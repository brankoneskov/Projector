//
//  StudioInfoStore.swift
//  Projector
//
//  Stores studio identity information used in quote PDF headers.
//  Persisted as studio.json in the data folder (shared via Dropbox).
//  Logo is stored as logo_custom.png in the data folder.
//

import Foundation
import AppKit
import Combine

struct StudioInfo: Codable {
    var name:              String = ""
    var address:           String = ""
    var email:             String = ""
    var phone:             String = ""
    var website:           String = ""
    var vat:               String = ""
    var quoteValidityDays: Int    = 30
}

final class StudioInfoStore: ObservableObject {
    static let shared = StudioInfoStore()

    @Published var info = StudioInfo()

    private var fileURL: URL { DataPaths.file("studio.json") }

    /// URL of the custom logo in the data folder, if the file exists.
    static var customLogoURL: URL? {
        let url = DataPaths.file("logo_custom.png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private init() { load() }

    // MARK: - Load / Save

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(StudioInfo.self, from: data) else { return }
        info = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(info) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func reload() { load() }

    // MARK: - Logo management

    /// Maximum logo dimensions in pixels. Larger images are resized proportionally.
    static let maxLogoWidth:  CGFloat = 600
    static let maxLogoHeight: CGFloat = 200

    enum LogoValidationResult {
        case accepted(size: CGSize)
        case resized(originalSize: CGSize, newSize: CGSize)
        case portraitWarning(size: CGSize)   // accepted but warn
        case invalidFormat
        case tooLarge                        // can't read at all
    }

    /// Copy a user-chosen PNG/JPEG into the data folder as logo_custom.png.
    /// Validates dimensions and resizes if needed.
    /// Returns a validation result describing what happened.
    @discardableResult
    func setLogo(from sourceURL: URL) -> LogoValidationResult {
        guard let src = NSImage(contentsOf: sourceURL) else { return .invalidFormat }

        let originalSize = src.size   // in points — NSImage reports at 72dpi
        // Convert to pixels (assume 72dpi for NSImage — multiply by backing scale for accuracy,
        // but for validation purposes point size is sufficient)
        let w = originalSize.width
        let h = originalSize.height

        guard w > 0, h > 0 else { return .invalidFormat }

        // Determine if resize is needed
        let needsResize = w > Self.maxLogoWidth || h > Self.maxLogoHeight
        let isPortrait = h > w

        let finalImage: NSImage
        let finalSize: CGSize

        if needsResize {
            let scale = min(Self.maxLogoWidth / w, Self.maxLogoHeight / h)
            finalSize = CGSize(width: floor(w * scale), height: floor(h * scale))
            finalImage = resized(src, to: finalSize)
        } else {
            finalSize = originalSize
            finalImage = src
        }

        // Save as PNG
        guard let tiff = finalImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return .invalidFormat
        }

        let dst = DataPaths.file("logo_custom.png")
        do {
            if FileManager.default.fileExists(atPath: dst.path) {
                try FileManager.default.removeItem(at: dst)
            }
            try pngData.write(to: dst, options: .atomic)
            objectWillChange.send()
        } catch {
            print("⚠️ Failed to save logo: \(error)")
            return .invalidFormat
        }

        if needsResize {
            return .resized(originalSize: originalSize, newSize: finalSize)
        } else if isPortrait {
            return .portraitWarning(size: finalSize)
        } else {
            return .accepted(size: finalSize)
        }
    }

    private func resized(_ image: NSImage, to newSize: CGSize) -> NSImage {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }

    /// Remove the custom logo from the data folder.
    func removeLogo() {
        let dst = DataPaths.file("logo_custom.png")
        try? FileManager.default.removeItem(at: dst)
        objectWillChange.send()
    }

    var hasCustomLogo: Bool {
        FileManager.default.fileExists(atPath: DataPaths.file("logo_custom.png").path)
    }

    var customLogoImage: NSImage? {
        guard let url = StudioInfoStore.customLogoURL else { return nil }
        return NSImage(contentsOf: url)
    }
}
