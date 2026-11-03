import AppKit

/// Deterministic procedural textures without game assets or external downloads
@MainActor
final class SurfaceView: NSView {
    let material: Material
    var opacity: CGFloat = 0.78 {
        didSet { needsDisplay = true }
    }
    
    private var texture: NSImage?

    init(_ material: Material) {
        self.material = material
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    // MARK: - Texture cache

    private func updateTextureIfNeeded() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        if let texture,
            texture.size.width >= bounds.width,
            texture.size.height >= bounds.height {
            return
        }

        // Grow the cache in small increments during resizing. This is one canvas,
        // not repeating tiles. Existing pixels stay anchored to the top-left corner.
        // A 128-point increment avoids regenerating the bitmap for each drag event.
        let cacheIncrement: CGFloat = 128
        let width = Int(ceil(max(bounds.width, texture?.size.width ?? 0) / cacheIncrement) * cacheIncrement)
        let height = Int(ceil(max(bounds.height, texture?.size.height ?? 0) / cacheIncrement) * cacheIncrement)
        texture = makeTexture(width: width, height: height)
    }

    private func makeTexture(width: Int, height: Int) -> NSImage? {
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: width * 4,
                bitsPerPixel: 32
            ),
            let data = bitmap.bitmapData
        else { return nil }
        fillTexture(data, width: width, height: height)

        // Keep a fixed profile across redraws. Generic RGB preserves the lighter
        // palette without relying on the current drawing context's device RGB.
        bitmap.setProperty(.colorSyncProfileData, withValue: NSColorSpace.genericRGB.iccProfileData)
        let result = NSImage(size: NSSize(width: width, height: height))
        result.addRepresentation(bitmap)

