#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENARIO="${1:-}"
if [[ -z "$SCENARIO" ]]; then
    echo "usage: scripts/run-diagnostics.sh <scenario>" >&2
    exit 64
fi
cd "$ROOT"
exec swift run InstantTranslationDiagnostics "$SCENARIO"
