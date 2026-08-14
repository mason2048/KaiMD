#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: generate_icon.swift <source-image> <iconset-directory>\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)

guard let sourceImage = NSImage(contentsOf: sourceURL),
      sourceImage.size.width > 0,
      sourceImage.size.height > 0 else {
    fputs("error: unable to load icon source at \(sourceURL.path)\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func resizeIcon(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "KaiMD.Icon", code: 1)
    }

    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }

    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high

    let canvas = CGFloat(size)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()
    sourceImage.draw(
        in: NSRect(x: 0, y: 0, width: canvas, height: canvas),
        from: NSRect(origin: .zero, size: sourceImage.size),
        operation: .copy,
        fraction: 1,
        respectFlipped: true,
        hints: nil
    )

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "KaiMD.Icon", code: 2)
    }
    return data
}

for (name, size) in variants {
    let data = try resizeIcon(size: size)
    try data.write(to: outputDirectory.appendingPathComponent(name), options: .atomic)
}