        // The texture is already cached by SurfaceView. Draw its bitmap directly
        // instead of letting NSImage create another cache for each drawing size.
        result.cacheMode = .never
        return result
    }

    // MARK: - Procedural grain

    private func fillTexture(_ data: UnsafeMutablePointer<UInt8>, width: Int, height: Int) {
        let base = material.baseColor
        
        // Cache the horizontal waves so extending a large window does not run
        // trigonometric functions separately for every pixel.
        // Frequencies and amplitudes are tuned to create broad, warped veins
        // with finer cross-grain.
        let sinX = (0..<width).map { sin(Double($0) * 0.009) }
        let cosX = (0..<width).map { cos(Double($0) * 0.009) }

        let fineSinX = (0..<width).map { sin(Double($0) * 0.019) }
        let fineCosX = (0..<width).map { cos(Double($0) * 0.019) }
        for y in 0..<height {
            let warp = sin(Double(y) * 0.022) * 3
            let sinWarp = sin(warp)
            let cosWarp = cos(warp)
            let sinY = sin(Double(y) * 0.057)
            let cosY = cos(Double(y) * 0.057)
            for x in 0..<width {
                let noise = grain(x: x, y: y)
                let cloud =
                    (sinX[x] * cosWarp + cosX[x] * sinWarp) * 7
                    + (fineCosX[x] * cosY - fineSinX[x] * sinY) * 5
                let amount = material == .parchment ? noise * 0.4 + cloud : noise * 0.3 + cloud * 0.5
                
                // Interleaved 8-bit RGBA.
                // Clamp channels before converting to UInt8.
                let offset = (y * width + x) * 4
                data[offset] = UInt8(max(0, min(255, base.0 + amount)))
                data[offset + 1] = UInt8(max(0, min(255, base.1 + amount)))
                data[offset + 2] = UInt8(max(0, min(255, base.2 + amount)))
                data[offset + 3] = 255
            }
        }
    }

    private func grain(x: Int, y: Int) -> Double {
        // Hash coordinates so growing the cache never
        // changes existing pixels. Wrapping products and shifts mix adjacent pixels.
        // Seed is a random number which looks just nice on canvas.
        let seed: UInt64 = material == .parchment ? 7321 : 4903
        
        // SplitMix64 constants (from SplitMix64 algo)
        let goldenRatioIncrement: UInt64 = 0x9e3779b97f4a7c15
        let firstMixMultiplier: UInt64 = 0xbf58476d1ce4e5b9
        let secondMixMultiplier: UInt64 = 0x94d049bb133111eb

        var hash = (UInt64(x) &* goldenRatioIncrement) ^ (UInt64(y) &* firstMixMultiplier) ^ seed

        // XOR with right-shifted copies mixes higher bits into lower ones. Wrapping
        // multiplication spreads those changes across the 64-bit value. Together
        // these steps make nearby coordinates produce very different noise values.
        hash = (hash ^ (hash >> 30)) &* firstMixMultiplier
        hash = (hash ^ (hash >> 27)) &* secondMixMultiplier
        hash ^= hash >> 31
        // Symmetric noise in -14...14 keeps the average material color unchanged.
        return Double(hash % 29) - 14
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        updateTextureIfNeeded()
        context.saveGState()
        if material == .overlay {
            // Clear the old background so translucent redraws do not accumulate.
            context.clear(dirtyRect)
            NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3).addClip()
        }
        if let texture {
            // Crop at the original scale rather than stretching or tiling.
            let source = NSRect(
                x: 0, y: texture.size.height - bounds.height,
                width: bounds.width, height: bounds.height)
            // NSImage applies its fraction as drawing alpha; pass opacity here
            // rather than setting CGContext alpha before the image draw.
            let fraction: CGFloat = material == .overlay ? min(1, max(0, opacity)) : 1
            texture.draw(
                in: bounds, from: source, operation: .sourceOver, fraction: fraction,
                respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
        }
        context.restoreGState()
        drawBorder()
    }

    private func drawBorder() {
        switch material {
        case .parchment: drawParchmentBorder()
        case .frame: drawFrameBorder()
        case .stone: drawStoneBorder()
        case .overlay: drawOverlayBorder()
        }
    }

    // Border widths, corner radii and highlights are in points. Nested strokes
    // form the bevel, half-point insets keep thin outlines inside the view bounds.
    private func drawParchmentBorder() {
        // Fade the outer 18 points to suggest the curved edge of a page.
        let edge = NSGradient(colors: [.black.withAlphaComponent(0.34), .clear])!
        edge.draw(in: NSRect(x: 0, y: 0, width: 18, height: bounds.height), angle: 0)
        edge.draw(in: NSRect(x: bounds.width - 18, y: 0, width: 18, height: bounds.height), angle: 180)
        NSColor(hex: 0x5d472a).setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1)).stroke()
        NSColor(hex: 0xedd19a).withAlphaComponent(0.45).setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 3, dy: 3)).stroke()
    }

    private func drawFrameBorder() {
        NSColor(hex: 0x0a0b0a).setStroke()
        let outer = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
        outer.lineWidth = 3
        outer.stroke()
        NSColor(hex: 0x99917b).setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 3, yRadius: 3).stroke()
        Theme.mutedGold.withAlphaComponent(0.5).setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 6, dy: 6)).stroke()
        // Five-point rivets sit 11 points from each corner.
        for point in [
            NSPoint(x: 11, y: 11), NSPoint(x: bounds.width - 11, y: 11),
            NSPoint(x: 11, y: bounds.height - 11), NSPoint(x: bounds.width - 11, y: bounds.height - 11)
        ] {
            NSGradient(colors: [NSColor(hex: 0xbdb190), NSColor(hex: 0x302e25)])!
                .draw(
                    in: NSBezierPath(ovalIn: NSRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)),
                    angle: 270)
        }
    }

    private func drawStoneBorder() {
        NSColor(hex: 0x050605).setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1)).stroke()
        Theme.mutedGold.withAlphaComponent(0.55).setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 2.5, dy: 2.5)).stroke()
    }

    private func drawOverlayBorder() {
        Theme.mutedGold.withAlphaComponent(opacity * 0.7).setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3).stroke()
    }
}

// MARK: - Materials

extension SurfaceView {
    enum Material {
        case frame, stone, parchment, overlay

        // Base RGB channels before procedural shading; parchment uses a warmer palette.
        var baseColor: (Double, Double, Double) {
            switch self {
            case .parchment: (213, 180, 119)
            case .frame: (43, 43, 38)
            case .stone: (18, 21, 20)
            case .overlay: (20, 23, 21)
            }
        }
    }
}
