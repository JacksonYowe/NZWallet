// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreGraphics
import ImageIO
import CoreText

/// Placeholder ID photo as JPEG bytes (the mDL `portrait` element is mandatory).
/// Same neutral silhouette as the on-screen placeholder; no real person.
enum DemoPortrait {
    static let jpeg: Data = {
        let w = 240, h = 320
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return Data() }
        ctx.setFillColor(CGColor(red: 0.85, green: 0.88, blue: 0.93, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 0.47, green: 0.53, blue: 0.61, alpha: 1))
        let head = CGFloat(w) * 0.44
        ctx.fillEllipse(in: CGRect(x: (CGFloat(w) - head) / 2, y: CGFloat(h) * 0.63 - head / 2, width: head, height: head))
        ctx.fillEllipse(in: CGRect(x: CGFloat(w) * 0.04, y: -CGFloat(h) * 0.23, width: CGFloat(w) * 0.92, height: CGFloat(h) * 0.5))
        let bandHeight = CGFloat(h) * 0.30
        ctx.setFillColor(CGColor(gray: 0.08, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(w), height: bandHeight))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, min(CGFloat(w) * 0.27, bandHeight * 0.8), nil)
        let text = NSAttributedString(string: "TEST", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
        ])
        let line = CTLineCreateWithAttributedString(text)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        ctx.textPosition = CGPoint(x: (CGFloat(w) - bounds.width) / 2 - bounds.minX,
                                       y: (bandHeight - bounds.height) / 2 - bounds.minY)
        CTLineDraw(line, ctx)
        guard let img = ctx.makeImage() else { return Data() }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else { return Data() }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return out as Data
    }()
}

/// Loads local raster paths or bundled relative filenames. Orientation is normalized and dimensions
/// are capped before encoding so UI and mDL share the same portrait bytes.
/// Supplied images receive no TEST text, watermark or other overlay.
enum DemoLicenceImages {
    static func image(named name: String?, bundle: Bundle = .main) -> CGImage? {
        guard let name, !name.isEmpty else { return nil }
        let path = (name as NSString).expandingTildeInPath
        guard ["png", "jpg", "jpeg"].contains((path as NSString).pathExtension.lowercased()) else { return nil }
        let url: URL?
        if (path as NSString).isAbsolutePath {
            url = URL(fileURLWithPath: path)
        } else {
            url = bundle.url(forResource: path, withExtension: nil)
        }
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048
        ] as CFDictionary)
    }

    static func encoded(_ image: CGImage, type: String) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    static func portrait(named name: String?) -> Data {
        let source = image(named: name) ?? CGImageSourceCreateWithData(DemoPortrait.jpeg as CFData, nil)
            .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        guard let source else { return Data() }
        return encoded(source, type: "public.jpeg") ?? Data()
    }

    static func signature(named name: String?) -> Data {
        if let image = image(named: name), let data = encoded(image, type: "public.png") { return data }
        return sampleSignature
    }

    /// Fictional "TEST" lettering, rendered to a transparent PNG locally.
    static let sampleSignature: Data = {
        guard let context = CGContext(data: nil, width: 600, height: 180,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return Data() }
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 100, nil)
        let text = NSAttributedString(string: "TEST", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                CGColor(red: 0.12, green: 0.17, blue: 0.20, alpha: 1)
        ])
        context.textPosition = CGPoint(x: 24, y: 45)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        guard let image = context.makeImage() else { return Data() }
        return encoded(image, type: "public.png") ?? Data()
    }()
}
