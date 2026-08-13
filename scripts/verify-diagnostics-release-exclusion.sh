#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-}"
ZIP="${2:-}"
EXTRACTED="${3:-}"
MANIFEST="$ROOT/scripts/known-diagnostics-fixtures.txt"
TEMP_ROOT="$(mktemp -d -t instant-translation-diagnostics-exclusion)"
trap 'rm -rf "$TEMP_ROOT"' EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

[[ -d "$APP" ]] || fail "application bundle not found: $APP"
[[ -f "$ZIP" ]] || fail "release ZIP not found: $ZIP"
[[ -d "$EXTRACTED" ]] || fail "extracted release tree not found: $EXTRACTED"
[[ -r "$MANIFEST" ]] || fail "diagnostics fixture manifest is unreadable"

scan_tree() {
    local label="$1"
    local tree="$2"
    local paths="$TEMP_ROOT/${label}-paths.txt"
    local matches="$TEMP_ROOT/${label}-matches.txt"
    local path
    local marker

    if ! find "$tree" -print >"$paths"; then
        fail "could not enumerate $label"
    fi
    [[ -s "$paths" ]] || fail "$label scan set is empty"
    while IFS= read -r path; do
        case "$path" in
            *InstantTranslationDiagnostics*|*DiagnosticsScenario.swift*|*DiagnosticsScenarioTests*)
                fail "$label contains diagnostics path: ${path##*/}"
                ;;
        esac
    done <"$paths"

    while IFS= read -r marker || [[ -n "$marker" ]]; do
        [[ -n "$marker" ]] || continue
        if grep -R -a -F -l -- "$marker" "$tree" >"$matches"; then
            fail "$label contains diagnostics marker: $marker"
        else
            local status=$?
            [[ "$status" -eq 1 ]] || fail "could not scan $label for marker: $marker"
        fi
    done <"$MANIFEST"
}

ZIP_PATHS="$TEMP_ROOT/zip-paths.txt"
if ! unzip -Z1 "$ZIP" >"$ZIP_PATHS"; then
    fail "could not enumerate release ZIP"
fi
[[ -s "$ZIP_PATHS" ]] || fail "release ZIP scan set is empty"
while IFS= read -r path; do
    case "$path" in
        *InstantTranslationDiagnostics*|*DiagnosticsScenario.swift*|*DiagnosticsScenarioTests*)
            fail "release ZIP contains diagnostics path: ${path##*/}"
            ;;
    esac
done <"$ZIP_PATHS"

ZIP_TREE="$TEMP_ROOT/zip-tree"
mkdir -p "$ZIP_TREE"
if ! ditto -x -k "$ZIP" "$ZIP_TREE"; then
    fail "could not extract release ZIP"
fi

scan_tree "application bundle" "$APP"
scan_tree "provided extracted tree" "$EXTRACTED"
scan_tree "release ZIP" "$ZIP_TREE"

echo "diagnostics release exclusion passed"
