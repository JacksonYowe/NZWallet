// SPDX-License-Identifier: GPL-3.0-only
import UIKit
import LocalAuthentication
import CoreImage.CIFilterBuiltins

@MainActor
enum Biometrics {
    private(set) static var isAuthenticating = false
    /// Requires device-owner authentication. Unavailable authentication fails closed.
    static func confirm(reason: String) async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let ctx = LAContext()
        ctx.touchIDAuthenticationAllowableReuseDuration = 0
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return false }
        do { return try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) }
        catch { return false }
    }
}

enum QRCode {
    static func image(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let out = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

enum Mask {
    static func mask(_ v: String) -> String {
        guard v.count > 4 else { return "••••" }
        return String(repeating: "•", count: v.count - 3) + v.suffix(3)
    }
}
