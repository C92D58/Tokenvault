#!/usr/bin/env swift
//
//  Composes App Store screenshots (1320×2868, the 6.9" slot) from raw simulator captures.
//
//      swift scripts/make-store-shots.swift <raw-dir> <out-dir>
//
//  Raw captures keep the app's own pixels; this only adds the brand frame: a headline, a deep teal
//  ground, and the device screen bleeding into the bottom edge. Regenerate rather than retouch.
//

import AppKit
import CoreGraphics
import Foundation

let canvasW: CGFloat = 1320
let canvasH: CGFloat = 2868

// MARK: - Copy

struct Shot {
    let file: String
    let title: [String]
    let subtitle: String
}

let shots: [Shot] = [
    Shot(file: "00-lock.png",
         title: ["API 金鑰，", "鎖在這台裝置"],
         subtitle: "AES-256-GCM 加密 · Face ID 解鎖"),
    Shot(file: "01-vault.png",
         title: ["所有密鑰，", "一個保險庫"],
         subtitle: "搜尋、分類、收藏 · 滑動即複製"),
    Shot(file: "02-detail.png",
         title: ["複製之後，", "45 秒自動清除"],
         subtitle: "剪貼板不留殘影 · 明文只在需要時出現"),
    Shot(file: "04-tools.png",
         title: ["產生、解碼、檢查", "都在本機"],
         subtitle: "金鑰產生器 · JWT 解碼 · Token 健康檢查"),
    Shot(file: "06-log.png",
         title: ["每一次存取", "都留下紀錄"],
         subtitle: "本機稽核日誌 · 不上傳、不同步"),
    Shot(file: "05-settings.png",
         title: ["零知識", "沒有伺服器"],
         subtitle: "沒有帳號、沒有分析、沒有追蹤"),
]

// MARK: - Helpers

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, a])!
}

func context() -> CGContext {
    let ctx = CGContext(data: nil, width: Int(canvasW), height: Int(canvasH),
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    return ctx
}

/// Top-left based rect → CG (bottom-left origin).
func rect(x: CGFloat, top: CGFloat, w: CGFloat, h: CGFloat) -> CGRect {
    CGRect(x: x, y: canvasH - top - h, width: w, height: h)
}

// MARK: - Drawing

func drawBackground(_ ctx: CGContext) {
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [color(0.012, 0.055, 0.052), color(0.024, 0.102, 0.098), color(0.008, 0.035, 0.034)] as CFArray,
                        locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: canvasH), end: CGPoint(x: canvasW, y: 0), options: [])

    // Cyan bloom behind the device's top edge.
    let bloom = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [color(0.208, 0.882, 0.815, 0.30), color(0.208, 0.882, 0.815, 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawRadialGradient(bloom,
                           startCenter: CGPoint(x: canvasW * 0.5, y: canvasH * 0.72), startRadius: 0,
                           endCenter: CGPoint(x: canvasW * 0.5, y: canvasH * 0.72), endRadius: canvasW * 0.62,
                           options: [])

    // Faint top rule so the headline never floats in a void.
    ctx.setFillColor(color(1, 1, 1, 0.06))
    ctx.fill(CGRect(x: 112, y: canvasH - 118, width: canvasW - 224, height: 1))
}

func drawText(_ ctx: CGContext, _ text: String, font: NSFont, tint: CGColor,
              at point: CGPoint, width: CGFloat, lineSpacing: CGFloat = 8, tracking: CGFloat = 0) {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = lineSpacing
    style.alignment = .left
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(cgColor: tint)!,
        .paragraphStyle: style,
        .kern: tracking,
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let measured = attributed.boundingRect(with: CGSize(width: width, height: 1000),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading])
    let target = CGRect(x: point.x, y: canvasH - point.y - measured.height,
                        width: width, height: measured.height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    attributed.draw(in: target)
    NSGraphicsContext.restoreGraphicsState()
}

func drawHeadline(_ ctx: CGContext, _ shot: Shot) {
    let titleFont = NSFont.systemFont(ofSize: 74, weight: .bold)
    let subFont = NSFont.systemFont(ofSize: 34, weight: .regular)

    drawText(ctx, shot.title.joined(separator: "\n"), font: titleFont,
             tint: color(1, 1, 1, 0.97), at: CGPoint(x: 112, y: 158), width: canvasW - 224,
             lineSpacing: 12, tracking: -1.2)
    drawText(ctx, shot.subtitle, font: subFont,
             tint: color(0.78, 0.74, 0.92, 0.72), at: CGPoint(x: 112, y: 352),
             width: canvasW - 224, lineSpacing: 6)
}

func drawDevice(_ ctx: CGContext, image: CGImage, top: CGFloat) {
    let margin: CGFloat = 110
    let width = canvasW - margin * 2
    let height = width * canvasH / canvasW
    let frame = rect(x: margin, top: top, w: width, h: height)
    let radius: CGFloat = 66
    let path = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Cast shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 64, color: color(0, 0, 0, 0.62))
    ctx.addPath(path)
    ctx.setFillColor(color(0.03, 0.025, 0.05))
    ctx.fillPath()
    ctx.restoreGState()

    // Screen.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.draw(image, in: frame)
    ctx.restoreGState()

    // Hairline edge.
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5),
                       cornerWidth: radius - 0.5, cornerHeight: radius - 0.5, transform: nil))
    ctx.setLineWidth(1.5)
    ctx.setStrokeColor(color(1, 1, 1, 0.16))
    ctx.strokePath()
    ctx.restoreGState()
}

// MARK: - Entry point

let args = CommandLine.arguments
let rawDir = args.count > 1 ? args[1] : "build/store-raw"
let outDir = args.count > 2 ? args[2] : "build/store"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

var made = 0
for (index, shot) in shots.enumerated() {
    let source = "\(rawDir)/\(shot.file)"
    guard let nsImage = NSImage(contentsOfFile: source),
          let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("skip \(shot.file) — not found at \(source)")
        continue
    }

    let ctx = context()
    drawBackground(ctx)
    drawHeadline(ctx, shot)
    drawDevice(ctx, image: cgImage, top: 470)

    guard let out = ctx.makeImage() else { continue }
    let rep = NSBitmapImageRep(cgImage: out)
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    let name = String(format: "%02d-store-%d.png", index + 1, Int(canvasW))
    let path = "\(outDir)/\(name)"
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)  (\(Int(canvasW))×\(Int(canvasH)))  from \(shot.file)")
    made += 1
}
print("done — \(made) images")
