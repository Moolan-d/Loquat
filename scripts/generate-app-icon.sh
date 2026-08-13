#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SOURCE="$ROOT/Design/AppIcon.svg"
OUTPUT="$ROOT/Config/Loquat.icns"

if [[ ! -f "$SOURCE" ]]; then
    echo "error: icon source not found: $SOURCE" >&2
    exit 66
fi

WORK="$(mktemp -d -t loquat-icon)"
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/Loquat.iconset"
mkdir -p "$ICONSET"

# 环境里没有 rsvg-convert/inkscape 一类的栅格化工具，AppKit 自带的 SVG 解码
# 已验证能正确还原线性/径向渐变与高斯模糊，因此直接用它当栅格化器。
cat > "$WORK/rasterize.swift" <<'SWIFT'
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: rasterize <svg> <iconset-dir>\n".utf8))
    exit(64)
}
let sourceURL = URL(fileURLWithPath: arguments[1])
let outputDirectory = URL(fileURLWithPath: arguments[2])

guard let image = NSImage(contentsOf: sourceURL) else {
    FileHandle.standardError.write(Data("error: could not decode \(sourceURL.path)\n".utf8))
    exit(65)
}

// .icns 要求每个尺寸都有 1x 与 2x，@2x 的像素尺寸等于下一档的 1x。
let variants: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2),
    (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

for variant in variants {
    let pixels = variant.points * variant.scale
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        FileHandle.standardError.write(Data("error: could not allocate \(pixels)px bitmap\n".utf8))
        exit(70)
    }
    representation.size = NSSize(width: pixels, height: pixels)

    guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
        FileHandle.standardError.write(Data("error: could not create drawing context\n".utf8))
        exit(70)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = representation.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("error: could not encode \(pixels)px PNG\n".utf8))
        exit(70)
    }
    let suffix = variant.scale == 1 ? "" : "@2x"
    let name = "icon_\(variant.points)x\(variant.points)\(suffix).png"
    try data.write(to: outputDirectory.appendingPathComponent(name))
}
SWIFT

swift "$WORK/rasterize.swift" "$SOURCE" "$ICONSET"
iconutil --convert icns --output "$OUTPUT" "$ICONSET"

echo "$OUTPUT"
