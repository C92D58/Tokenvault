#!/usr/bin/env swift
//
//  TokenVault's app icon — one design, two idiomatic framings.
//
//      swift scripts/make-icon.swift macos        # Assets.xcassets PNGs + Resources/AppIcon.icns
//      swift scripts/make-icon.swift ios [path]   # 1024×1024 full-bleed PNG for the iOS asset
//
//  The mark is a vault door: a polished disc, four bolts, a keyhole. Drawn in Core Graphics so
//  every size is generated from the same geometry instead of resampled from a screenshot.
//
//  macOS wants the mark inside a margin with a soft shadow (the system does *not* mask it);
//  iOS wants it full-bleed (the system masks and rounds it). Same artwork, different frame.
//

import AppKit
import CoreGraphics
import Foundation

let canvas: CGFloat = 1024

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, a])!
}

/// The artwork itself, drawn edge to edge.
func drawMark(in ctx: CGContext) {
    let s = canvas
    let center = CGPoint(x: s * 0.5, y: s * 0.5)
    let cs = CGColorSpaceCreateDeviceRGB()

    // Background: deep teal → near-black petrol, lit from the top-left.
    let bg = CGGradient(colorsSpace: cs,
                        colors: [color(0.043, 0.220, 0.208), color(0.012, 0.078, 0.075), color(0.004, 0.028, 0.027)] as CFArray,
                        locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

    // Accent bloom behind the door — bright cyan, the brand's one loud colour.
    let bloom = CGGradient(colorsSpace: cs,
                           colors: [color(0.208, 0.882, 0.815, 0.50), color(0.208, 0.882, 0.815, 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawRadialGradient(bloom, startCenter: CGPoint(x: s * 0.5, y: s * 0.55), startRadius: 0,
                           endCenter: CGPoint(x: s * 0.5, y: s * 0.55), endRadius: s * 0.52, options: [])

    // Door plates.
    ctx.setLineWidth(s * 0.012)
    ctx.setStrokeColor(color(1, 1, 1, 0.20))
    var strokeAlpha: CGFloat = 0.20
    for r in [0.300, 0.352] {
        ctx.setStrokeColor(color(1, 1, 1, strokeAlpha))
        ctx.addArc(center: center, radius: s * CGFloat(r), startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()
        strokeAlpha = 0.10
    }

    // Polished disc.
    let faceRect = CGRect(x: center.x - s * 0.265, y: center.y - s * 0.265, width: s * 0.53, height: s * 0.53)
    ctx.saveGState()
    ctx.addPath(CGPath(ellipseIn: faceRect, transform: nil))
    ctx.clip()
    // The disc is polished cyan metal: bright at the top-left, deep teal at the bottom-right.
    let face = CGGradient(colorsSpace: cs,
                          colors: [color(0.639, 0.973, 0.937, 0.95), color(0.114, 0.741, 0.686, 0.95), color(0.024, 0.361, 0.337, 0.95)] as CFArray,
                          locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(face, start: CGPoint(x: faceRect.minX, y: faceRect.maxY),
                           end: CGPoint(x: faceRect.maxX, y: faceRect.minY), options: [])
    // Rim light along the top-left edge.
    ctx.setLineWidth(s * 0.018)
    ctx.setStrokeColor(color(1, 1, 1, 0.55))
    ctx.addArc(center: center, radius: s * 0.256, startAngle: .pi * 0.35, endAngle: .pi * 1.05, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    // Four bolts — the thing that reads "vault" at 16 px.
    ctx.setLineCap(.round)
    for angle in stride(from: 0.0, to: 360.0, by: 90.0) {
        let a = (angle + 45) * .pi / 180
        let inner = s * 0.115, outer = s * 0.225
        let p1 = CGPoint(x: center.x + cos(a) * inner, y: center.y + sin(a) * inner)
        let p2 = CGPoint(x: center.x + cos(a) * outer, y: center.y + sin(a) * outer)
        ctx.setLineWidth(s * 0.030)
        ctx.setStrokeColor(color(1, 1, 1, 0.92))
        ctx.move(to: p1); ctx.addLine(to: p2); ctx.strokePath()
        ctx.setFillColor(color(1, 1, 1, 0.92))
        ctx.fillEllipse(in: CGRect(x: p2.x - s * 0.026, y: p2.y - s * 0.026,
                                   width: s * 0.052, height: s * 0.052))
    }

    // Keyhole: a dot with a stem.
    ctx.setFillColor(color(0.008, 0.055, 0.052, 0.92))
    let holeR = s * 0.052
    ctx.fillEllipse(in: CGRect(x: center.x - holeR, y: center.y - holeR + s * 0.012,
                               width: holeR * 2, height: holeR * 2))
    let stem = CGRect(x: center.x - s * 0.020, y: center.y - s * 0.115,
                      width: s * 0.040, height: s * 0.125)
    ctx.addPath(CGPath(roundedRect: stem, cornerWidth: s * 0.020, cornerHeight: s * 0.020, transform: nil))
    ctx.fillPath()

    // Vignette, so the corners stop glowing.
    let vignette = CGGradient(colorsSpace: cs,
                              colors: [color(0, 0, 0, 0), color(0, 0, 0, 0.42)] as CFArray,
                              locations: [0.55, 1])!
    ctx.drawRadialGradient(vignette, startCenter: center, startRadius: s * 0.32,
                           endCenter: center, endRadius: s * 0.72, options: [])
}

func context(size: Int) -> CGContext {
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("no context")
    }
    ctx.interpolationQuality = .high
    return ctx
}

func png(_ image: CGImage) -> Data {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
    return data
}

func write(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    try! png(image).write(to: url)
}

/// The full-bleed artwork (iOS).
func renderBleed(size: Int) -> CGImage {
    let ctx = context(size: size)
    let scale = CGFloat(size) / canvas
    ctx.scaleBy(x: scale, y: scale)
    drawMark(in: ctx)
    guard let image = ctx.makeImage() else { fatalError("no image") }
    return image
}

/// The macOS framing: rounded rect with a margin, a soft cast shadow and a top inner light.
func renderMacMaster() -> CGImage {
    let size = Int(canvas)
    let ctx = context(size: size)
    let margin: CGFloat = 100  // Apple's Big Sur grid: an 824 px tile on a 1024 px canvas
    let rect = CGRect(x: margin, y: margin, width: canvas - margin * 2, height: canvas - margin * 2)
    let radius = rect.width * 0.2237  // the Big Sur squircle ratio

    let art = renderBleed(size: size)
    let body = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Cast shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -canvas * 0.012),
                  blur: canvas * 0.026,
                  color: color(0, 0, 0, 0.45))
    ctx.addPath(body)
    ctx.setFillColor(color(0.008, 0.055, 0.052, 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Artwork clipped to the tile.
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    ctx.draw(art, in: rect)
    ctx.restoreGState()

    // Inner hairline so the tile edge reads on any wallpaper.
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 1, dy: 1),
                       cornerWidth: radius - 1, cornerHeight: radius - 1, transform: nil))
    ctx.setLineWidth(2)
    ctx.setStrokeColor(color(1, 1, 1, 0.18))
    ctx.strokePath()
    ctx.restoreGState()

    guard let image = ctx.makeImage() else { fatalError("no image") }
    return image
}

func scaled(_ image: CGImage, to px: Int) -> CGImage {
    let ctx = context(size: px)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: px, height: px))
    guard let out = ctx.makeImage() else { fatalError("no image") }
    return out
}

// MARK: - Entry point

let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "macos"
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

switch mode {
case "ios", "ios-bleed":
    let path = args.count > 2
        ? args[2]
        : root.appendingPathComponent("iOS/TokenVault/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png").path
    write(renderBleed(size: 1024), to: path)
    print("wrote \(path)")

case "macos":
    let master = renderMacMaster()
    let assetDir = root.appendingPathComponent("Assets.xcassets/AppIcon.appiconset").path
    let sizes: [(name: String, px: Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]
    for item in sizes {
        write(scaled(master, to: item.px), to: "\(assetDir)/\(item.name).png")
    }
    print("wrote \(sizes.count) PNGs to \(assetDir)")

    // .icns, via iconutil, so the DMG and Finder get the same artwork.
    let iconset = NSTemporaryDirectory() + "TokenVault.iconset"
    try? FileManager.default.removeItem(atPath: iconset)
    try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
    let icnsNames: [(name: String, px: Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]
    for item in icnsNames {
        write(scaled(master, to: item.px), to: "\(iconset)/\(item.name).png")
    }
    let icnsPath = root.appendingPathComponent("Resources/AppIcon.icns").path
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", iconset, "-o", icnsPath]
    try? task.run()
    task.waitUntilExit()
    print("wrote \(icnsPath)")

default:
    FileHandle.standardError.write(Data("usage: make-icon.swift [macos|ios [path]]\n".utf8))
    exit(2)
}
