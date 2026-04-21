#!/usr/bin/env swift
//
// Regenerates Sources/Yojam/Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png
// from scripts/icon-source/yojam-icon-source-1024.png by applying the macOS
// app icon template: scale the source into an 824/1024 safe area centered
// on a transparent canvas, and clip to a continuous-corner squircle.
//
// Run from the repo root:    swift scripts/regenerate-app-icon.swift
//
// macOS does not auto-mask app icons (unlike iOS), so the squircle and the
// transparent safe-area padding must be baked into each PNG. Without them
// the icon renders as a full-bleed square in Cmd+Tab and looks larger and
// boxier than every other macOS app.

import AppKit
import QuartzCore

let repoRoot = FileManager.default.currentDirectoryPath
let assetDir = "\(repoRoot)/Sources/Yojam/Resources/Assets.xcassets/AppIcon.appiconset"
let sourcePath = "\(repoRoot)/scripts/icon-source/yojam-icon-source-1024.png"

guard let nsImage = NSImage(contentsOfFile: sourcePath),
      let sourceCG = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("ERROR: cannot load source image at \(sourcePath)\n".utf8))
    exit(1)
}

// Apple's macOS app icon template proportions. The 824/1024 safe area and
// 22.37% corner radius match Apple's published Production Templates and the
// iOS/macOS continuous-squircle ratio.
let safeAreaRatio: CGFloat = 824.0 / 1024.0
let cornerRadiusRatio: CGFloat = 0.2237
let sizes: [Int] = [16, 32, 64, 128, 256, 512, 1024]

func renderIcon(size: Int) -> Data? {
    let canvas = CGFloat(size)
    let safe = canvas * safeAreaRatio
    let inset = (canvas - safe) / 2
    let radius = safe * cornerRadiusRatio

    // Render via CALayer so we get the continuous-curvature corner that
    // matches Apple's app icon shape (cornerCurve = .continuous), instead
    // of the circular-arc corners produced by CGPath(roundedRect:...).
    let outer = CALayer()
    outer.frame = CGRect(x: 0, y: 0, width: canvas, height: canvas)
    outer.backgroundColor = NSColor.clear.cgColor

    let inner = CALayer()
    inner.frame = CGRect(x: inset, y: inset, width: safe, height: safe)
    inner.contents = sourceCG
    inner.contentsGravity = .resize
    inner.cornerRadius = radius
    inner.cornerCurve = .continuous
    inner.masksToBounds = true
    inner.minificationFilter = .trilinear
    inner.magnificationFilter = .trilinear
    outer.addSublayer(inner)

    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(
            data: nil,
            width: size, height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        return nil
    }
    ctx.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))
    ctx.interpolationQuality = .high
    outer.render(in: ctx)

    guard let cg = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: cg)
    rep.size = NSSize(width: canvas, height: canvas)
    return rep.representation(using: .png, properties: [:])
}

for size in sizes {
    guard let data = renderIcon(size: size) else {
        FileHandle.standardError.write(Data("ERROR rendering size \(size)\n".utf8))
        exit(1)
    }
    let outPath = "\(assetDir)/icon_\(size)x\(size).png"
    do {
        try data.write(to: URL(fileURLWithPath: outPath))
        print("Wrote icon_\(size)x\(size).png — \(data.count) bytes")
    } catch {
        FileHandle.standardError.write(Data("ERROR writing \(outPath): \(error)\n".utf8))
        exit(1)
    }
}
print("Done.")
