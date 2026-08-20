import AppKit
import XCTest

struct StatusItemImageRaster: Equatable {
    let width: Int
    let height: Int
    let alpha: [UInt8]

    var visiblePixelCount: Int {
        alpha.count(where: { $0 > 0 })
    }

    func differingPixelCount(from other: StatusItemImageRaster) -> Int {
        guard width == other.width, height == other.height else {
            return max(alpha.count, other.alpha.count)
        }
        return zip(alpha, other.alpha).count(where: !=)
    }
}

@MainActor
func rasterizeStatusItemImage(
    _ image: NSImage,
    file: StaticString = #filePath,
    line: UInt = #line
) -> StatusItemImageRaster {
    let width = Int(image.size.width.rounded(.up))
    let height = Int(image.size.height.rounded(.up))
    guard width > 0, height > 0,
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
        let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else {
        XCTFail("Could not create image raster", file: file, line: line)
        return StatusItemImageRaster(width: width, height: height, alpha: [])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    image.draw(
        in: NSRect(x: 0, y: 0, width: width, height: height),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    let alpha = (0 ..< height).flatMap { y in
        (0 ..< width).map { x in
            UInt8((bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) * 255)
        }
    }
    return StatusItemImageRaster(width: width, height: height, alpha: alpha)
}
