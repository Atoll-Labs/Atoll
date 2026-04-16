/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import AVFoundation
import Combine
import SkyLightWindow
import SwiftUI

// MARK: - Click Receiver Window

private class ClickReceiverWindow: NSWindow {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onClick?()
    }
}

private final class LoopingVideoView: NSView {
    private var playerLayer: AVPlayerLayer?
    private var queuePlayer: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }

    func play(url: URL) {
        stop()

        let playerItem = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        layer.backgroundColor = NSColor.clear.cgColor

        self.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        self.layer?.addSublayer(layer)

        playerLayer = layer
        queuePlayer = player
        playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)
        player.play()
    }

    func stop() {
        queuePlayer?.pause()
        playerLooper = nil
        queuePlayer = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
    }
}

// MARK: - Window Manager

@MainActor
final class FullScreenArtworkWindowManager {
    static let shared = FullScreenArtworkWindowManager()

    private(set) var isShowing = false
    var onDismiss: (() -> Void)?

    private let wallpaperPlistURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }()
    private let backupPlistURL: URL = {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll_wallpaper_backup.plist")
    }()
    private let aerialManifestURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json")
    }()
    private let aerialVideosDirectoryURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/videos", isDirectory: true)
    }()
    private let aerialThumbnailsDirectoryURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/thumbnails", isDirectory: true)
    }()
    private let customLiveWallpaperAssetID = "6D6834A4-2F0F-479A-B053-7D4DC5CB8EB7"
    private let liveWallpaperManifestBackupURL: URL = {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll_aerial_manifest_backup.json")
    }()
    private let liveWallpaperVideoBackupURL: URL = {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll_aerial_video_backup.mov")
    }()
    private let liveWallpaperThumbnailBackupURL: URL = {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll_aerial_thumbnail_backup.png")
    }()
    private var artworkFileURL: URL?
    private var cachedArtworkPNG: URL?
    private var cachedArtworkIdentifier: String?
    private var activeSongTitle: String?
    private var activeArtist: String?
    private var trackChangeCancellable: AnyCancellable?
    private var artworkCacheCancellable: AnyCancellable?
    private var videoArtworkCancellable: AnyCancellable?
    private var clickWindow: ClickReceiverWindow?
    private var clickWindowDelegated = false
    private var videoWindow: NSWindow?
    private var videoView: LoopingVideoView?
    private var liveWallpaperTask: Task<Void, Never>?
    private var isLiveWallpaperAllowed = false
    private var activeLiveWallpaperFingerprint: String?

    private init() {
        observeArtworkChanges()
        observeVideoArtworkChanges()
    }

    func show(artwork: NSImage, videoURL: URL? = nil, allowLiveWallpaper: Bool = false) {
        guard !isShowing else { return }
        guard let screen = NSScreen.main else { return }

        let fileURL: URL
        let artworkID = "\(MusicManager.shared.songTitle)|\(MusicManager.shared.artistName)"

        if let cached = cachedArtworkPNG,
           cachedArtworkIdentifier == artworkID,
           FileManager.default.fileExists(atPath: cached.path) {
            fileURL = cached
        } else {
            guard let encoded = encodeToPNG(artwork) else { return }
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("atoll_artwork_wallpaper.png")
            do {
                try encoded.write(to: tempURL, options: .atomic)
            } catch {
                return
            }
            fileURL = tempURL
            cachedArtworkPNG = tempURL
            cachedArtworkIdentifier = artworkID
        }

        artworkFileURL = fileURL
        isLiveWallpaperAllowed = allowLiveWallpaper
        activeLiveWallpaperFingerprint = nil
        backupWallpaperConfig()

        guard applyArtworkToPlist(imageURL: fileURL) else {
            print("[FullScreenArtworkWindowManager] Failed to patch plist")
            return
        }

        restartWallpaperAgent()
        hideVideoWindow()
        showClickReceiver(on: screen)

        isShowing = true
        activeSongTitle = MusicManager.shared.songTitle
        activeArtist = MusicManager.shared.artistName

        observeTrackChanges()
        scheduleLiveWallpaperPreparation(for: videoURL, artwork: artwork, identifier: artworkID)

        print("[FullScreenArtworkWindowManager] Artwork applied as wallpaper")
    }

    func hide() {
        guard isShowing else { return }
        isShowing = false
        isLiveWallpaperAllowed = false
        activeLiveWallpaperFingerprint = nil
        trackChangeCancellable?.cancel()
        trackChangeCancellable = nil
        liveWallpaperTask?.cancel()
        liveWallpaperTask = nil

        hideVideoWindow()
        hideClickReceiver()
        restoreWallpaper()

        activeSongTitle = nil
        activeArtist = nil

        let callback = onDismiss
        onDismiss = nil
        callback?()

        print("[FullScreenArtworkWindowManager] Original wallpaper restored")
    }

    // MARK: - Artwork Pre-Cache

    private func observeArtworkChanges() {
        artworkCacheCancellable = MusicManager.shared.$albumArt
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] newArt in
                guard let self else { return }
                let artID = "\(MusicManager.shared.songTitle)|\(MusicManager.shared.artistName)"
                guard artID != self.cachedArtworkIdentifier else { return }
                Task.detached(priority: .utility) {
                    guard let pngData = self.encodeToPNG(newArt) else { return }
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("atoll_artwork_wallpaper.png")
                    try? pngData.write(to: url, options: .atomic)
                    await MainActor.run {
                        self.cachedArtworkPNG = url
                        self.cachedArtworkIdentifier = artID
                    }
                }
            }
    }

    private func observeVideoArtworkChanges() {
        videoArtworkCancellable = MusicManager.shared.$videoArtworkURL
            .receive(on: DispatchQueue.main)
            .sink { [weak self] videoURL in
                guard let self, self.isShowing, self.isLiveWallpaperAllowed else { return }
                let artworkID = "\(MusicManager.shared.songTitle)|\(MusicManager.shared.artistName)"
                self.scheduleLiveWallpaperPreparation(
                    for: videoURL,
                    artwork: MusicManager.shared.albumArt,
                    identifier: artworkID
                )
            }
    }

    private nonisolated func encodeToPNG(_ image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func scheduleLiveWallpaperPreparation(for videoURL: URL?, artwork: NSImage, identifier: String) {
        liveWallpaperTask?.cancel()
        liveWallpaperTask = nil

        guard isLiveWallpaperAllowed else { return }
        guard let artworkFileURL else { return }

        let nextFingerprint = videoURL?.absoluteString
        if activeLiveWallpaperFingerprint != nil, activeLiveWallpaperFingerprint != nextFingerprint {
            activeLiveWallpaperFingerprint = nil
            if applyArtworkToPlist(imageURL: artworkFileURL) {
                restartWallpaperAgent()
            }
        }

        guard let videoURL else { return }
        if activeLiveWallpaperFingerprint == nextFingerprint { return }
        if let screen = NSScreen.main {
            showVideoWindow(on: screen, videoURL: videoURL)
        }

        let assetID = customLiveWallpaperAssetID
        let manifestURL = aerialManifestURL
        let videosDirectoryURL = aerialVideosDirectoryURL
        let thumbnailsDirectoryURL = aerialThumbnailsDirectoryURL
        let manifestBackupURL = liveWallpaperManifestBackupURL
        let videoBackupURL = liveWallpaperVideoBackupURL
        let thumbnailBackupURL = liveWallpaperThumbnailBackupURL
        let thumbnailData = encodeToPNG(artwork)
        let title = activeSongTitle ?? MusicManager.shared.songTitle
        let artist = activeArtist ?? MusicManager.shared.artistName
        let displayName = [title, artist]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " - ")

        liveWallpaperTask = Task(priority: .utility) { [weak self] in
            let prepared = await Self.prepareCustomLiveWallpaperAsset(
                from: videoURL,
                assetID: assetID,
                displayName: displayName.isEmpty ? "Atoll Canvas" : displayName,
                manifestURL: manifestURL,
                videosDirectoryURL: videosDirectoryURL,
                thumbnailsDirectoryURL: thumbnailsDirectoryURL,
                thumbnailData: thumbnailData,
                manifestBackupURL: manifestBackupURL,
                videoBackupURL: videoBackupURL,
                thumbnailBackupURL: thumbnailBackupURL
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, self.isShowing, self.isLiveWallpaperAllowed else { return }
                let currentIdentifier = "\(MusicManager.shared.songTitle)|\(MusicManager.shared.artistName)"
                guard currentIdentifier == identifier else { return }
                guard prepared else { return }
                guard self.applyAerialToPlist(assetID: assetID) else { return }

                self.activeLiveWallpaperFingerprint = nextFingerprint
                self.hideVideoWindow()
                self.restartWallpaperAgent()
                print("[FullScreenArtworkWindowManager] Live wallpaper applied")
            }
        }
    }

    private nonisolated static func prepareCustomLiveWallpaperAsset(
        from sourceURL: URL,
        assetID: String,
        displayName: String,
        manifestURL: URL,
        videosDirectoryURL: URL,
        thumbnailsDirectoryURL: URL,
        thumbnailData: Data?,
        manifestBackupURL: URL,
        videoBackupURL: URL,
        thumbnailBackupURL: URL
    ) async -> Bool {
        let fm = FileManager.default
        let videoDestinationURL = videosDirectoryURL.appendingPathComponent("\(assetID).mov")
        let thumbnailDestinationURL = thumbnailsDirectoryURL.appendingPathComponent("\(assetID).png")

        do {
            try fm.createDirectory(at: videosDirectoryURL, withIntermediateDirectories: true)
            try fm.createDirectory(at: thumbnailsDirectoryURL, withIntermediateDirectories: true)
        } catch {
            return false
        }

        backupItemIfNeeded(at: manifestURL, backupURL: manifestBackupURL)
        backupItemIfNeeded(at: videoDestinationURL, backupURL: videoBackupURL)
        backupItemIfNeeded(at: thumbnailDestinationURL, backupURL: thumbnailBackupURL)

        guard await materializeVideo(from: sourceURL, to: videoDestinationURL) else {
            return false
        }

        if let thumbnailData {
            try? thumbnailData.write(to: thumbnailDestinationURL, options: .atomic)
        }

        return updateAerialManifest(
            manifestURL: manifestURL,
            assetID: assetID,
            videoURL: videoDestinationURL,
            thumbnailURL: fm.fileExists(atPath: thumbnailDestinationURL.path) ? thumbnailDestinationURL : nil,
            displayName: displayName
        )
    }

    private nonisolated static func materializeVideo(from sourceURL: URL, to destinationURL: URL) async -> Bool {
        let fm = FileManager.default
        try? fm.removeItem(at: destinationURL)

        if !sourceURL.isFileURL {
            guard let downloadedURL = await downloadRemoteVideo(from: sourceURL) else {
                return false
            }
            defer { try? fm.removeItem(at: downloadedURL) }
            return await materializeVideo(from: downloadedURL, to: destinationURL)
        }

        if sourceURL.isFileURL, sourceURL.pathExtension.lowercased() == "mov" {
            do {
                try fm.copyItem(at: sourceURL, to: destinationURL)
                return validateVideo(at: destinationURL)
            } catch {
                return false
            }
        }

        let asset = AVURLAsset(url: sourceURL)
        let presets = [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality]
        for preset in presets {
            try? fm.removeItem(at: destinationURL)
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
                continue
            }

            exportSession.outputURL = destinationURL
            exportSession.outputFileType = .mov
            exportSession.shouldOptimizeForNetworkUse = true

            let exported = await export(exportSession)
            if exported, validateVideo(at: destinationURL) {
                return true
            }
        }

        return false
    }

    private nonisolated static func downloadRemoteVideo(from sourceURL: URL) async -> URL? {
        do {
            let (temporaryURL, response) = try await URLSession.shared.download(from: sourceURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                return nil
            }

            let destinationURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension)
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
            return destinationURL
        } catch {
            return nil
        }
    }

    private nonisolated static func export(_ exportSession: AVAssetExportSession) async -> Bool {
        await withCheckedContinuation { continuation in
            exportSession.exportAsynchronously {
                continuation.resume(returning: exportSession.status == .completed)
            }
        }
    }

    private nonisolated static func validateVideo(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let asset = AVURLAsset(url: url)
        return !asset.tracks(withMediaType: .video).isEmpty
    }

    private nonisolated static func updateAerialManifest(
        manifestURL: URL,
        assetID: String,
        videoURL: URL,
        thumbnailURL: URL?,
        displayName: String
    ) -> Bool {
        guard let manifestData = try? Data(contentsOf: manifestURL),
              var root = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              var assets = root["assets"] as? [[String: Any]]
        else {
            return false
        }

        guard let existingIndex = assets.firstIndex(where: { ($0["id"] as? String) == assetID }) else {
            return false
        }

        var customAsset = assets[existingIndex]
        customAsset["accessibilityLabel"] = displayName
        customAsset["previewImage"] = thumbnailURL?.absoluteString ?? ""
        customAsset["url-4K-SDR-240FPS"] = videoURL.absoluteString
        customAsset["pointsOfInterest"] = [:]
        assets[existingIndex] = customAsset

        root["assets"] = assets

        guard let encoded = try? JSONSerialization.data(withJSONObject: root, options: []) else {
            return false
        }

        do {
            try encoded.write(to: manifestURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private nonisolated static func backupItemIfNeeded(at sourceURL: URL, backupURL: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else { return }
        guard !fm.fileExists(atPath: backupURL.path) else { return }
        try? fm.copyItem(at: sourceURL, to: backupURL)
    }

    private func restoreLiveWallpaperResources() {
        let fm = FileManager.default
        let assetID = customLiveWallpaperAssetID
        let videoDestinationURL = aerialVideosDirectoryURL.appendingPathComponent("\(assetID).mov")
        let thumbnailDestinationURL = aerialThumbnailsDirectoryURL.appendingPathComponent("\(assetID).png")

        if fm.fileExists(atPath: liveWallpaperManifestBackupURL.path) {
            try? fm.removeItem(at: aerialManifestURL)
            try? fm.copyItem(at: liveWallpaperManifestBackupURL, to: aerialManifestURL)
            try? fm.removeItem(at: liveWallpaperManifestBackupURL)
        }

        if fm.fileExists(atPath: liveWallpaperVideoBackupURL.path) {
            try? fm.removeItem(at: videoDestinationURL)
            try? fm.copyItem(at: liveWallpaperVideoBackupURL, to: videoDestinationURL)
            try? fm.removeItem(at: liveWallpaperVideoBackupURL)
        }

        if fm.fileExists(atPath: liveWallpaperThumbnailBackupURL.path) {
            try? fm.removeItem(at: thumbnailDestinationURL)
            try? fm.copyItem(at: liveWallpaperThumbnailBackupURL, to: thumbnailDestinationURL)
            try? fm.removeItem(at: liveWallpaperThumbnailBackupURL)
        }
    }

    // MARK: - Click Receiver

    private func showClickReceiver(on screen: NSScreen) {
        let screenFrame = screen.frame

        let window: ClickReceiverWindow
        if let existing = clickWindow {
            window = existing
        } else {
            let newWindow = ClickReceiverWindow(
                contentRect: screenFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newWindow.isReleasedWhenClosed = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            newWindow.isMovable = false
            newWindow.hasShadow = false

            ScreenCaptureVisibilityManager.shared.register(newWindow, scope: .entireInterface)
            clickWindow = newWindow
            window = newWindow
            clickWindowDelegated = false
        }

        window.setFrame(screenFrame, display: true)
        window.onClick = { [weak self] in
            self?.hide()
        }

        if !clickWindowDelegated {
            SkyLightOperator.shared.delegateWindow(window)
            clickWindowDelegated = true
        }

        window.orderFrontRegardless()

        for other in NSApp.windows where other !== window && other.level.rawValue >= Int(CGShieldingWindowLevel()) && other.isVisible {
            window.order(.below, relativeTo: other.windowNumber)
        }
    }

    private func hideClickReceiver() {
        clickWindow?.orderOut(nil)
        clickWindow?.onClick = nil
    }

    private func showVideoWindow(on screen: NSScreen, videoURL: URL) {
        let screenFrame = screen.frame

        let window: NSWindow
        let view: LoopingVideoView

        if let existingWindow = videoWindow, let existingView = videoView {
            window = existingWindow
            view = existingView
        } else {
            let newWindow = NSWindow(
                contentRect: screenFrame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            newWindow.isReleasedWhenClosed = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.ignoresMouseEvents = true
            newWindow.hasShadow = false
            newWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

            let newView = LoopingVideoView(frame: screenFrame)
            newWindow.contentView = newView

            videoWindow = newWindow
            videoView = newView
            window = newWindow
            view = newView
        }

        window.setFrame(screenFrame, display: true)
        view.frame = NSRect(origin: .zero, size: screenFrame.size)
        view.play(url: videoURL)
        window.orderFrontRegardless()
    }

    private func hideVideoWindow() {
        videoView?.stop()
        videoWindow?.orderOut(nil)
    }

    // MARK: - Backup / Restore

    private var hasValidBackup: Bool {
        FileManager.default.fileExists(atPath: backupPlistURL.path)
    }

    private func backupWallpaperConfig() {
        guard !hasValidBackup else { return }
        try? FileManager.default.copyItem(at: wallpaperPlistURL, to: backupPlistURL)
    }

    private func applyArtworkToPlist(imageURL: URL) -> Bool {
        guard let plistData = try? Data(contentsOf: wallpaperPlistURL),
              var plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else { return false }

        let desktopBlock = makeImageWallpaperBlock(imageURL: imageURL)
        let idleBlock = makeImageWallpaperBlock(imageURL: imageURL)

        patchWallpaperEntries(&plist, desktopBlock: desktopBlock, idleBlock: idleBlock)

        guard let newData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        else { return false }

        return (try? newData.write(to: wallpaperPlistURL, options: .atomic)) != nil
    }

    private func applyAerialToPlist(assetID: String) -> Bool {
        guard let plistData = try? Data(contentsOf: wallpaperPlistURL),
              var plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else { return false }

        let desktopTemplate = wallpaperBlock(
            named: "Desktop",
            in: plist["AllSpacesAndDisplays"] as? [String: Any],
            fallback: plist["SystemDefault"] as? [String: Any]
        )
        let idleTemplate = wallpaperBlock(
            named: "Idle",
            in: plist["AllSpacesAndDisplays"] as? [String: Any],
            fallback: plist["SystemDefault"] as? [String: Any]
        )

        let desktopBlock = makeAerialWallpaperBlock(assetID: assetID, existingBlock: desktopTemplate)
        let idleBlock = makeAerialWallpaperBlock(assetID: assetID, existingBlock: idleTemplate)

        patchWallpaperEntries(&plist, desktopBlock: desktopBlock, idleBlock: idleBlock)

        guard let newData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        else { return false }

        return (try? newData.write(to: wallpaperPlistURL, options: .atomic)) != nil
    }

    private func wallpaperBlock(named name: String, in primary: [String: Any]?, fallback: [String: Any]?) -> [String: Any]? {
        if let primaryBlock = primary?[name] as? [String: Any] {
            return primaryBlock
        }
        return fallback?[name] as? [String: Any]
    }

    private func makeImageWallpaperBlock(imageURL: URL) -> [String: Any] {
        let config: [String: Any] = [
            "type": "imageFile",
            "url": ["relative": imageURL.absoluteString]
        ]
        let configData = (try? PropertyListSerialization.data(fromPropertyList: config, format: .binary, options: 0)) ?? Data()

        let imageChoice: [String: Any] = [
            "Provider": "com.apple.wallpaper.choice.image",
            "Files": [] as [Any],
            "Configuration": configData
        ]

        let contentBlock: [String: Any] = [
            "Choices": [imageChoice],
            "Shuffle": "$null"
        ]

        return [
            "Content": contentBlock,
            "LastSet": Date(),
            "LastUse": Date()
        ]
    }

    private func makeAerialWallpaperBlock(assetID: String, existingBlock: [String: Any]?) -> [String: Any] {
        let config: [String: Any] = [
            "assetID": assetID
        ]
        let configData = (try? PropertyListSerialization.data(fromPropertyList: config, format: .binary, options: 0)) ?? Data()

        let aerialChoice: [String: Any] = [
            "Provider": "com.apple.wallpaper.choice.aerials",
            "Files": [] as [Any],
            "Configuration": configData
        ]

        var contentBlock: [String: Any] = [
            "Choices": [aerialChoice],
            "Shuffle": "$null"
        ]

        if let existingContent = existingBlock?["Content"] as? [String: Any],
           let encodedOptionValues = existingContent["EncodedOptionValues"] {
            contentBlock["EncodedOptionValues"] = encodedOptionValues
        }

        return [
            "Content": contentBlock,
            "LastSet": Date(),
            "LastUse": Date()
        ]
    }

    private func patchWallpaperEntries(_ plist: inout [String: Any], desktopBlock: [String: Any], idleBlock: [String: Any]) {
        var allSpaces = (plist["AllSpacesAndDisplays"] as? [String: Any]) ?? [:]
        allSpaces["Desktop"] = desktopBlock
        allSpaces["Idle"] = idleBlock
        allSpaces["Type"] = allSpaces["Type"] ?? "individual"
        plist["AllSpacesAndDisplays"] = allSpaces

        var systemDefault = (plist["SystemDefault"] as? [String: Any]) ?? [:]
        systemDefault["Desktop"] = desktopBlock
        systemDefault["Idle"] = idleBlock
        systemDefault["Type"] = systemDefault["Type"] ?? "individual"
        plist["SystemDefault"] = systemDefault

        if var displays = plist["Displays"] as? [String: Any] {
            for key in displays.keys {
                if var display = displays[key] as? [String: Any] {
                    display["Desktop"] = desktopBlock
                    display["Idle"] = idleBlock
                    displays[key] = display
                }
            }
            plist["Displays"] = displays
        }

        if var spaces = plist["Spaces"] as? [String: Any] {
            for spaceKey in spaces.keys {
                if var space = spaces[spaceKey] as? [String: Any] {
                    if var defaultEntry = space["Default"] as? [String: Any] {
                        defaultEntry["Desktop"] = desktopBlock
                        defaultEntry["Idle"] = idleBlock
                        space["Default"] = defaultEntry
                    }
                    if var spaceDisplays = space["Displays"] as? [String: Any] {
                        for displayKey in spaceDisplays.keys {
                            if var display = spaceDisplays[displayKey] as? [String: Any] {
                                display["Desktop"] = desktopBlock
                                display["Idle"] = idleBlock
                                spaceDisplays[displayKey] = display
                            }
                        }
                        space["Displays"] = spaceDisplays
                    }
                    spaces[spaceKey] = space
                }
            }
            plist["Spaces"] = spaces
        }
    }

    private func restartWallpaperAgent() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["WallpaperAgent"]
        try? task.run()
    }

    private func restoreWallpaper() {
        let fm = FileManager.default
        guard hasValidBackup else { return }

        do {
            try fm.removeItem(at: wallpaperPlistURL)
            try fm.copyItem(at: backupPlistURL, to: wallpaperPlistURL)
            try fm.removeItem(at: backupPlistURL)
        } catch {
            print("[FullScreenArtworkWindowManager] Failed to restore plist: \(error)")
        }

        restoreLiveWallpaperResources()
        restartWallpaperAgent()
    }

    // MARK: - Track Change Observer

    private func observeTrackChanges() {
        trackChangeCancellable?.cancel()
        trackChangeCancellable = MusicManager.shared.$songTitle
            .combineLatest(MusicManager.shared.$artistName)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] title, artist in
                guard let self, self.isShowing else { return }
                if title != self.activeSongTitle || artist != self.activeArtist {
                    self.hide()
                }
            }
    }
}
