import Foundation
import SwiftUI
import AppKit

// MARK: - Screen Capture Store
// Full-screen capture utility. Grabs the entire display so Andrew can show
// Thrawn external docs, websites, or anything else on screen — not just the app window.

@MainActor
final class ScreenCaptureStore: ObservableObject {
    @Published var pendingScreenshot: Data?
    @Published var pendingThumbnail: NSImage?
    @Published var isCapturing = false
    @Published var captureError: String?

    /// Capture the entire main display, downscale to reasonable size, encode as JPEG.
    func captureFullScreen() {
        isCapturing = true
        captureError = nil

        // CGDisplayCreateImage captures the full screen (requires Screen Recording permission)
        guard let cgImage = CGDisplayCreateImage(CGMainDisplayID()) else {
            captureError = "Screen capture failed — grant Screen Recording permission in System Settings > Privacy."
            isCapturing = false
            return
        }

        // Downscale to max 1920px wide for a reasonable payload (~200-400KB JPEG)
        let maxWidth: CGFloat = 1920
        let origW = CGFloat(cgImage.width)
        let origH = CGFloat(cgImage.height)
        let scale = min(1.0, maxWidth / origW)
        let newW = Int(origW * scale)
        let newH = Int(origH * scale)

        // Draw into a new bitmap at the target size
        guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: newW,
                  height: newH,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            captureError = "Could not create graphics context for resize."
            isCapturing = false
            return
        }

        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: newW, height: newH))

        guard let resized = ctx.makeImage() else {
            captureError = "Resize failed."
            isCapturing = false
            return
        }

        // Encode as JPEG (much smaller than PNG for screenshots)
        let bitmapRep = NSBitmapImageRep(cgImage: resized)
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.72]) else {
            captureError = "JPEG encoding failed."
            isCapturing = false
            return
        }

        // Build a small thumbnail for the input bar preview
        let thumbW: CGFloat = 120
        let thumbH = thumbW * CGFloat(newH) / CGFloat(newW)
        let thumbImage = NSImage(size: NSSize(width: thumbW, height: thumbH))
        thumbImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: resized, size: .zero)
            .draw(in: NSRect(x: 0, y: 0, width: thumbW, height: thumbH))
        thumbImage.unlockFocus()

        pendingScreenshot = jpegData
        pendingThumbnail = thumbImage
        isCapturing = false
    }

    /// Clear the pending screenshot after it's been sent or dismissed.
    func clear() {
        pendingScreenshot = nil
        pendingThumbnail = nil
        captureError = nil
    }

    /// Base64-encoded JPEG string for API transmission.
    var base64JPEG: String? {
        pendingScreenshot?.base64EncodedString()
    }

    /// Human-readable size of the pending screenshot.
    var fileSizeLabel: String {
        guard let data = pendingScreenshot else { return "" }
        let kb = Double(data.count) / 1024.0
        if kb > 1024 {
            return String(format: "%.1f MB", kb / 1024.0)
        }
        return String(format: "%.0f KB", kb)
    }
}
