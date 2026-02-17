import ImageIO
import SwiftUI
import UIKit

enum StampLoadMode {
    case immediate
    case deferred
}

struct FavoriteStateIconView: View {
    let isFavorite: Bool
    var size: CGFloat = 19

    var body: some View {
        ZStack {
            Image("FavoriteOkiniiriIcon")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(.white)
                .frame(width: size * 1.06, height: size * 1.06)

            Image("FavoriteOkiniiriIcon")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .saturation(isFavorite ? 1 : 0)
                .opacity(isFavorite ? 1 : 0.88)
        }
        .accessibilityLabel(L10n.PlaceState.favoriteA11y)
    }
}

struct PlaceStampBackgroundView: View {
    let stamp: PlaceStampPresentation?
    var size: CGFloat
    var isCompact: Bool = false
    var loadMode: StampLoadMode = .deferred
    var rotationDegrees: Double = 0

    var body: some View {
        if let stamp {
            stampImage(resourceName: stamp.resourceName)
                .frame(width: size, height: size)
                .rotationEffect(.degrees(rotationDegrees))
                .saturation(stamp.isColorized ? 1 : 0)
                .opacity(stamp.isColorized ? (isCompact ? 0.29 : 0.24) : (isCompact ? 0.20 : 0.16))
                .blendMode(.multiply)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func stampImage(resourceName: String) -> some View {
        switch loadMode {
        case .immediate:
            ImmediateStampImageView(resourceName: resourceName, maxPixelSize: Int(size * 2.4))
        case .deferred:
            DeferredStampImageView(resourceName: resourceName, maxPixelSize: Int(size * 2.4))
        }
    }
}

struct StampIconView: View {
    let stamp: PlaceStampPresentation?
    let isColorized: Bool
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let stamp {
                ImmediateStampImageView(resourceName: stamp.resourceName, maxPixelSize: Int(size * 2))
                    .saturation(isColorized ? 1 : 0)
                    .opacity(isColorized ? 1 : 0.72)
            } else {
                Image(systemName: isColorized ? "checkmark.seal.fill" : "seal")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color(red: 0.36, green: 0.47, blue: 0.52))
                    .opacity(0.86)
            }
        }
        .frame(width: size, height: size)
    }
}

struct ImmediateStampImageView: View {
    let resourceName: String
    let maxPixelSize: Int

    @State private var image: UIImage?
    @State private var loadedKey: String = ""

    init(resourceName: String, maxPixelSize: Int) {
        self.resourceName = resourceName
        self.maxPixelSize = maxPixelSize
        let key = "\(resourceName)-\(maxPixelSize)"
        _image = State(initialValue: StampImageLoader.loadImage(resourceName: resourceName, maxPixelSize: maxPixelSize))
        _loadedKey = State(initialValue: key)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
            } else {
                Color.clear
            }
        }
        .onAppear {
            reloadIfNeeded()
        }
        .onChange(of: resourceName) { _, _ in
            reloadIfNeeded()
        }
        .onChange(of: maxPixelSize) { _, _ in
            reloadIfNeeded()
        }
        .onDisappear {
            image = nil
            loadedKey = ""
        }
    }

    private func reloadIfNeeded() {
        let key = "\(resourceName)-\(maxPixelSize)"
        guard key != loadedKey || image == nil else {
            return
        }
        image = StampImageLoader.loadImage(resourceName: resourceName, maxPixelSize: maxPixelSize)
        loadedKey = key
    }
}

struct DeferredStampImageView: View {
    let resourceName: String
    let maxPixelSize: Int

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
            } else {
                Color.clear
            }
        }
        .task(id: "\(resourceName)-\(maxPixelSize)") {
            image = await Task.detached(priority: .utility) {
                StampImageLoader.loadImage(resourceName: resourceName, maxPixelSize: maxPixelSize)
            }.value
        }
        .onDisappear {
            image = nil
        }
    }
}

struct StampWhiteBaseImageView: View {
    let resourceName: String
    let maxPixelSize: Int

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
            } else {
                Color.clear
            }
        }
        .task(id: "\(resourceName)-\(maxPixelSize)-white-base") {
            image = await Task.detached(priority: .utility) {
                StampImageLoader.loadWhiteBaseImage(resourceName: resourceName, maxPixelSize: maxPixelSize)
            }.value
        }
        .onDisappear {
            image = nil
        }
    }
}

private enum StampImageLoader {
    nonisolated static func loadImage(resourceName: String, maxPixelSize: Int) -> UIImage? {
        guard let baseURL = Bundle.main.resourceURL else {
            return nil
        }
        let primaryURL = baseURL.appendingPathComponent(resourceName, isDirectory: false)
        let fallbackURL = baseURL.appendingPathComponent("stamps", isDirectory: true)
            .appendingPathComponent(resourceName, isDirectory: false)
        let imageURL = FileManager.default.fileExists(atPath: primaryURL.path) ? primaryURL : fallbackURL

        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil) else {
            return UIImage(contentsOfFile: imageURL.path)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 64)
        ]

        if let downsampled = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return UIImage(cgImage: downsampled)
        }

        return UIImage(contentsOfFile: imageURL.path)
    }

    nonisolated static func loadWhiteBaseImage(resourceName: String, maxPixelSize: Int) -> UIImage? {
        guard let image = loadImage(resourceName: resourceName, maxPixelSize: maxPixelSize) else {
            return nil
        }
        return makeWhiteBase(from: image)
    }

    private nonisolated static func makeWhiteBase(from image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let raw = context.data else {
            return nil
        }
        let pixelCount = width * height
        let buffer = raw.bindMemory(to: UInt8.self, capacity: pixelCount * bytesPerPixel)
        let alphaThreshold = 8

        for index in 0 ..< pixelCount {
            let offset = index * bytesPerPixel
            let alpha = Int(buffer[offset + 3])
            if alpha > alphaThreshold {
                buffer[offset] = 255
                buffer[offset + 1] = 255
                buffer[offset + 2] = 255
                buffer[offset + 3] = 255
            } else {
                buffer[offset] = 0
                buffer[offset + 1] = 0
                buffer[offset + 2] = 0
                buffer[offset + 3] = 0
            }
        }

        guard let whiteBaseCGImage = context.makeImage() else {
            return nil
        }
        return UIImage(cgImage: whiteBaseCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
}
