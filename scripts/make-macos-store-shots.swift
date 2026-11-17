#!/usr/bin/env swift
// Composes 2880×1800 App Store images from the raw window captures produced by
// `TokenVault --capture-shots <dir>`.
//
//   swift scripts/make-macos-store-shots.swift <raw-dir> <out-dir>

import AppKit
import CoreGraphics
import Foundation

let W: CGFloat = 2880
let H: CGFloat = 1800

struct Shot {
    let file: String
    let title: String
    let subtitle: String
    let maxHeight: CGFloat
}

let englishTitles = [
    "01-main.png": ("Every API key in one place", "AES-256 encryption · Touch ID · iCloud backup"),
    "03-lock.png": ("Nobody gets in without you", "AES-256-GCM · key in the keychain · auto-lock"),
    "04-about.png": ("Built for developers", "Native SwiftUI · zero dependencies · MIT"),
]

let shots: [Shot] = [
    .init(file: "01-main.png", title: "所有 API 密鑰，一個地方",
          subtitle: "AES-256 加密 · Touch ID 解鎖 · iCloud 自動備份", maxHeight: 1390),
    .init(file: "03-lock.png", title: "沒有你，誰都打不開",
          subtitle: "AES-256-GCM · 金鑰存於鑰匙圈 · 逾時自動鎖定", maxHeight: 1180),
    .init(file: "04-about.png", title: "為開發者而做",
          subtitle: "原生 SwiftUI · 零依賴 · 開源 MIT", maxHeight: 1180),
]

let useEnglish = CommandLine.arguments.count >= 4 && CommandLine.arguments[3] == "en"

guard CommandLine.arguments.count >= 3 else {
    print("usage: make-macos-store-shots.swift <raw-dir> <out-dir>")
    exit(1)
}
let rawDir = URL(fileURLWithPath: CommandLine.arguments[1])
let outDir = URL(fileURLWithPath: CommandLine.arguments[2])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func drawBackground(_ ctx: CGContext) {
    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: space,
                              colors: [color(0x04100F).cgColor, color(0x08201E).cgColor,
                                       color(0x0B2E2A).cgColor] as CFArray,
                              locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: H),
                           end: CGPoint(x: W, y: 0), options: [])

    // Cyan glow behind the window.
    let glow = CGGradient(colorsSpace: space,
                          colors: [color(0x35E1D0, 0.38).cgColor, color(0x35E1D0, 0).cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow,
                           startCenter: CGPoint(x: W * 0.5, y: H * 0.42), startRadius: 0,
                           endCenter: CGPoint(x: W * 0.5, y: H * 0.42), endRadius: W * 0.62,
                           options: [])

    // Warm ember bottom-left, keeps it from reading as generic cyan SaaS.
    let ember = CGGradient(colorsSpace: space,
                           colors: [color(0xF97316, 0.13).cgColor, color(0xF97316, 0).cgColor] as CFArray,
                           locations: [0, 1])!
    ctx.drawRadialGradient(ember,
                           startCenter: CGPoint(x: W * 0.06, y: H * 0.04), startRadius: 0,
                           endCenter: CGPoint(x: W * 0.06, y: H * 0.04), endRadius: W * 0.45,
                           options: [])
}

func drawText(_ text: String, font: NSFont, color: NSColor, centerX: CGFloat, top: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let size = (text as NSString).size(withAttributes: attrs)
    (text as NSString).draw(at: NSPoint(x: centerX - size.width / 2, y: top), withAttributes: attrs)
}

func rounded(_ rect: CGRect, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

func compose(_ shot: Shot, index: Int) -> Bool {
    let source = rawDir.appendingPathComponent(shot.file)
    guard let image = NSImage(contentsOf: source),
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let cgRaw = rep.cgImage else {
        print("skip \(shot.file): cannot read")
        return false
    }

    guard let ctx = CGContext(data: nil, width: Int(W), height: Int(H),
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
    let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ns

    drawBackground(ctx)

    let scale = min(1, shot.maxHeight / CGFloat(cgRaw.height))
    let winW = CGFloat(cgRaw.width) * scale
    let winH = CGFloat(cgRaw.height) * scale
    let winX = (W - winW) / 2
    let winY = H - 360 - winH

    // Soft shadow, then the window with its own corners.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 90,
                  color: NSColor.black.withAlphaComponent(0.55).cgColor)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(rounded(CGRect(x: winX, y: winY, width: winW, height: winH), 26 * scale))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(rounded(CGRect(x: winX, y: winY, width: winW, height: winH), 26 * scale))
    ctx.clip()
    ctx.draw(cgRaw, in: CGRect(x: winX, y: winY, width: winW, height: winH))
    ctx.restoreGState()

    // 1px hairline so the dark window still separates from the dark background.
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.14).cgColor)
    ctx.setLineWidth(2)
    ctx.addPath(rounded(CGRect(x: winX + 1, y: winY + 1, width: winW - 2, height: winH - 2), 26 * scale))
    ctx.strokePath()

    drawText(shot.title, font: .systemFont(ofSize: 96, weight: .semibold),
             color: NSColor.white, centerX: W / 2, top: H - 210)
    drawText(shot.subtitle, font: .systemFont(ofSize: 44, weight: .regular),
             color: NSColor.white.withAlphaComponent(0.62), centerX: W / 2, top: H - 296)

    NSGraphicsContext.restoreGraphicsState()

    guard let out = ctx.makeImage() else { return false }
    let outRep = NSBitmapImageRep(cgImage: out)
    guard let png = outRep.representation(using: .png, properties: [:]) else { return false }
    let target = outDir.appendingPathComponent(shot.file)
    try? png.write(to: target)
    print("→ \(target.lastPathComponent) \(Int(W))x\(Int(H))")
    return true
}

var made = 0
for (i, var shot) in shots.enumerated() {
    if useEnglish, let titles = englishTitles[shot.file] {
        shot = Shot(file: shot.file, title: titles.0, subtitle: titles.1, maxHeight: shot.maxHeight)
    }
    if compose(shot, index: i) { made += 1 }
}
print("done: \(made)/\(shots.count)")
