#!/bin/bash
set -e

echo "🎨 Generating emoji icon..."

# Create iconset directory
ICONSET="Resources/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Create temporary Swift script
cat > /tmp/generate_icon.swift <<'SWIFT_CODE'
import AppKit

func renderEmoji(_ emoji: String, size: CGFloat, scale: CGFloat, filename: String) {
    let pixelSize = size * scale
    let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize))

    image.lockFocus()

    let font = NSFont.systemFont(ofSize: pixelSize * 0.8)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font
    ]

    let textSize = (emoji as NSString).size(withAttributes: attributes)
    let x = (pixelSize - textSize.width) / 2
    let y = (pixelSize - textSize.height) / 2

    (emoji as NSString).draw(
        at: NSPoint(x: x, y: y),
        withAttributes: attributes
    )

    image.unlockFocus()

    if let tiffData = image.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiffData),
       let pngData = bitmap.representation(using: .png, properties: [:]) {
        try? pngData.write(to: URL(fileURLWithPath: filename))
    }
}

let emoji = "🙌🏾"
let iconset = "Resources/AppIcon.iconset"

let configs: [(CGFloat, CGFloat, String)] = [
    (16, 1, "icon_16x16.png"),
    (32, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (64, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (256, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (512, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (1024, 2, "icon_512x512@2x.png"),
]

for (size, scale, filename) in configs {
    let path = "\(iconset)/\(filename)"
    renderEmoji(emoji, size: size, scale: scale, filename: path)
    print("Generated \(filename)")
}
SWIFT_CODE

# Run the Swift script
swift /tmp/generate_icon.swift

# Convert iconset to icns
echo "📦 Converting to .icns format..."
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns

echo "✅ Icon generation complete!"
