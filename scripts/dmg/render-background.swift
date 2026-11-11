// Renders the WhisperFly disk-image background.
//
//   swift scripts/dmg/render-background.swift <out-dir> <version> [preview-app]
//
// Writes background.png (1x) and background@2x.png into <out-dir>; make-dmg.sh
// combines them into a HiDPI TIFF. With [preview-app], also writes preview.png:
// the background with the real icons and both label colours drawn on, to check
// the layout without opening Finder.
//
// Finder draws the icon labels itself — black in light mode, white in dark
// mode — so the area under each label is kept mid-tone, where both read. The
// script prints the measured contrast and fails below 4:1.
//
// Geometry must match scripts/dmg/settings.py.

import AppKit
import SwiftUI

let canvas = CGSize(width: 660, height: 420)
let appCenter = CGPoint(x: 180, y: 212)
let applicationsCenter = CGPoint(x: 480, y: 212)
let iconSize: CGFloat = 128

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: render-background.swift <out-dir> <version> [preview-app]\n".utf8))
    exit(2)
}
let outDir = URL(fileURLWithPath: arguments[1], isDirectory: true)
let version = arguments[2]
let previewApp = arguments.count > 3 ? arguments[3] : nil

// MARK: - Design

struct Background: View {
    let version: String

    var body: some View {
        ZStack {
            // Base: deep violet to blue, mid-tone where the labels sit.
            LinearGradient(
                colors: [Color(red: 0.33, green: 0.27, blue: 0.80), Color(red: 0.45, green: 0.27, blue: 0.74), Color(red: 0.24, green: 0.33, blue: 0.74)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            // Soft light fields for the glass to sit on.
            Circle().fill(Color(red: 1.0, green: 0.55, blue: 0.75).opacity(0.55))
                .frame(width: 330).blur(radius: 70).offset(x: -250, y: -190)
            Circle().fill(Color(red: 0.45, green: 0.85, blue: 1.0).opacity(0.40))
                .frame(width: 260).blur(radius: 70).offset(x: 330, y: 230)
            Circle().fill(Color(red: 1.0, green: 0.78, blue: 0.45).opacity(0.30))
                .frame(width: 220).blur(radius: 60).offset(x: 250, y: -170)

            // Glass plates behind the two icons.
            plate.position(x: appCenter.x, y: appCenter.y + 12)
            plate.position(x: applicationsCenter.x, y: applicationsCenter.y + 12)

            arrow.position(x: (appCenter.x + applicationsCenter.x) / 2, y: appCenter.y)

            VStack(spacing: 6) {
                Text("WhisperFly")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Drag WhisperFly into Applications to install")
                    .font(.system(size: 13.5, weight: .medium))
                    .opacity(0.88)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            .position(x: canvas.width / 2, y: 62)

            HStack(spacing: 8) {
                chip("keyboard", "Hold fn to dictate")
                chip("cpu", "Intel & Apple silicon")
                chip("macwindow", "macOS 13 or later")
            }
            .position(x: canvas.width / 2, y: 352)

            Text("Version \(version)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .position(x: canvas.width / 2, y: 383)
        }
        .frame(width: canvas.width, height: canvas.height)
        .clipped()
    }

    private var plate: some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .fill(
                LinearGradient(colors: [.white.opacity(0.20), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            .frame(width: 176, height: 196)
    }

    private var arrow: some View {
        HStack(spacing: 7) {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(0.30 + 0.17 * Double(index)))
                    .frame(width: 7, height: 7)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
    }

    private func chip(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(.white.opacity(0.16))
                .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.8))
        )
    }
}

/// The background plus the real icons and sample labels, for review.
struct Preview: View {
    let version: String
    let appIcon: NSImage
    let folderIcon: NSImage
    let darkLabels: Bool

    var body: some View {
        ZStack {
            Background(version: version)
            icon(appIcon, "WhisperFly", at: appCenter)
            icon(folderIcon, "Applications", at: applicationsCenter)
        }
        .frame(width: canvas.width, height: canvas.height)
    }

    private func icon(_ image: NSImage, _ label: String, at point: CGPoint) -> some View {
        VStack(spacing: 6) {
            Image(nsImage: image).resizable().frame(width: iconSize, height: iconSize)
            Text(label).font(.system(size: 13)).foregroundStyle(darkLabels ? .white : .black)
        }
        .position(x: point.x, y: point.y + 12)
    }
}

// MARK: - Output

@MainActor
func render<V: View>(_ view: V, scale: CGFloat) -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    guard let cgImage = renderer.cgImage else {
        FileHandle.standardError.write(Data("render failed\n".utf8))
        exit(1)
    }
    // Redraw into an 8-bit sRGB bitmap: CoreGraphics converts (and tone-maps)
    // whatever space the renderer chose.
    let width = cgImage.width, height = cgImage.height
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { exit(1) }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    rep.size = NSSize(width: canvas.width, height: canvas.height)   // 72 / 144 dpi
    return rep
}

@MainActor
func write(_ rep: NSBitmapImageRep, _ name: String) {
    let url = outDir.appendingPathComponent(name)
    guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
    do { try data.write(to: url) } catch { print("write failed: \(error)"); exit(1) }
    print("wrote \(url.path) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
}

/// System icons can carry HDR representations, which pull the whole render into
/// an HDR colour space; flatten them to a 256 px sRGB bitmap first.
@MainActor
func sRGBIcon(_ image: NSImage) -> NSImage {
    let pixels = 256
    var rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
    guard let source = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
          let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
    context.draw(source, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    return NSImage(cgImage: context.makeImage()!, size: NSSize(width: iconSize, height: iconSize))
}

/// WCAG contrast of black and white text against the average colour of `rect`.
@MainActor
func labelContrast(_ rep: NSBitmapImageRep, rect: CGRect) -> (black: Double, white: Double) {
    func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    var r = 0.0, g = 0.0, b = 0.0, n = 0.0
    for y in Int(rect.minY)..<Int(rect.maxY) {
        for x in Int(rect.minX)..<Int(rect.maxX) {
            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            r += color.redComponent; g += color.greenComponent; b += color.blueComponent; n += 1
        }
    }
    let luminance = 0.2126 * linear(r / n) + 0.7152 * linear(g / n) + 0.0722 * linear(b / n)
    return ((luminance + 0.05) / 0.05, 1.05 / (luminance + 0.05))
}

MainActor.assumeIsolated {
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let oneX = render(Background(version: version), scale: 1)
    write(oneX, "background.png")
    write(render(Background(version: version), scale: 2), "background@2x.png")

    // Finder puts a 13 pt label just under each 128 pt icon.
    var worst = Double.infinity
    for (name, center) in [("WhisperFly", appCenter), ("Applications", applicationsCenter)] {
        let rect = CGRect(x: center.x - 50, y: center.y + iconSize / 2 + 6, width: 100, height: 16)
        let contrast = labelContrast(oneX, rect: rect)
        worst = min(worst, contrast.black, contrast.white)
        print(String(format: "label contrast under %@: black %.1f:1, white %.1f:1", name, contrast.black, contrast.white))
    }
    if worst < 4.0 {
        print("ERROR: a label would be hard to read in light or dark mode")
        exit(1)
    }

    if let previewApp {
        let appIcon = sRGBIcon(NSWorkspace.shared.icon(forFile: previewApp))
        let folderIcon = sRGBIcon(NSWorkspace.shared.icon(forFile: "/Applications"))
        write(render(Preview(version: version, appIcon: appIcon, folderIcon: folderIcon, darkLabels: false), scale: 2), "preview-light.png")
        write(render(Preview(version: version, appIcon: appIcon, folderIcon: folderIcon, darkLabels: true), scale: 2), "preview-dark.png")
    }
}
