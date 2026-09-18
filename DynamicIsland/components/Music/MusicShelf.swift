/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import AppKit
import Combine
import Defaults
import Foundation
import QuartzCore
import SwiftUI

enum MusicShelfProvider: String, Codable, Sendable {
    case appleMusic
    case spotify
    case other

    var name: String {
        switch self {
        case .appleMusic: return String(localized: "Apple Music")
        case .spotify: return String(localized: "Spotify")
        case .other: return String(localized: "Current player")
        }
    }

    var tint: Color {
        switch self {
        case .appleMusic: return .pink
        case .spotify: return .green
        case .other: return .accentColor
        }
    }
}

enum MusicShelfItemKind: String, Codable, Sendable {
    case album
    case artist
    case playlist
    case track
}

private enum MusicShelfCollection: String, CaseIterable, Identifiable {
    case albums
    case artists
    case playlists
    case history

    var id: String { rawValue }

    var name: String {
        switch self {
        case .albums: return String(localized: "Albums")
        case .artists: return String(localized: "Artists")
        case .playlists: return String(localized: "Playlists")
        case .history: return String(localized: "Recently played")
        }
    }

    var symbol: String {
        switch self {
        case .albums: return "square.stack"
        case .artists: return "person.2"
        case .playlists: return "music.note.list"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

struct MusicShelfItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let detail: String
    let provider: MusicShelfProvider
    let catalogID: String?
    let artworkURL: URL?
    let artworkPath: String?
    let playbackURI: String?
    let externalURL: URL?
    let isRecent: Bool
    var kind: MusicShelfItemKind = .album
    var lastPlayed: Date? = nil
}

struct MusicShelfTrack: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let artist: String
    let duration: TimeInterval
    let provider: MusicShelfProvider
    let playbackURI: String?
    let externalURL: URL?
}

private enum SpotifyLocalCommand {
    case play
    case pause
    case previous
    case next
    case seek(TimeInterval)
    case playTrack(uri: String, contextURI: String?)
}

private struct SpotifyPresentationGuard: Sendable {
    let spotifyPID: pid_t
    let frontmostPID: pid_t?
    let shouldRemainHidden: Bool
    let wasActive: Bool
}

private struct MusicShelfHistoryRecord: Codable {
    let id: String
    let album: String
    let artist: String
    let trackTitle: String
    let provider: MusicShelfProvider
    let artworkPath: String?
    let playbackURI: String?
    let externalURL: String?
    let lastPlayed: Date

    var item: MusicShelfItem {
        MusicShelfItem(
            id: id,
            title: album,
            subtitle: artist,
            detail: trackTitle,
            provider: provider,
            catalogID: nil,
            artworkURL: nil,
            artworkPath: artworkPath,
            playbackURI: playbackURI,
            externalURL: externalURL.flatMap { URL(string: $0) },
            isRecent: true,
            kind: .album,
            lastPlayed: lastPlayed
        )
    }
}

private enum MusicShelfArtworkValidator {
    private static let sampleSide = 20

    static func isProviderIcon(_ image: NSImage, provider: MusicShelfProvider) -> Bool {
        guard provider == .spotify,
              let icon = AppIconAsNSImage(for: SpotifyController.bundleIdentifier),
              let artworkPixels = normalizedPixels(for: image),
              let iconPixels = normalizedPixels(for: icon),
              artworkPixels.count == iconPixels.count
        else { return false }

        let accumulatedDifference = zip(artworkPixels, iconPixels).reduce(0.0) { result, pair in
            result + abs(Double(pair.0) - Double(pair.1))
        }
        let normalizedDifference = accumulatedDifference / (Double(artworkPixels.count) * 255)
        return normalizedDifference < 0.105
    }

    private static func normalizedPixels(for image: NSImage) -> [UInt8]? {
        guard image.size.width > 0, image.size.height > 0,
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: sampleSide,
                pixelsHigh: sampleSide,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: sampleSide * 4,
                bitsPerPixel: 32
              ),
              let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: sampleSide, height: sampleSide).fill()
        image.draw(
            in: NSRect(x: 0, y: 0, width: sampleSide, height: sampleSide),
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.bitmapData else { return nil }
        var pixels: [UInt8] = []
        pixels.reserveCapacity(sampleSide * sampleSide * 3)
        for y in 0..<sampleSide {
            let row = data.advanced(by: y * bitmap.bytesPerRow)
            for x in 0..<sampleSide {
                let pixel = row.advanced(by: x * 4)
                pixels.append(pixel[0])
                pixels.append(pixel[1])
                pixels.append(pixel[2])
            }
        }
        return pixels
    }
}

private final class MusicShelfWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class MusicShelfManager: ObservableObject {
    static let shared = MusicShelfManager()

    @Published private(set) var isPresented = false
    @Published private(set) var recentItems: [MusicShelfItem] = []
    @Published private(set) var libraryAlbums: [MusicShelfItem] = []
    @Published private(set) var libraryArtists: [MusicShelfItem] = []
    @Published private(set) var libraryPlaylists: [MusicShelfItem] = []
    @Published private(set) var relatedItems: [MusicShelfItem] = []
    @Published private(set) var searchResults: [MusicShelfItem] = []
    @Published private(set) var selectedItem: MusicShelfItem?
    @Published private(set) var tracks: [MusicShelfTrack] = []
    @Published private(set) var isSearching = false
    @Published private(set) var isLoadingTracks = false
    @Published private(set) var statusMessage: String?
    @Published var query = ""
    @Published var isContextPanelPresented = false
    @Published private(set) var searchFocusRequest = 0
    @Published private(set) var pinnedItemIDs: Set<String> = []
    @Published private var resolvedArtistArtwork: [String: URL] = [:]

    private let musicManager = MusicManager.shared
    private let historyDefaultsKey = "musicShelfHistory.v1"
    private let pinnedDefaultsKey = "musicShelfPinnedItems.v1"
    private var historyRecords: [MusicShelfHistoryRecord] = []
    private var window: MusicShelfWindow?
    private var hostingView: NSHostingView<MusicShelfRootView>?
    private var edgePollTimer: Timer?
    private var shownAt = Date.distantPast
    private var hiddenAt = Date.distantPast
    private var lastPointerInside = Date.distantPast
    private var searchTask: Task<Void, Never>?
    private var trackLoadTask: Task<Void, Never>?
    private var libraryLoadTask: Task<Void, Never>?
    private var artistArtworkTask: Task<Void, Never>?
    private var spotifyActivationObserver: NSObjectProtocol?
    private var spotifyPresentationRestoreTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        loadHistory()
        loadPinnedItems()
        observePlayback()
        observeSettings()
        updateEdgeMonitoring()
    }

    func toggle() {
        isPresented ? hide() : show(focusSearch: true)
    }

    func show(focusSearch: Bool = true) {
        guard Defaults[.enableMusicShelf], !LockScreenManager.shared.isLocked else { return }
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        guard let screen else { return }
        show(on: screen, focusSearch: focusSearch)
    }

    func hide() {
        guard isPresented, let window else { return }
        isPresented = false
        hiddenAt = Date()
        searchTask?.cancel()
        trackLoadTask?.cancel()
        isContextPanelPresented = false

        let hiddenFrame: NSRect
        switch Defaults[.musicShelfEdge] {
        case .left: hiddenFrame = window.frame.offsetBy(dx: -28, dy: 0)
        case .right: hiddenFrame = window.frame.offsetBy(dx: 28, dy: 0)
        case .bottom: hiddenFrame = window.frame.offsetBy(dx: 0, dy: -28)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
            window.animator().setFrame(hiddenFrame, display: true)
        } completionHandler: { [weak window] in
            window?.orderOut(nil)
        }
    }

    func updateSearchQuery(_ newValue: String) {
        query = newValue
        searchTask?.cancel()
        statusMessage = nil

        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            if selectedItem?.isRecent == false {
                select(recentItems.first)
            }
            return
        }

        let localResults = allBrowsableItems.filter { item in
            item.provider == .spotify && (
                item.title.localizedCaseInsensitiveContains(trimmed)
                || item.subtitle.localizedCaseInsensitiveContains(trimmed)
                || item.detail.localizedCaseInsensitiveContains(trimmed)
            )
        }
        searchResults = Array(localResults.prefix(12))

        guard Defaults[.musicShelfCatalogSearch] else {
            statusMessage = String(localized: "Catalog search is disabled in Media settings.")
            return
        }

        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled, let self else { return }
            let results = await self.searchCatalog(for: trimmed)
            guard !Task.isCancelled else { return }
            self.searchResults = self.uniqueItems(localResults + results)
            self.isSearching = false
            if self.searchResults.isEmpty, self.statusMessage == nil {
                self.statusMessage = String(localized: "No Spotify results found")
            }
            if let first = self.searchResults.first {
                self.select(first)
            }
        }
    }

    fileprivate func items(for collection: MusicShelfCollection) -> [MusicShelfItem] {
        switch collection {
        case .albums:
            return uniqueItems(libraryAlbums + recentItems)
        case .artists:
            var seen = Set<String>()
            let recentArtists = recentItems.compactMap { item -> MusicShelfItem? in
                let key = item.subtitle.lowercased()
                guard seen.insert(key).inserted else { return nil }
                return MusicShelfItem(
                    id: "recent-artist|\(key)",
                    title: item.subtitle,
                    subtitle: String(localized: "Recently played artist"),
                    detail: item.title,
                    provider: item.provider,
                    catalogID: nil,
                    artworkURL: resolvedArtistArtwork[key],
                    artworkPath: resolvedArtistArtwork[key] == nil ? item.artworkPath : nil,
                    playbackURI: nil,
                    externalURL: nil,
                    isRecent: true,
                    kind: .artist,
                    lastPlayed: item.lastPlayed
                )
            }
            seen.removeAll()
            return (libraryArtists + recentArtists).filter {
                seen.insert($0.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)).inserted
            }
        case .playlists:
            return libraryPlaylists
        case .history:
            return recentItems
        }
    }

    var allBrowsableItems: [MusicShelfItem] {
        uniqueItems(libraryAlbums + libraryArtists + libraryPlaylists + recentItems)
    }

    func isPinned(_ item: MusicShelfItem) -> Bool {
        pinnedItemIDs.contains(item.id)
    }

    func togglePin(_ item: MusicShelfItem) {
        if pinnedItemIDs.contains(item.id) {
            pinnedItemIDs.remove(item.id)
        } else {
            pinnedItemIDs.insert(item.id)
        }
        UserDefaults.standard.set(Array(pinnedItemIDs), forKey: pinnedDefaultsKey)
    }

    func select(_ item: MusicShelfItem?) {
        trackLoadTask?.cancel()
        selectedItem = item
        tracks = []
        relatedItems = []
        statusMessage = nil
        guard let item else { return }

        if item.kind == .artist {
            isLoadingTracks = true
            trackLoadTask = Task { [weak self] in
                guard let self else { return }
                let loaded: [MusicShelfItem]
                if item.provider == .spotify, let artistID = item.catalogID {
                    loaded = await self.loadSpotifyArtistAlbums(artistID: artistID)
                } else {
                    loaded = self.recentItems.filter {
                        $0.subtitle.localizedCaseInsensitiveContains(item.title)
                    }
                }
                guard !Task.isCancelled, self.selectedItem?.id == item.id else { return }
                self.relatedItems = loaded
                self.isLoadingTracks = false
                self.statusMessage = loaded.isEmpty ? String(localized: "No albums available") : nil
            }
            return
        }

        if item.kind == .track {
            tracks = [
                MusicShelfTrack(
                    id: item.id,
                    title: item.title,
                    artist: item.subtitle,
                    duration: 0,
                    provider: item.provider,
                    playbackURI: item.playbackURI,
                    externalURL: item.externalURL
                )
            ]
            return
        }

        if item.isRecent, item.catalogID == nil {
            tracks = [
                MusicShelfTrack(
                    id: item.playbackURI ?? item.id,
                    title: item.detail,
                    artist: item.subtitle,
                    duration: 0,
                    provider: item.provider,
                    playbackURI: item.playbackURI,
                    externalURL: item.externalURL
                )
            ]
            return
        }

        guard let catalogID = item.catalogID else { return }
        isLoadingTracks = true
        trackLoadTask = Task { [weak self] in
            guard let self else { return }
            let loaded = await self.loadTracks(for: item, catalogID: catalogID)
            guard !Task.isCancelled, self.selectedItem?.id == item.id else { return }
            self.tracks = loaded
            self.isLoadingTracks = false
            self.statusMessage = loaded.isEmpty ? String(localized: "No tracks available") : nil
        }
    }

    func play(_ track: MusicShelfTrack) {
        Task { [weak self] in
            guard let self else { return }
            let didStart = await self.startPlayback(track)
            if !didStart {
                if self.statusMessage == nil {
                    self.statusMessage = String(localized: "Playback could not be started in the background.")
                }
            }
            if didStart, Defaults[.musicShelfCloseAfterPlaying] {
                self.hide()
            }
        }
    }

    func playSelectedAlbum(shuffled: Bool = false) {
        guard let item = selectedItem else { return }
        playCollection(item, shuffled: shuffled)
    }

    func playCollection(_ item: MusicShelfItem, shuffled: Bool = false) {
        if item.kind == .track {
            if let track = tracks.first(where: { $0.id == item.id }) ?? tracks.first {
                play(track)
            }
            return
        }

        if item.provider == .spotify,
           let uri = item.playbackURI,
           item.kind != .artist {
            Task { [weak self] in
                guard let self else { return }
                var didStart = await self.startSpotifyLocally(item, shuffled: shuffled)
                if !didStart, shuffled {
                    _ = await self.spotifyPlaybackRequest(
                        path: "/v1/me/player/shuffle",
                        method: "PUT",
                        queryItems: [URLQueryItem(name: "state", value: "true")]
                    )
                }
                guard let body = try? JSONSerialization.data(withJSONObject: ["context_uri": uri]) else { return }
                if !didStart {
                    didStart = await self.spotifyPlaybackRequest(
                        path: "/v1/me/player/play",
                        method: "PUT",
                        body: body
                    )
                }
                if !didStart { self.statusMessage = self.spotifyPlaybackHelp }
                if didStart, Defaults[.musicShelfCloseAfterPlaying] { self.hide() }
            }
            return
        }

        guard !tracks.isEmpty else { return }
        let track = shuffled ? tracks.randomElement() : tracks.first
        if let track { play(track) }
    }

    func togglePlayback() {
        guard musicManager.isSpotifyActive else {
            musicManager.togglePlay()
            return
        }
        let path = musicManager.isPlaying ? "/v1/me/player/pause" : "/v1/me/player/play"
        performSpotifyControl(
            path: path,
            method: "PUT",
            localCommand: musicManager.isPlaying ? .pause : .play
        )
    }

    func previousTrack() {
        guard musicManager.isSpotifyActive else {
            musicManager.previousTrack()
            return
        }
        performSpotifyControl(path: "/v1/me/player/previous", method: "POST", localCommand: .previous)
    }

    func nextTrack() {
        guard musicManager.isSpotifyActive else {
            musicManager.nextTrack()
            return
        }
        performSpotifyControl(path: "/v1/me/player/next", method: "POST", localCommand: .next)
    }

    func seek(to position: TimeInterval) {
        guard musicManager.isSpotifyActive else {
            musicManager.seek(to: position)
            return
        }
        let milliseconds = max(0, Int(position * 1_000))
        performSpotifyControl(
            path: "/v1/me/player/seek",
            method: "PUT",
            queryItems: [URLQueryItem(name: "position_ms", value: String(milliseconds))],
            localCommand: .seek(max(0, position))
        )
    }

    private func performSpotifyControl(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        localCommand: SpotifyLocalCommand? = nil
    ) {
        Task { [weak self] in
            guard let self else { return }
            if let localCommand, await self.runLocalSpotifyCommand(localCommand) {
                self.statusMessage = nil
                return
            }
            let webAPISucceeded = await self.spotifyPlaybackRequest(
                path: path,
                method: method,
                queryItems: queryItems
            )
            if webAPISucceeded {
                self.statusMessage = nil
                return
            }
            self.statusMessage = self.spotifyPlaybackHelp
        }
    }

    func clearHistory() {
        historyRecords.removeAll()
        recentItems.removeAll()
        selectedItem = nil
        tracks.removeAll()
        UserDefaults.standard.removeObject(forKey: historyDefaultsKey)

        if let directory = artworkCacheDirectory(),
           let cachedArtwork = try? FileManager.default.contentsOfDirectory(
               at: directory,
               includingPropertiesForKeys: nil,
               options: [.skipsHiddenFiles]
           ) {
            for artworkURL in cachedArtwork {
                try? FileManager.default.removeItem(at: artworkURL)
            }
        }
    }

    private func show(on screen: NSScreen, focusSearch: Bool = false) {
        let targetFrame = panelFrame(on: screen)
        let window = ensureWindow(frame: targetFrame)
        let initialFrame: NSRect
        switch Defaults[.musicShelfEdge] {
        case .left: initialFrame = targetFrame.offsetBy(dx: -34, dy: 0)
        case .right: initialFrame = targetFrame.offsetBy(dx: 34, dy: 0)
        case .bottom: initialFrame = targetFrame.offsetBy(dx: 0, dy: -34)
        }

        // NSWindow creates an empty content view by default. Checking
        // `window.contentView == nil` therefore left this panel transparent
        // forever; the hosting view itself is the reliable installation flag.
        if hostingView == nil {
            let view = NSHostingView(rootView: MusicShelfRootView(manager: self))
            view.frame = NSRect(origin: .zero, size: targetFrame.size)
            view.autoresizingMask = [.width, .height]
            window.contentView = view
            hostingView = view
        }

        hostingView?.frame = NSRect(origin: .zero, size: targetFrame.size)
        window.setFrame(initialFrame, display: true)
        window.alphaValue = 0
        window.ignoresMouseEvents = false
        window.orderFrontRegardless()
        if focusSearch {
            window.makeKey()
            searchFocusRequest &+= 1
        }

        isPresented = true
        shownAt = Date()
        lastPointerInside = Date()
        loadLibraryIfNeeded()
        refreshRecentArtistArtwork()
        if selectedItem == nil { select(libraryAlbums.first ?? recentItems.first) }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(targetFrame, display: true)
        }
    }

    private func ensureWindow(frame: NSRect) -> MusicShelfWindow {
        if let window { return window }

        let newWindow = MusicShelfWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newWindow.isReleasedWhenClosed = false
        newWindow.isFloatingPanel = true
        newWindow.hidesOnDeactivate = false
        newWindow.isOpaque = false
        newWindow.backgroundColor = .clear
        newWindow.hasShadow = false
        newWindow.level = .mainMenu + 2
        newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        newWindow.animationBehavior = .none
        ScreenCaptureVisibilityManager.shared.register(newWindow, scope: .panelsOnly)
        window = newWindow
        return newWindow
    }

    private func panelFrame(on screen: NSScreen) -> NSRect {
        let available = screen.visibleFrame
        switch Defaults[.musicShelfEdge] {
        case .left:
            let width = min(max(available.width * 0.27, 410), 470)
            return NSRect(x: available.minX, y: available.minY, width: width, height: available.height)
        case .right:
            let width = min(max(available.width * 0.27, 410), 470)
            return NSRect(x: available.maxX - width, y: available.minY, width: width, height: available.height)
        case .bottom:
            let width = min(max(available.width * 0.58, 680), 940)
            let height = min(max(available.height * 0.48, 420), 560)
            return NSRect(x: available.midX - width / 2, y: available.minY, width: width, height: height)
        }
    }

    private func observePlayback() {
        Publishers.CombineLatest4(
            musicManager.$songTitle,
            musicManager.$artistName,
            musicManager.$album,
            musicManager.$albumArt
        )
        .debounce(for: .milliseconds(420), scheduler: RunLoop.main)
        .sink { [weak self] title, artist, album, artwork in
            self?.recordCurrentTrack(title: title, artist: artist, album: album, artwork: artwork)
        }
        .store(in: &cancellables)
    }

    private func observeSettings() {
        Defaults.publisher(.enableMusicShelf, options: [])
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                guard let self else { return }
                if change.newValue {
                    // Opening once on enable makes the feature discoverable
                    // and confirms immediately that the switch took effect.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                        guard Defaults[.enableMusicShelf],
                              !LockScreenManager.shared.isLocked,
                              self?.isPresented == false
                        else { return }
                        self?.show()
                    }
                } else {
                    self.hide()
                }
                self.updateEdgeMonitoring()
            }
            .store(in: &cancellables)

        Defaults.publisher(.musicShelfRevealOnHover, options: [])
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateEdgeMonitoring() }
            .store(in: &cancellables)

        Defaults.publisher(.musicShelfEdge, options: [])
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.isPresented, let screen = self.window?.screen ?? NSScreen.main {
                    self.window?.setFrame(self.panelFrame(on: screen), display: true, animate: true)
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.musicShelfRecentLimit, options: [])
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.trimAndPersistHistory() }
            .store(in: &cancellables)

        LockScreenManager.shared.$isLocked
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] locked in
                guard locked else { return }
                self?.hide()
            }
            .store(in: &cancellables)
    }

    private func updateEdgeMonitoring() {
        edgePollTimer?.invalidate()
        edgePollTimer = nil
        guard Defaults[.enableMusicShelf], Defaults[.musicShelfRevealOnHover] else { return }

        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollPointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        edgePollTimer = timer
    }

    private func pollPointer() {
        guard Defaults[.enableMusicShelf], !LockScreenManager.shared.isLocked else {
            if isPresented { hide() }
            return
        }

        let location = NSEvent.mouseLocation
        let pointerScreen = NSScreen.screens.first(where: { $0.frame.contains(location) })
        if !isPresented,
           Date().timeIntervalSince(hiddenAt) > 0.45,
           let pointerScreen {
            let edgeDistance: CGFloat
            switch Defaults[.musicShelfEdge] {
            case .left: edgeDistance = abs(location.x - pointerScreen.frame.minX)
            case .right: edgeDistance = abs(pointerScreen.frame.maxX - location.x)
            case .bottom: edgeDistance = abs(location.y - pointerScreen.frame.minY)
            }
            if edgeDistance <= 10 {
                show(on: pointerScreen, focusSearch: false)
                return
            }
        }

        guard isPresented, let window else { return }
        let acceptsMouse = interactiveRegionContains(location, in: window)
        window.ignoresMouseEvents = !acceptsMouse
        if acceptsMouse {
            lastPointerInside = Date()
        } else if Defaults[.musicShelfAutoHide],
                  Date().timeIntervalSince(shownAt) > 1.2,
                  Date().timeIntervalSince(lastPointerInside) > 0.7 {
            hide()
        }
    }

    private func interactiveRegionContains(_ location: NSPoint, in window: NSWindow) -> Bool {
        let frame = window.frame
        guard frame.insetBy(dx: -8, dy: -8).contains(location) else { return false }

        let point = NSPoint(x: location.x - frame.minX, y: location.y - frame.minY)
        let width = frame.width
        let height = frame.height
        let isRight = Defaults[.musicShelfEdge] == .right
        let topPlayer = NSRect(
            x: isRight ? width - 310 : 0,
            y: height - 118,
            width: 310,
            height: 118
        )
        let bottomSearch = NSRect(
            x: isRight ? width - 215 : 0,
            y: 0,
            width: 215,
            height: 54
        )

        switch Defaults[.musicShelfEdge] {
        case .left, .right:
            let shelfX = isRight ? width - 135 : 0
            let shelf = NSRect(x: shelfX, y: 90, width: 135, height: max(220, height - 210))
            let label = NSRect(x: isRight ? width - 330 : 82, y: height * 0.44, width: 250, height: 90)
            let detail = NSRect(
                x: isRight ? 0 : 120,
                y: max(65, height * 0.5 - 230),
                width: max(0, width - 120),
                height: min(460, height - 150)
            )
            let results = NSRect(
                x: isRight ? width - 320 : 0,
                y: 35,
                width: 320,
                height: min(370, height * 0.52)
            )
            return topPlayer.contains(point)
                || bottomSearch.contains(point)
                || shelf.contains(point)
                || label.contains(point)
                || (isContextPanelPresented && detail.contains(point))
                || (!query.isEmpty && results.contains(point))
        case .bottom:
            let shelf = NSRect(x: 0, y: 0, width: width, height: 145)
            let label = NSRect(x: width / 2 - 135, y: 130, width: 270, height: 100)
            let detail = NSRect(x: width / 2 - 170, y: 115, width: 340, height: min(410, height - 120))
            return topPlayer.contains(point)
                || bottomSearch.contains(point)
                || shelf.contains(point)
                || label.contains(point)
                || (isContextPanelPresented && detail.contains(point))
                || (!query.isEmpty && detail.contains(point))
        }
    }

    private func recordCurrentTrack(title: String, artist: String, album: String, artwork: NSImage) {
        guard musicManager.hasActiveSession else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !cleanArtist.isEmpty else { return }

        let provider = provider(for: musicManager.bundleIdentifier)
        let albumTitle = cleanAlbum.isEmpty || cleanAlbum.lowercased() == "unknown" ? cleanTitle : cleanAlbum
        let id = "recent|\(provider.rawValue)|\(albumTitle.lowercased())|\(cleanArtist.lowercased())"
        let priorArtworkPath = historyRecords.first(where: { $0.id == id })?.artworkPath
        let isFallbackArtwork = musicManager.usingAppIconForArtwork
            || MusicShelfArtworkValidator.isProviderIcon(artwork, provider: provider)
        let artworkPath = isFallbackArtwork
            ? priorArtworkPath
            : persistArtwork(artwork, identifier: id)
        let identifier = musicManager.currentContentIdentifier
        let contentURL = musicManager.currentContentURL
        let playbackURI = provider == .spotify ? canonicalSpotifyURI(identifier: identifier, contentURL: contentURL) : nil

        let record = MusicShelfHistoryRecord(
            id: id,
            album: albumTitle,
            artist: cleanArtist,
            trackTitle: cleanTitle,
            provider: provider,
            artworkPath: artworkPath,
            playbackURI: playbackURI,
            externalURL: contentURL,
            lastPlayed: Date()
        )

        historyRecords.removeAll { $0.id == id }
        historyRecords.insert(record, at: 0)
        trimAndPersistHistory()
        refreshRecentArtistArtwork()
        if selectedItem == nil { select(recentItems.first) }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyDefaultsKey),
              let records = try? JSONDecoder().decode([MusicShelfHistoryRecord].self, from: data)
        else { return }
        var removedFallbackArtwork = false
        historyRecords = records.map { record in
            guard record.provider == .spotify,
                  let path = record.artworkPath,
                  let image = NSImage(contentsOfFile: path),
                  MusicShelfArtworkValidator.isProviderIcon(image, provider: record.provider)
            else { return record }

            removedFallbackArtwork = true
            return MusicShelfHistoryRecord(
                id: record.id,
                album: record.album,
                artist: record.artist,
                trackTitle: record.trackTitle,
                provider: record.provider,
                artworkPath: nil,
                playbackURI: record.playbackURI,
                externalURL: record.externalURL,
                lastPlayed: record.lastPlayed
            )
        }
        .sorted { $0.lastPlayed > $1.lastPlayed }
        recentItems = historyRecords.map(\.item)
        if removedFallbackArtwork,
           let sanitized = try? JSONEncoder().encode(historyRecords) {
            UserDefaults.standard.set(sanitized, forKey: historyDefaultsKey)
        }
    }

    private func loadPinnedItems() {
        pinnedItemIDs = Set(UserDefaults.standard.stringArray(forKey: pinnedDefaultsKey) ?? [])
    }

    private func uniqueItems(_ items: [MusicShelfItem]) -> [MusicShelfItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    private func refreshRecentArtistArtwork() {
        let artists = recentItems
            .map(\.subtitle)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let unresolved = Array(Set(artists.map { $0.lowercased() }))
            .filter { resolvedArtistArtwork[$0] == nil }
        guard !unresolved.isEmpty else { return }

        artistArtworkTask?.cancel()
        artistArtworkTask = Task { [weak self] in
            guard let self else { return }
            let originalNames = artists.reduce(into: [String: String]()) { names, artist in
                names[artist.lowercased()] = artist
            }

            await withTaskGroup(of: (String, URL?).self) { group in
                for key in unresolved.prefix(40) {
                    guard let name = originalNames[key] else { continue }
                    group.addTask {
                        (key, await Self.deezerArtistArtwork(named: name))
                    }
                }

                for await (key, url) in group {
                    guard !Task.isCancelled else { return }
                    if let url { self.resolvedArtistArtwork[key] = url }
                }
            }
            self.artistArtworkTask = nil
        }
    }

    nonisolated private static func deezerArtistArtwork(named artist: String) async -> URL? {
        var components = URLComponents(string: "https://api.deezer.com/search/artist")!
        components.queryItems = [
            URLQueryItem(name: "q", value: artist),
            URLQueryItem(name: "limit", value: "4")
        ]
        guard let url = components.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let result = try? JSONDecoder().decode(DeezerArtistSearchResponse.self, from: data)
        else { return nil }

        let normalized = artist.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let match = result.data.first {
            $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == normalized
        } ?? result.data.first
        return match?.pictureXL ?? match?.pictureBig ?? match?.pictureMedium
    }

    private func loadLibraryIfNeeded() {
        guard libraryLoadTask == nil,
              SpotifyLibraryManager.shared.isAuthenticated,
              libraryAlbums.isEmpty,
              libraryArtists.isEmpty,
              libraryPlaylists.isEmpty
        else { return }

        libraryLoadTask = Task { [weak self] in
            guard let self else { return }
            async let albums = self.loadSpotifySavedAlbums()
            async let artists = self.loadSpotifyFollowedArtists()
            async let playlists = self.loadSpotifyPlaylists()
            let loaded = await (albums, artists, playlists)
            guard !Task.isCancelled else { return }
            self.libraryAlbums = loaded.0
            self.libraryArtists = loaded.1
            self.libraryPlaylists = loaded.2
            self.libraryLoadTask = nil
            if self.selectedItem == nil {
                self.select(self.libraryAlbums.first ?? self.recentItems.first)
            }
        }
    }

    private func trimAndPersistHistory() {
        let limit = min(max(Defaults[.musicShelfRecentLimit], 6), 40)
        historyRecords = Array(historyRecords.prefix(limit))
        recentItems = historyRecords.map(\.item)
        if let data = try? JSONEncoder().encode(historyRecords) {
            UserDefaults.standard.set(data, forKey: historyDefaultsKey)
        }
    }

    private func artworkCacheDirectory() -> URL? {
        guard let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let directory = cache.appendingPathComponent("Atoll/MusicShelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func persistArtwork(_ artwork: NSImage, identifier: String) -> String? {
        guard let directory = artworkCacheDirectory(),
              let tiff = artwork.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff),
              let data = representation.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        else { return nil }

        let digest = identifier.data(using: .utf8)?.base64EncodedString() ?? UUID().uuidString
        let safeName = digest.replacingOccurrences(of: "/", with: "_")
        let url = directory.appendingPathComponent(safeName).appendingPathExtension("jpg")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
        }
        return url.path
    }

    private func provider(for bundleIdentifier: String?) -> MusicShelfProvider {
        switch bundleIdentifier {
        case "com.apple.Music": return .appleMusic
        case SpotifyController.bundleIdentifier: return .spotify
        default: return .other
        }
    }

    private func canonicalSpotifyURI(identifier: String?, contentURL: String?) -> String? {
        for candidate in [identifier, contentURL].compactMap({ $0 }) {
            if candidate.hasPrefix("spotify:track:") { return candidate }
            if let url = URL(string: candidate),
               let index = url.pathComponents.firstIndex(of: "track"),
               index + 1 < url.pathComponents.count {
                return "spotify:track:\(url.pathComponents[index + 1])"
            }
        }
        return nil
    }

    private func searchCatalog(for query: String) async -> [MusicShelfItem] {
        if SpotifyLibraryManager.shared.isAuthenticated {
            let spotifyResults = await searchSpotifyCatalog(query: query)
            if !spotifyResults.isEmpty { return spotifyResults }
        }

        let publicResults = await searchPublicMusicCatalog(query: query)
        if !publicResults.isEmpty {
            statusMessage = nil
            return publicResults
        }

        statusMessage = String(localized: "No Spotify-compatible results found")
        return []
    }

    private func searchPublicMusicCatalog(query: String) async -> [MusicShelfItem] {
        var components = URLComponents(string: "https://api.deezer.com/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "12")
        ]
        guard let url = components.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let result = try? JSONDecoder().decode(DeezerTrackSearchResponse.self, from: data)
        else { return [] }

        return result.data.compactMap { track in
            guard !track.isrc.isEmpty else { return nil }
            return MusicShelfItem(
                id: "catalog-track|\(track.id)",
                title: track.title,
                subtitle: track.artist.name,
                detail: track.album.title,
                provider: .spotify,
                catalogID: track.isrc,
                artworkURL: track.album.coverXL ?? track.album.coverBig ?? track.album.coverMedium,
                artworkPath: nil,
                playbackURI: "isrc:\(track.isrc)",
                externalURL: nil,
                isRecent: false,
                kind: .track
            )
        }
    }

    private func loadTracks(for item: MusicShelfItem, catalogID: String) async -> [MusicShelfTrack] {
        switch item.provider {
        case .spotify:
            if item.kind == .playlist {
                return await loadSpotifyPlaylistTracks(playlistID: catalogID)
            }
            return await loadSpotifyTracks(albumID: catalogID)
        case .appleMusic, .other: return await loadAppleTracks(collectionID: catalogID)
        }
    }

    private func searchAppleAlbums(query: String) async -> [MusicShelfItem] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "limit", value: "24")
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(ITunesAlbumSearchResponse.self, from: data)
        else { return [] }

        return response.results.compactMap { album in
            guard let id = album.collectionID, let title = album.collectionName else { return nil }
            return MusicShelfItem(
                id: "apple|\(id)",
                title: title,
                subtitle: album.artistName ?? String(localized: "Unknown artist"),
                detail: album.primaryGenreName ?? String(localized: "Album"),
                provider: .appleMusic,
                catalogID: String(id),
                artworkURL: album.artworkURL(size: 600),
                artworkPath: nil,
                playbackURI: nil,
                externalURL: album.collectionViewURL.flatMap { URL(string: $0) },
                isRecent: false
            )
        }
    }

    private func loadAppleTracks(collectionID: String) async -> [MusicShelfTrack] {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "id", value: collectionID),
            URLQueryItem(name: "entity", value: "song")
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(ITunesTrackLookupResponse.self, from: data)
        else { return [] }

        return response.results.compactMap { result in
            guard result.wrapperType == "track", let id = result.trackID, let title = result.trackName else { return nil }
            return MusicShelfTrack(
                id: "apple-track|\(id)",
                title: title,
                artist: result.artistName ?? selectedItem?.subtitle ?? "",
                duration: TimeInterval(result.trackTimeMillis ?? 0) / 1000,
                provider: .appleMusic,
                playbackURI: nil,
                externalURL: result.trackViewURL.flatMap { URL(string: $0) }
            )
        }
    }

    private func searchSpotifyCatalog(query: String) async -> [MusicShelfItem] {
        guard let data = await spotifyData(path: "/v1/search", queryItems: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "track,album,artist,playlist"),
            URLQueryItem(name: "limit", value: "12")
        ]),
        let response = try? JSONDecoder().decode(SpotifyCatalogSearchResponse.self, from: data)
        else { return [] }

        let albums = response.albums?.items.map(spotifyAlbumItem) ?? []
        let artists = response.artists?.items.map(spotifyArtistItem) ?? []
        let playlists = response.playlists?.items.compactMap { $0 }.map(spotifyPlaylistItem) ?? []
        let tracks = response.tracks?.items.map(spotifyTrackItem) ?? []
        return tracks + albums + artists + playlists
    }

    private func resolveSpotifyURI(
        forISRC isrc: String,
        title: String,
        artist: String,
        release: String?
    ) async -> String? {
        if SpotifyLibraryManager.shared.isAuthenticated,
           let data = await spotifyData(path: "/v1/search", queryItems: [
               URLQueryItem(name: "q", value: "isrc:\(isrc)"),
               URLQueryItem(name: "type", value: "track"),
               URLQueryItem(name: "limit", value: "1")
           ]),
           let response = try? JSONDecoder().decode(SpotifyCatalogSearchResponse.self, from: data),
           let uri = response.tracks?.items.first?.uri {
            return uri
        }

        var listenBrainz = URLComponents(
            string: "https://labs.api.listenbrainz.org/spotify-id-from-metadata/json"
        )!
        listenBrainz.queryItems = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "release_name", value: release)
        ]
        if let url = listenBrainz.url {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue(
                "Atoll/1.0 (https://github.com/Ebullioscopic/Atoll)",
                forHTTPHeaderField: "User-Agent"
            )
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let matches = try? JSONDecoder().decode([ListenBrainzSpotifyMatch].self, from: data),
               let identifier = matches.first?.spotifyTrackIDs.first,
               !identifier.isEmpty {
                return identifier.hasPrefix("spotify:track:")
                    ? identifier
                    : "spotify:track:\(identifier)"
            }
        }

        var components = URLComponents(string: "https://musicbrainz.org/ws/2/isrc/\(isrc)")!
        components.queryItems = [
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "inc", value: "url-rels")
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(
            "Atoll/1.0 (https://github.com/Ebullioscopic/Atoll)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let lookup = try? JSONDecoder().decode(MusicBrainzISRCResponse.self, from: data)
        else { return nil }

        return lookup.recordings
            .flatMap(\.relations)
            .compactMap { spotifyURI(from: $0.url.resource) }
            .first
    }

    private func spotifyURI(from resource: String) -> String? {
        if resource.hasPrefix("spotify:track:") { return resource }
        guard let url = URL(string: resource),
              url.host?.localizedCaseInsensitiveContains("spotify.com") == true,
              let trackIndex = url.pathComponents.firstIndex(of: "track"),
              trackIndex + 1 < url.pathComponents.count
        else { return nil }
        let identifier = url.pathComponents[trackIndex + 1]
        guard !identifier.isEmpty else { return nil }
        return "spotify:track:\(identifier)"
    }

    private func loadSpotifySavedAlbums() async -> [MusicShelfItem] {
        guard let data = await spotifyData(path: "/v1/me/albums", queryItems: [
            URLQueryItem(name: "limit", value: "50")
        ]),
        let response = try? JSONDecoder().decode(SpotifySavedAlbumPage.self, from: data)
        else { return [] }
        return response.items.map(\.album).map(spotifyAlbumItem)
    }

    private func loadSpotifyFollowedArtists() async -> [MusicShelfItem] {
        guard let data = await spotifyData(path: "/v1/me/following", queryItems: [
            URLQueryItem(name: "type", value: "artist"),
            URLQueryItem(name: "limit", value: "50")
        ]),
        let response = try? JSONDecoder().decode(SpotifyFollowedArtistsResponse.self, from: data)
        else { return [] }
        return response.artists.items.map(spotifyArtistItem)
    }

    private func loadSpotifyPlaylists() async -> [MusicShelfItem] {
        guard let data = await spotifyData(path: "/v1/me/playlists", queryItems: [
            URLQueryItem(name: "limit", value: "50")
        ]),
        let response = try? JSONDecoder().decode(SpotifyPlaylistPage.self, from: data)
        else { return [] }
        return response.items.compactMap { $0 }.map(spotifyPlaylistItem)
    }

    private func loadSpotifyArtistAlbums(artistID: String) async -> [MusicShelfItem] {
        guard let data = await spotifyData(path: "/v1/artists/\(artistID)/albums", queryItems: [
            URLQueryItem(name: "include_groups", value: "album,single"),
            URLQueryItem(name: "limit", value: "30")
        ]),
        let response = try? JSONDecoder().decode(SpotifyAlbumPage.self, from: data)
        else { return [] }
        return uniqueItems(response.items.map(spotifyAlbumItem))
    }

    private func spotifyAlbumItem(_ album: SpotifyAlbumResult) -> MusicShelfItem {
        MusicShelfItem(
            id: "spotify-album|\(album.id)",
            title: album.name,
            subtitle: album.artists.map(\.name).joined(separator: ", "),
            detail: album.releaseDate ?? album.albumType.capitalized,
            provider: .spotify,
            catalogID: album.id,
            artworkURL: album.images.first?.url,
            artworkPath: nil,
            playbackURI: album.uri,
            externalURL: album.externalURLs.spotify,
            isRecent: false,
            kind: .album
        )
    }

    private func spotifyArtistItem(_ artist: SpotifyArtistResult) -> MusicShelfItem {
        MusicShelfItem(
            id: "spotify-artist|\(artist.id)",
            title: artist.name,
            subtitle: String(localized: "Artist"),
            detail: artist.genres.first?.capitalized ?? String(localized: "Spotify artist"),
            provider: .spotify,
            catalogID: artist.id,
            artworkURL: artist.images.first?.url,
            artworkPath: nil,
            playbackURI: artist.uri,
            externalURL: artist.externalURLs.spotify,
            isRecent: false,
            kind: .artist
        )
    }

    private func spotifyPlaylistItem(_ playlist: SpotifyPlaylistResult) -> MusicShelfItem {
        MusicShelfItem(
            id: "spotify-playlist|\(playlist.id)",
            title: playlist.name,
            subtitle: playlist.owner.displayName ?? String(localized: "Spotify playlist"),
            detail: String(localized: "\(playlist.tracks.total) songs"),
            provider: .spotify,
            catalogID: playlist.id,
            artworkURL: playlist.images.first?.url,
            artworkPath: nil,
            playbackURI: playlist.uri,
            externalURL: playlist.externalURLs.spotify,
            isRecent: false,
            kind: .playlist
        )
    }

    private func spotifyTrackItem(_ track: SpotifyTrackResult) -> MusicShelfItem {
        MusicShelfItem(
            id: "spotify-track|\(track.id)",
            title: track.name,
            subtitle: track.artists.map(\.name).joined(separator: ", "),
            detail: track.album?.name ?? String(localized: "Spotify track"),
            provider: .spotify,
            catalogID: track.id,
            artworkURL: track.album?.images.first?.url,
            artworkPath: nil,
            playbackURI: track.uri,
            externalURL: track.externalURLs.spotify,
            isRecent: false,
            kind: .track
        )
    }

    private func loadSpotifyTracks(albumID: String) async -> [MusicShelfTrack] {
        guard let data = await spotifyData(path: "/v1/albums/\(albumID)/tracks", queryItems: [
            URLQueryItem(name: "limit", value: "50")
        ]),
        let response = try? JSONDecoder().decode(SpotifyTrackPage.self, from: data)
        else { return [] }

        return response.items.map { track in
            MusicShelfTrack(
                id: "spotify-track|\(track.id)",
                title: track.name,
                artist: track.artists.map(\.name).joined(separator: ", "),
                duration: TimeInterval(track.durationMS) / 1000,
                provider: .spotify,
                playbackURI: track.uri,
                externalURL: track.externalURLs.spotify
            )
        }
    }

    private func loadSpotifyPlaylistTracks(playlistID: String) async -> [MusicShelfTrack] {
        guard let data = await spotifyData(path: "/v1/playlists/\(playlistID)/tracks", queryItems: [
            URLQueryItem(name: "limit", value: "50")
        ]),
        let response = try? JSONDecoder().decode(SpotifyPlaylistTrackPage.self, from: data)
        else { return [] }

        return response.items.compactMap(\.track).map { track in
            MusicShelfTrack(
                id: "spotify-track|\(track.id)",
                title: track.name,
                artist: track.artists.map(\.name).joined(separator: ", "),
                duration: TimeInterval(track.durationMS) / 1000,
                provider: .spotify,
                playbackURI: track.uri,
                externalURL: track.externalURLs.spotify
            )
        }
    }

    private func spotifyData(path: String, queryItems: [URLQueryItem]) async -> Data? {
        guard let result = await spotifyRequest(
            path: path,
            method: "GET",
            queryItems: queryItems
        ), (200..<300).contains(result.statusCode) else { return nil }
        return result.data
    }

    private func spotifyRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil
    ) async -> (data: Data, statusCode: Int)? {
        var components = URLComponents(string: "https://api.spotify.com\(path)")!
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { return nil }

        func send(with token: String) async -> (data: Data, statusCode: Int)? {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.httpBody = body
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if body != nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse
            else { return nil }
            return (data, http.statusCode)
        }

        guard let token = await SpotifyLibraryManager.shared.catalogAccessToken(),
              let first = await send(with: token)
        else { return nil }
        guard first.statusCode == 401 else { return first }
        guard let refreshed = await SpotifyLibraryManager.shared.catalogAccessToken(forceRefresh: true) else {
            return first
        }
        return await send(with: refreshed)
    }

    private func spotifyPlaybackRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil
    ) async -> Bool {
        guard SpotifyLibraryManager.shared.isAuthenticated else {
            statusMessage = String(localized: "Connect Spotify in Media settings to control playback without opening the app.")
            return false
        }
        guard let response = await spotifyRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            body: body
        ) else { return false }
        return (200..<300).contains(response.statusCode)
    }

    private func startPlayback(_ track: MusicShelfTrack) async -> Bool {
        switch track.provider {
        case .spotify:
            guard var uri = track.playbackURI else { return false }
            if uri.hasPrefix("isrc:") {
                statusMessage = String(localized: "Finding this recording on Spotify…")
                let isrc = String(uri.dropFirst("isrc:".count))
                guard let resolvedURI = await resolveSpotifyURI(
                    forISRC: isrc,
                    title: track.title,
                    artist: track.artist,
                    release: selectedItem?.detail
                ) else {
                    statusMessage = String(localized: "This catalog result could not be matched to a Spotify track.")
                    return false
                }
                uri = resolvedURI
            }

            guard let body = try? JSONSerialization.data(withJSONObject: ["uris": [uri]]) else { return false }
            let selectedContext = selectedItem?.playbackURI.flatMap {
                $0.hasPrefix("spotify:") ? $0 : nil
            }
            var didStart = await startSpotifyTrackLocally(uri: uri, contextURI: selectedContext)
            if !didStart {
                didStart = await spotifyPlaybackRequest(
                    path: "/v1/me/player/play",
                    method: "PUT",
                    body: body
                )
            }
            if !didStart, statusMessage == nil {
                statusMessage = spotifyPlaybackHelp
            }
            return didStart
        case .appleMusic:
            let title = appleScriptEscaped(track.title)
            let artist = appleScriptEscaped(track.artist)
            let script = """
            tell application "Music"
                try
                    set matchingTracks to (every track of library playlist 1 whose name is "\(title)" and artist is "\(artist)")
                    if (count of matchingTracks) > 0 then
                        play item 1 of matchingTracks
                        return true
                    end if
                end try
                return false
            end tell
            """
            if let result = try? await AppleScriptHelper.execute(script), result.booleanValue {
                return true
            }
        case .other:
            musicManager.openMusicApp()
            return true
        }

        if let externalURL = track.externalURL {
            return NSWorkspace.shared.open(externalURL)
        }
        musicManager.openMusicApp()
        return false
    }

    private func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func startSpotifyLocally(_ item: MusicShelfItem, shuffled: Bool) async -> Bool {
        var available = tracks.compactMap(\.playbackURI)
        if available.isEmpty, let catalogID = item.catalogID {
            let loaded = await loadTracks(for: item, catalogID: catalogID)
            available = loaded.compactMap(\.playbackURI)
            if selectedItem?.id == item.id { tracks = loaded }
        }
        guard let trackURI = shuffled ? available.randomElement() : available.first else { return false }
        return await startSpotifyTrackLocally(uri: trackURI, contextURI: item.playbackURI)
    }

    private func startSpotifyTrackLocally(uri: String, contextURI: String?) async -> Bool {
        await runLocalSpotifyCommand(.playTrack(uri: uri, contextURI: contextURI))
    }

    private func runLocalSpotifyCommand(_ command: SpotifyLocalCommand) async -> Bool {
        guard let spotify = NSRunningApplication.runningApplications(
            withBundleIdentifier: SpotifyController.bundleIdentifier
        ).first else {
            statusMessage = String(localized: "Open Spotify once to use background playback with a Free account.")
            return false
        }

        let presentationGuard = beginSpotifyPresentationGuard(for: spotify)

        if case .seek(let position) = command {
            let didSeek = await setSpotifyPosition(position)
            restoreSpotifyPresentation(presentationGuard)
            return didSeek
        }

        let eventID: AEEventID
        switch command {
        case .play: eventID = fourCharacterCode("Play")
        case .pause: eventID = fourCharacterCode("Paus")
        case .previous: eventID = fourCharacterCode("Prev")
        case .next: eventID = fourCharacterCode("Next")
        case .playTrack: eventID = fourCharacterCode("PCtx")
        case .seek: return false
        }

        let target = NSAppleEventDescriptor(processIdentifier: spotify.processIdentifier)
        let event = NSAppleEventDescriptor(
            eventClass: fourCharacterCode("spfy"),
            eventID: eventID,
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        if case .playTrack(let uri, let contextURI) = command {
            event.setParam(NSAppleEventDescriptor(string: uri), forKeyword: AEKeyword(keyDirectObject))
            if let contextURI, contextURI != uri {
                event.setParam(
                    NSAppleEventDescriptor(string: contextURI),
                    forKeyword: fourCharacterCode("cotx")
                )
            }
        }

        do {
            _ = try event.sendEvent(
                options: [.noReply, .neverInteract, .dontRecord],
                timeout: 1
            )
            restoreSpotifyPresentation(presentationGuard)
            return true
        } catch {
            restoreSpotifyPresentation(presentationGuard)
            return false
        }
    }

    private func setSpotifyPosition(_ position: TimeInterval) async -> Bool {
        let script = """
        tell application id "com.spotify.client"
            set player position to \(max(0, position))
        end tell
        """
        do {
            _ = try await AppleScriptHelper.execute(script)
            return true
        } catch {
            return false
        }
    }

    private func beginSpotifyPresentationGuard(
        for spotify: NSRunningApplication
    ) -> SpotifyPresentationGuard {
        endSpotifyPresentationGuard()

        let frontmost = NSWorkspace.shared.frontmostApplication
        let snapshot = SpotifyPresentationGuard(
            spotifyPID: spotify.processIdentifier,
            frontmostPID: frontmost?.processIdentifier == spotify.processIdentifier
                ? nil
                : frontmost?.processIdentifier,
            shouldRemainHidden: spotify.isHidden,
            wasActive: spotify.isActive
        )
        guard !snapshot.wasActive else { return snapshot }

        let center = NSWorkspace.shared.notificationCenter
        spotifyActivationObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  activated.processIdentifier == snapshot.spotifyPID
            else { return }
            Task { @MainActor [weak self] in
                self?.restoreSpotifyPresentation(snapshot)
            }
        }

        // Spotify can unhide itself a few frames after accepting the command.
        // Re-assert the previous presentation state across that short window so
        // neither its window nor its menu bar flashes in front of the user.
        spotifyPresentationRestoreTask = Task { [weak self] in
            for delay in [15, 45, 100, 180, 300] {
                do {
                    try await Task.sleep(for: .milliseconds(delay))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.restoreSpotifyPresentation(snapshot)
            }
            self?.endSpotifyPresentationGuard()
        }

        return snapshot
    }

    private func restoreSpotifyPresentation(_ snapshot: SpotifyPresentationGuard) {
        guard !snapshot.wasActive,
              let spotify = NSRunningApplication(processIdentifier: snapshot.spotifyPID)
        else { return }

        if snapshot.shouldRemainHidden, !spotify.isHidden {
            spotify.hide()
        }

        if spotify.isActive {
            if let frontmostPID = snapshot.frontmostPID,
               let previousApplication = NSRunningApplication(processIdentifier: frontmostPID) {
                previousApplication.activate(options: [])
            } else {
                spotify.hide()
            }
        }
    }

    private func endSpotifyPresentationGuard() {
        spotifyPresentationRestoreTask?.cancel()
        spotifyPresentationRestoreTask = nil
        if let spotifyActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spotifyActivationObserver)
            self.spotifyActivationObserver = nil
        }
    }

    private func fourCharacterCode(_ value: String) -> OSType {
        value.utf8.prefix(4).reduce(0) { ($0 << 8) | OSType($1) }
    }

    private var spotifyPlaybackHelp: String {
        String(localized: "Spotify could not play in the background. Keep the Spotify desktop app running, or reconnect in Media settings for Spotify Connect.")
    }
}

private struct DeezerArtistSearchResponse: Decodable {
    let data: [DeezerArtistResult]
}

private struct DeezerArtistResult: Decodable {
    let name: String
    let pictureMedium: URL?
    let pictureBig: URL?
    let pictureXL: URL?

    enum CodingKeys: String, CodingKey {
        case name
        case pictureMedium = "picture_medium"
        case pictureBig = "picture_big"
        case pictureXL = "picture_xl"
    }
}

private struct DeezerTrackSearchResponse: Decodable {
    let data: [DeezerTrackResult]
}

private struct DeezerTrackResult: Decodable {
    struct Artist: Decodable { let name: String }
    struct Album: Decodable {
        let title: String
        let coverMedium: URL?
        let coverBig: URL?
        let coverXL: URL?

        enum CodingKeys: String, CodingKey {
            case title
            case coverMedium = "cover_medium"
            case coverBig = "cover_big"
            case coverXL = "cover_xl"
        }
    }

    let id: Int
    let title: String
    let isrc: String
    let artist: Artist
    let album: Album
}

private struct MusicBrainzISRCResponse: Decodable {
    struct Recording: Decodable {
        struct Relation: Decodable {
            struct Resource: Decodable { let resource: String }
            let url: Resource
        }
        let relations: [Relation]
    }
    let recordings: [Recording]
}

private struct ListenBrainzSpotifyMatch: Decodable {
    let spotifyTrackIDs: [String]

    enum CodingKeys: String, CodingKey {
        case spotifyTrackIDs = "spotify_track_ids"
    }
}

private struct ITunesAlbumSearchResponse: Decodable {
    let results: [ITunesAlbumResult]
}

private struct ITunesAlbumResult: Decodable {
    let collectionID: Int?
    let collectionName: String?
    let artistName: String?
    let artworkUrl100: String?
    let collectionViewURL: String?
    let primaryGenreName: String?

    enum CodingKeys: String, CodingKey {
        case collectionID = "collectionId"
        case collectionName, artistName, artworkUrl100
        case collectionViewURL = "collectionViewUrl"
        case primaryGenreName
    }

    func artworkURL(size: Int) -> URL? {
        artworkUrl100
            .map { $0.replacingOccurrences(of: "100x100", with: "\(size)x\(size)") }
            .flatMap { URL(string: $0) }
    }
}

private struct ITunesTrackLookupResponse: Decodable {
    let results: [ITunesTrackResult]
}

private struct ITunesTrackResult: Decodable {
    let wrapperType: String?
    let trackID: Int?
    let trackName: String?
    let artistName: String?
    let trackTimeMillis: Int?
    let trackViewURL: String?

    enum CodingKeys: String, CodingKey {
        case wrapperType, trackName, artistName, trackTimeMillis
        case trackID = "trackId"
        case trackViewURL = "trackViewUrl"
    }
}

private struct SpotifyCatalogSearchResponse: Decodable {
    let albums: SpotifyAlbumPage?
    let artists: SpotifyArtistPage?
    let playlists: SpotifyPlaylistPage?
    let tracks: SpotifyTrackPage?
}

private struct SpotifyAlbumPage: Decodable {
    let items: [SpotifyAlbumResult]
}

private struct SpotifySavedAlbumPage: Decodable {
    struct Entry: Decodable { let album: SpotifyAlbumResult }
    let items: [Entry]
}

private struct SpotifyAlbumResult: Decodable {
    struct Image: Decodable { let url: URL }
    struct Artist: Decodable { let name: String }
    struct ExternalURLs: Decodable {
        let spotify: URL?
        enum CodingKeys: String, CodingKey { case spotify }
    }

    let id: String
    let name: String
    let albumType: String
    let artists: [Artist]
    let images: [Image]
    let uri: String
    let externalURLs: ExternalURLs
    let releaseDate: String?

    enum CodingKeys: String, CodingKey {
        case id, name, artists, images, uri
        case albumType = "album_type"
        case externalURLs = "external_urls"
        case releaseDate = "release_date"
    }
}

private struct SpotifyFollowedArtistsResponse: Decodable {
    let artists: SpotifyArtistPage
}

private struct SpotifyArtistPage: Decodable {
    let items: [SpotifyArtistResult]
}

private struct SpotifyArtistResult: Decodable {
    struct Image: Decodable { let url: URL }
    struct ExternalURLs: Decodable {
        let spotify: URL?
        enum CodingKeys: String, CodingKey { case spotify }
    }

    let id: String
    let name: String
    let genres: [String]
    let images: [Image]
    let uri: String
    let externalURLs: ExternalURLs

    enum CodingKeys: String, CodingKey {
        case id, name, genres, images, uri
        case externalURLs = "external_urls"
    }
}

private struct SpotifyPlaylistPage: Decodable {
    let items: [SpotifyPlaylistResult?]
}

private struct SpotifyPlaylistResult: Decodable {
    struct Image: Decodable { let url: URL }
    struct Owner: Decodable {
        let displayName: String?
        enum CodingKeys: String, CodingKey { case displayName = "display_name" }
    }
    struct Tracks: Decodable { let total: Int }
    struct ExternalURLs: Decodable {
        let spotify: URL?
        enum CodingKeys: String, CodingKey { case spotify }
    }

    let id: String
    let name: String
    let owner: Owner
    let tracks: Tracks
    let images: [Image]
    let uri: String
    let externalURLs: ExternalURLs

    enum CodingKeys: String, CodingKey {
        case id, name, owner, tracks, images, uri
        case externalURLs = "external_urls"
    }
}

private struct SpotifyTrackPage: Decodable {
    let items: [SpotifyTrackResult]
}

private struct SpotifyPlaylistTrackPage: Decodable {
    struct Entry: Decodable { let track: SpotifyTrackResult? }
    let items: [Entry]
}

private struct SpotifyTrackResult: Decodable {
    struct Artist: Decodable { let name: String }
    struct Album: Decodable {
        struct Image: Decodable { let url: URL }
        let name: String
        let images: [Image]
    }
    struct ExternalURLs: Decodable {
        let spotify: URL?
        enum CodingKeys: String, CodingKey { case spotify }
    }

    let id: String
    let name: String
    let artists: [Artist]
    let durationMS: Int
    let uri: String
    let externalURLs: ExternalURLs
    let album: Album?

    enum CodingKeys: String, CodingKey {
        case id, name, artists, uri, album
        case durationMS = "duration_ms"
        case externalURLs = "external_urls"
    }
}

private struct MusicShelfRootView: View {
    @ObservedObject var manager: MusicShelfManager
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.musicShelfShowNowPlayingControls) private var showNowPlayingControls
    @Default(.musicShelfEdge) private var shelfEdge

    @State private var collection: MusicShelfCollection = .albums
    @State private var centeredItemID: String?
    @State private var showsDetail = false
    @State private var isScrubbing = false
    @State private var scrubPosition: TimeInterval = 0
    @State private var wheelPosition: CGFloat = 0
    @State private var wheelDragOrigin: CGFloat?
    @State private var wheelIsInteracting = false
    @State private var wheelSettleTask: Task<Void, Never>?
    @State private var lastWheelFeedbackIndex: Int?
    @FocusState private var searchFocused: Bool

    private let playbackClock = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var displayedItems: [MusicShelfItem] {
        manager.items(for: collection)
    }

    private var focusedShelfItem: MusicShelfItem? {
        if showsDetail { return manager.selectedItem }
        if let centeredItemID,
           let centered = displayedItems.first(where: { $0.id == centeredItemID }) {
            return centered
        }
        return manager.selectedItem
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.clear

                if shelfEdge == .bottom {
                    bottomShelf(size: geometry.size)
                } else {
                    sideShelf(size: geometry.size)
                }

                if showNowPlayingControls, musicManager.hasActiveSession {
                    nowPlayingCluster
                        .frame(width: 284)
                        .position(
                            x: shelfEdge == .right ? geometry.size.width - 150 : 150,
                            y: 66
                        )
                        .zIndex(50)
                }

                searchField
                    .frame(width: 184)
                    .position(
                        x: shelfEdge == .right ? geometry.size.width - 102 : 102,
                        y: geometry.size.height - 25
                    )
                    .zIndex(60)

                if !manager.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchResultsPanel
                        .frame(width: 294, height: min(330, geometry.size.height * 0.46))
                        .position(
                            x: shelfEdge == .right ? geometry.size.width - 157 : 157,
                            y: geometry.size.height - min(330, geometry.size.height * 0.46) / 2 - 50
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(55)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onExitCommand { manager.hide() }
        .onAppear {
            chooseFirstAvailableCollection()
            centeredItemID = manager.selectedItem?.id ?? displayedItems.first?.id
            synchronizeWheelPosition(animated: false)
            scrubPosition = musicManager.estimatedPlaybackPosition()
        }
        .onDisappear {
            wheelSettleTask?.cancel()
            wheelSettleTask = nil
        }
        .onChange(of: manager.searchFocusRequest) { _, _ in
            searchFocused = true
        }
        .onChange(of: showsDetail) { _, visible in
            manager.isContextPanelPresented = visible
        }
        .onChange(of: manager.isPresented) { _, presented in
            if !presented { showsDetail = false }
        }
        .onChange(of: collection) { _, _ in
            wheelSettleTask?.cancel()
            wheelDragOrigin = nil
            wheelIsInteracting = false
            showsDetail = false
            centeredItemID = displayedItems.first?.id
            wheelPosition = 0
            manager.select(displayedItems.first)
        }
        .onChange(of: displayedItems.map(\.id)) { _, ids in
            guard !ids.isEmpty else {
                centeredItemID = nil
                showsDetail = false
                return
            }
            if centeredItemID.map({ ids.contains($0) }) != true {
                centeredItemID = ids.first
            }
            if !wheelIsInteracting {
                synchronizeWheelPosition(animated: false)
            }
        }
        .onChange(of: centeredItemID) { _, identifier in
            guard let identifier,
                  let item = displayedItems.first(where: { $0.id == identifier }),
                  manager.selectedItem?.id != identifier,
                  !wheelIsInteracting
            else { return }
            if shelfEdge != .bottom {
                synchronizeWheelPosition(animated: true)
            }
            showsDetail = false
            manager.select(item)
        }
        .onChange(of: shelfEdge) { _, edge in
            guard edge != .bottom else { return }
            synchronizeWheelPosition(animated: false)
        }
        .onReceive(playbackClock) { _ in
            guard !isScrubbing else { return }
            scrubPosition = musicManager.estimatedPlaybackPosition()
        }
    }

    private func sideShelf(size: CGSize) -> some View {
        let carouselHeight = min(max(size.height - 230, 330), 610)
        let centerY = max(235, min(size.height * 0.55, size.height - 180))
        let isLeft = shelfEdge == .left
        let detailWidth = min(288, max(250, size.width - 132))
        let detailHalfWidth = detailWidth / 2
        let preferredDetailX = isLeft ? 274 : size.width - 274
        let detailX = min(
            max(preferredDetailX, detailHalfWidth + 10),
            size.width - detailHalfWidth - 10
        )

        return ZStack {
            sideCarousel(viewportHeight: carouselHeight)
                .frame(width: 124, height: carouselHeight)
                .position(x: isLeft ? 62 : size.width - 62, y: centerY)

            if let item = focusedShelfItem {
                selectionLabel(item)
                    .frame(width: 230)
                    .position(x: isLeft ? 208 : size.width - 208, y: centerY)
                    .zIndex(20)
            }

            if showsDetail {
                detailPanel
                    .frame(width: detailWidth, height: min(410, size.height - 210))
                    .position(x: detailX, y: centerY)
                    .transition(.move(edge: isLeft ? .leading : .trailing).combined(with: .opacity))
                    .zIndex(40)
            }
        }
    }

    private func bottomShelf(size: CGSize) -> some View {
        ZStack {
            bottomCarousel
                .frame(width: min(size.width - 42, 760), height: 118)
                .position(x: size.width / 2, y: size.height - 92)

            if let item = manager.selectedItem {
                selectionLabel(item)
                    .frame(width: 240)
                    .position(x: size.width / 2, y: size.height - 190)
                    .zIndex(20)
            }

            if showsDetail {
                detailPanel
                    .frame(width: 300, height: min(380, size.height - 150))
                    .position(x: size.width / 2, y: max(200, size.height * 0.46))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(40)
            }
        }
    }

    private func sideCarousel(viewportHeight: CGFloat) -> some View {
        Group {
            if displayedItems.isEmpty {
                emptyShelf
            } else {
                ZStack {
                    ForEach(Array(displayedItems.enumerated()), id: \.element.id) { index, item in
                        let relativePosition = CGFloat(index) - wheelPosition
                        if abs(relativePosition) < 2.72 {
                            GramolaWheelCover(
                                item: item,
                                relativePosition: relativePosition,
                                isSelected: centeredItemID == item.id,
                                edge: shelfEdge,
                                viewportHeight: viewportHeight,
                                action: { selectWheelItem(item, at: index) }
                            )
                            .zIndex(wheelDepth(for: relativePosition))
                        }
                    }
                }
                .contentShape(Rectangle())
                .background {
                    GramolaWheelScrollMonitor { delta in
                        handleWheelScroll(delta)
                    }
                }
                .simultaneousGesture(wheelDragGesture)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white, location: 0.035),
                            .init(color: .white, location: 0.965),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
    }

    private var bottomCarousel: some View {
        Group {
            if displayedItems.isEmpty {
                emptyShelf
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: -10) {
                        Color.clear.frame(width: 250)
                        ForEach(displayedItems) { item in
                            Button { activate(item) } label: {
                                MusicShelfArtwork(item: item)
                                    .frame(width: centeredItemID == item.id ? 94 : 76,
                                           height: centeredItemID == item.id ? 94 : 76)
                                    .clipShape(GramolaCoverShape(isCircle: item.kind == .artist))
                                    .overlay {
                                        GramolaCoverShape(isCircle: item.kind == .artist)
                                            .strokeBorder(.white.opacity(centeredItemID == item.id ? 0.72 : 0.16), lineWidth: 1)
                                    }
                                    .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                            }
                            .buttonStyle(.plain)
                            .id(item.id)
                            .zIndex(centeredItemID == item.id ? 10 : 1)
                        }
                        Color.clear.frame(width: 250)
                    }
                    .scrollTargetLayout()
                }
                .scrollPosition(id: $centeredItemID, anchor: .center)
                .scrollTargetBehavior(.viewAligned)
                .simultaneousGesture(collectionSwipe)
            }
        }
    }

    private var collectionSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.25,
                      abs(value.translation.width) > 46
                else { return }
                changeCollection(by: value.translation.width < 0 ? 1 : -1)
            }
    }

    private var wheelDragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard shelfEdge != .bottom, displayedItems.count > 1 else { return }
                if wheelDragOrigin == nil {
                    guard abs(value.translation.height) > abs(value.translation.width) * 0.72 else { return }
                }
                wheelSettleTask?.cancel()
                wheelSettleTask = nil
                if wheelDragOrigin == nil {
                    wheelDragOrigin = wheelPosition
                    wheelIsInteracting = true
                    showsDetail = false
                }
                let origin = wheelDragOrigin ?? wheelPosition
                updateWheelPosition(origin - (value.translation.height / 67))
            }
            .onEnded { value in
                guard shelfEdge != .bottom, !displayedItems.isEmpty else { return }
                if abs(value.translation.width) > abs(value.translation.height) * 1.25,
                   abs(value.translation.width) > 46 {
                    wheelSettleTask?.cancel()
                    wheelDragOrigin = nil
                    wheelIsInteracting = false
                    changeCollection(by: value.translation.width < 0 ? 1 : -1)
                    return
                }
                guard wheelDragOrigin != nil else { return }
                let origin = wheelDragOrigin ?? wheelPosition
                let projected = origin - (value.predictedEndTranslation.height / 67)
                let limitedProjection = min(max(projected, wheelPosition - 4), wheelPosition + 4)
                wheelDragOrigin = nil
                snapWheel(toward: limitedProjection)
            }
    }

    private func handleWheelScroll(_ delta: CGFloat) {
        guard shelfEdge != .bottom, displayedItems.count > 1, abs(delta) > 0.01 else { return }
        wheelSettleTask?.cancel()
        wheelIsInteracting = true
        showsDetail = false

        let limitedDelta = min(max(delta, -52), 52)
        updateWheelPosition(wheelPosition - limitedDelta / 64)

        wheelSettleTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(115))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            snapWheel(toward: wheelPosition)
        }
    }

    private func updateWheelPosition(_ proposedPosition: CGFloat) {
        guard !displayedItems.isEmpty else { return }
        let upperBound = CGFloat(displayedItems.count - 1)
        let bounded: CGFloat
        if proposedPosition < 0 {
            bounded = -min(0.42, abs(proposedPosition) * 0.2)
        } else if proposedPosition > upperBound {
            bounded = upperBound + min(0.42, (proposedPosition - upperBound) * 0.2)
        } else {
            bounded = proposedPosition
        }
        wheelPosition = bounded
        updateCenteredWheelItem()
    }

    private func updateCenteredWheelItem() {
        guard !displayedItems.isEmpty else { return }
        let index = min(max(Int(wheelPosition.rounded()), 0), displayedItems.count - 1)
        let item = displayedItems[index]
        guard centeredItemID != item.id else { return }
        centeredItemID = item.id
        if lastWheelFeedbackIndex != index {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            lastWheelFeedbackIndex = index
        }
    }

    private func snapWheel(toward proposedPosition: CGFloat) {
        wheelSettleTask?.cancel()
        wheelSettleTask = nil
        guard !displayedItems.isEmpty else {
            wheelIsInteracting = false
            return
        }

        let targetIndex = min(max(Int(proposedPosition.rounded()), 0), displayedItems.count - 1)
        let target = displayedItems[targetIndex]
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86, blendDuration: 0.08)) {
            wheelPosition = CGFloat(targetIndex)
            centeredItemID = target.id
        }
        wheelIsInteracting = false
        showsDetail = false
        if manager.selectedItem?.id != target.id {
            manager.select(target)
        }
    }

    private func selectWheelItem(_ item: MusicShelfItem, at index: Int) {
        if centeredItemID == item.id, abs(wheelPosition - CGFloat(index)) < 0.08 {
            withAnimation(.snappy(duration: 0.2)) { showsDetail.toggle() }
            return
        }
        wheelIsInteracting = true
        withAnimation(.spring(response: 0.4, dampingFraction: 0.84, blendDuration: 0.08)) {
            wheelPosition = CGFloat(index)
            centeredItemID = item.id
            showsDetail = false
        }
        wheelIsInteracting = false
        manager.select(item)
    }

    private func synchronizeWheelPosition(animated: Bool) {
        guard !displayedItems.isEmpty else {
            wheelPosition = 0
            return
        }
        let index = centeredItemID
            .flatMap { identifier in displayedItems.firstIndex(where: { $0.id == identifier }) }
            ?? 0
        if animated {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                wheelPosition = CGFloat(index)
            }
        } else {
            wheelPosition = CGFloat(index)
        }
    }

    private func wheelDepth(for relativePosition: CGFloat) -> Double {
        let angle = min(abs(relativePosition) * 0.56, 1.52)
        return Double(max(0, cos(angle)) * 100)
    }

    private var emptyShelf: some View {
        VStack(spacing: 7) {
            Image(systemName: collection.symbol)
                .font(.system(size: 17, weight: .medium))
            Text(collection.name)
                .font(.system(size: 10, weight: .semibold))
            Text("No items")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .gramolaGlass(cornerRadius: 14)
    }

    private func selectionLabel(_ item: MusicShelfItem) -> some View {
        HStack(spacing: 8) {
            if shelfEdge != .right { selectionBadge(item) }

            Button {
                withAnimation(.snappy(duration: 0.22)) { showsDetail.toggle() }
            } label: {
                HStack(spacing: 9) {
                    VStack(alignment: shelfEdge == .right ? .trailing : .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                        Text(item.subtitle)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                            .overlay(alignment: .leading) {
                                Circle()
                                    .fill(item.provider.tint)
                                    .frame(width: 4, height: 4)
                                    .offset(x: -8)
                            }
                    }
                    Image(systemName: showsDetail ? "chevron.left" : "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .rotationEffect(.degrees(shelfEdge == .right ? 180 : 0))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.horizontal, 13)
                .frame(height: 46)
                .frame(maxWidth: .infinity, alignment: shelfEdge == .right ? .trailing : .leading)
                .gramolaGlass(cornerRadius: 15)
            }
            .buttonStyle(.plain)

            if shelfEdge == .right { selectionBadge(item) }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
    }

    private func selectionBadge(_ item: MusicShelfItem) -> some View {
        Group {
            if collection == .history, let date = item.lastPlayed {
                Text(Self.shortRelativeDate(date))
                    .font(.system(size: 8.5, weight: .semibold))
                    .padding(.horizontal, 8)
                    .frame(height: 32)
                    .gramolaGlass(cornerRadius: 11)
            } else {
                Image(systemName: collection.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 34, height: 34)
                    .gramolaGlass(cornerRadius: 17)
            }
        }
        .foregroundStyle(.white.opacity(0.88))
    }

    private var detailPanel: some View {
        Group {
            if let item = manager.selectedItem {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 10) {
                        MusicShelfArtwork(item: item)
                            .frame(width: 43, height: 43)
                            .clipShape(GramolaCoverShape(isCircle: item.kind == .artist))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(2)
                            Text(item.subtitle)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)
                        Button {
                            withAnimation(.snappy(duration: 0.18)) { showsDetail = false }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .frame(width: 22, height: 22)
                                .background(.white.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    detailActions(item)
                    Divider().opacity(0.35)

                    if manager.isLoadingTracks {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if item.kind == .artist {
                        artistAlbums
                    } else {
                        trackList
                    }

                    if let status = manager.statusMessage {
                        Text(status)
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(12)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gramolaGlass(cornerRadius: 14, opacity: 0.4)
        .shadow(color: .black.opacity(0.2), radius: 9, y: 4)
    }

    private func detailActions(_ item: MusicShelfItem) -> some View {
        HStack(spacing: 5) {
            if item.kind != .artist {
                GramolaActionButton(title: "Play", symbol: "play.fill") {
                    manager.playCollection(item)
                }
                GramolaActionButton(title: "Shuffle", symbol: "shuffle") {
                    manager.playCollection(item, shuffled: true)
                }
            }
            GramolaActionButton(
                title: manager.isPinned(item) ? "Unpin" : "Pin",
                symbol: manager.isPinned(item) ? "pin.slash.fill" : "pin.fill"
            ) {
                manager.togglePin(item)
            }
        }
    }

    private var trackList: some View {
        Group {
            if manager.tracks.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "music.note.list")
                    Text("No tracks available")
                        .font(.system(size: 9.5, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(manager.tracks.enumerated()), id: \.element.id) { index, track in
                            Button { manager.play(track) } label: {
                                HStack(spacing: 7) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 8.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 17, alignment: .trailing)
                                    Text(track.title)
                                        .font(.system(size: 9.5, weight: .medium))
                                        .lineLimit(1)
                                    Spacer(minLength: 3)
                                    if track.duration > 0 {
                                        Text(Self.duration(track.duration))
                                            .font(.system(size: 8, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 5)
                                .frame(height: 24)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(GramolaRowButtonStyle())
                        }
                    }
                }
            }
        }
    }

    private var artistAlbums: some View {
        Group {
            if manager.relatedItems.isEmpty {
                Text("No albums available")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 10) {
                        ForEach(manager.relatedItems) { album in
                            Button {
                                manager.select(album)
                                showsDetail = true
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    MusicShelfArtwork(item: album)
                                        .aspectRatio(1, contentMode: .fill)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    Text(album.title)
                                        .font(.system(size: 8.5, weight: .medium))
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var nowPlayingCluster: some View {
        VStack(alignment: shelfEdge == .right ? .trailing : .leading, spacing: 6) {
            HStack(spacing: 9) {
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 43, height: 43)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(musicManager.songTitle)
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)
                    Text(musicManager.artistName)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Button { manager.previousTrack() } label: { Image(systemName: "backward.fill") }
                    Button { manager.togglePlayback() } label: {
                        Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    Button { manager.nextTrack() } label: { Image(systemName: "forward.fill") }
                }
                .font(.system(size: 10, weight: .semibold))
            }
            .padding(7)
            .frame(height: 57)
            .gramolaGlass(cornerRadius: 13)

            HStack(spacing: 3) {
                ForEach(MusicShelfCollection.allCases) { candidate in
                    Button {
                        withAnimation(.snappy(duration: 0.22)) { collection = candidate }
                    } label: {
                        Image(systemName: candidate.symbol)
                            .font(.system(size: 9.5, weight: .semibold))
                            .frame(width: 26, height: 24)
                            .background(collection == candidate ? .white.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .help(candidate.name)
                }

                Divider().frame(height: 14).opacity(0.35)

                Button { searchFocused = true } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 25, height: 24)
                }
                .buttonStyle(.plain)

                Button { manager.hide() } label: {
                    Image(systemName: "xmark")
                        .frame(width: 25, height: 24)
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white.opacity(0.86))
            .padding(.horizontal, 5)
            .frame(height: 34)
            .gramolaGlass(cornerRadius: 11)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Search music", text: $manager.query)
                .focused($searchFocused)
                .textFieldStyle(.plain)
                .font(.system(size: 9.5, weight: .medium))
                .onChange(of: manager.query) { _, value in manager.updateSearchQuery(value) }
                .onSubmit { submitSearch() }
            if manager.isSearching {
                ProgressView().controlSize(.mini)
            } else if !manager.query.isEmpty {
                Button { manager.updateSearchQuery("") } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .gramolaGlass(cornerRadius: 9, opacity: 0.3)
        .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
    }

    private var searchResultsPanel: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Search results")
                    .font(.system(size: 9.5, weight: .semibold))
                Spacer()
                Text("Return to open")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 3)

            if manager.searchResults.isEmpty, !manager.isSearching {
                Text(manager.statusMessage ?? "No music found")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(manager.searchResults) { item in
                            Button { openSearchResult(item) } label: {
                                HStack(spacing: 8) {
                                    MusicShelfArtwork(item: item)
                                        .frame(width: 31, height: 31)
                                        .clipShape(GramolaCoverShape(isCircle: item.kind == .artist))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.title)
                                            .font(.system(size: 9.5, weight: .semibold))
                                            .lineLimit(1)
                                        Text(item.subtitle)
                                            .font(.system(size: 8.5))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: symbol(for: item.kind))
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 5)
                                .frame(height: 39)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(GramolaRowButtonStyle())
                        }
                    }
                }
            }
        }
        .padding(9)
        .foregroundStyle(.white)
        .gramolaGlass(cornerRadius: 13, opacity: 0.42)
        .shadow(color: .black.opacity(0.2), radius: 9, y: 4)
    }

    private func activate(_ item: MusicShelfItem) {
        if centeredItemID == item.id {
            withAnimation(.snappy(duration: 0.2)) { showsDetail.toggle() }
        } else {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                centeredItemID = item.id
                showsDetail = false
            }
        }
    }

    private func openSearchResult(_ item: MusicShelfItem) {
        manager.select(item)
        showsDetail = true
        searchFocused = false
    }

    private func submitSearch() {
        guard let first = manager.searchResults.first else { return }
        openSearchResult(first)
        manager.playCollection(first)
    }

    private func changeCollection(by delta: Int) {
        let all = MusicShelfCollection.allCases
        guard let index = all.firstIndex(of: collection) else { return }
        let target = min(max(index + delta, 0), all.count - 1)
        guard target != index else { return }
        withAnimation(.snappy(duration: 0.25)) { collection = all[target] }
    }

    private func chooseFirstAvailableCollection() {
        if manager.items(for: collection).isEmpty,
           let first = MusicShelfCollection.allCases.first(where: { !manager.items(for: $0).isEmpty }) {
            collection = first
        }
    }

    private func collection(for kind: MusicShelfItemKind) -> MusicShelfCollection {
        switch kind {
        case .album: return .albums
        case .artist: return .artists
        case .playlist: return .playlists
        case .track: return .history
        }
    }

    private func symbol(for kind: MusicShelfItemKind) -> String {
        switch kind {
        case .album: return "square.stack"
        case .artist: return "person.crop.circle"
        case .playlist: return "music.note.list"
        case .track: return "music.note"
        }
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    private static func shortRelativeDate(_ date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 3_600 { return String(localized: "Now") }
        if seconds < 86_400 { return String(localized: "\(Int(seconds / 3_600))h ago") }
        return String(localized: "\(Int(seconds / 86_400))d ago")
    }
}

private struct GramolaWheelCover: View {
    let item: MusicShelfItem
    let relativePosition: CGFloat
    let isSelected: Bool
    let edge: MusicShelfEdge
    let viewportHeight: CGFloat
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        GeometryReader { geometry in
            let angle = min(max(relativePosition * 0.56, -1.52), 1.52)
            let depth = max(0, cos(angle))
            let prominence = pow(depth, 3.4)
            let radius = min(max(viewportHeight * 0.29, 150), 178)
            let size = 38 + prominence * 65 + (isSelected ? 2 : 0)
            let centerX = edge == .right
                ? geometry.size.width - size / 2 - 2
                : size / 2 + 2
            let centerY = geometry.size.height / 2 + sin(angle) * radius
            let alpha = 0.14 + pow(depth, 1.55) * 0.86
            let coverShape = GramolaCoverShape(isCircle: item.kind == .artist)

            Button(action: action) {
                ZStack {
                    coverShape
                        .fill(.black.opacity(0.9))

                    MusicShelfArtwork(item: item)
                        .clipShape(coverShape)
                }
                    .frame(width: size, height: size)
                    .clipShape(coverShape)
                    .overlay {
                        coverShape
                            .strokeBorder(
                                isSelected
                                    ? .white.opacity(0.9)
                                    : .white.opacity(0.08 + prominence * 0.18),
                                lineWidth: isSelected ? 1.7 : 0.75
                            )
                    }
                    .contentShape(coverShape)
                    .shadow(
                        color: .black.opacity(isSelected ? 0.28 : 0.07 * prominence),
                        radius: isSelected ? 11 : 2,
                        x: isSelected ? (edge == .right ? -2 : 2) : 0,
                        y: isSelected ? 4 : 1
                    )
            }
            .buttonStyle(.plain)
            .scaleEffect(
                isHovering ? 1.035 : 1,
                anchor: edge == .right ? .trailing : .leading
            )
            .opacity(alpha)
            .blur(radius: depth < 0.12 ? 0.65 : 0)
            .position(x: centerX, y: centerY)
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isSelected)
            .onHover { isHovering = $0 }
        }
        .allowsHitTesting(abs(relativePosition) < 2.65)
    }
}

private struct GramolaWheelScrollMonitor: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> WheelEventView {
        let view = WheelEventView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: WheelEventView, context: Context) {
        nsView.onScroll = onScroll
    }

    static func dismantleNSView(_ nsView: WheelEventView, coordinator: ()) {
        nsView.removeMonitor()
    }

    final class WheelEventView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        private var eventMonitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                removeMonitor()
            } else {
                installMonitorIfNeeded()
            }
        }

        func removeMonitor() {
            guard let eventMonitor else { return }
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }

        private func installMonitorIfNeeded() {
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self,
                      let window = self.window,
                      event.window === window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil))
                else { return event }

                var delta = event.scrollingDeltaY
                if event.isDirectionInvertedFromDevice { delta *= -1 }
                if !event.hasPreciseScrollingDeltas { delta *= 18 }
                self.onScroll?(delta)
                return nil
            }
        }

        deinit {
            removeMonitor()
        }
    }
}

private struct GramolaCoverShape: InsettableShape {
    let isCircle: Bool
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: insetAmount, dy: insetAmount)
        if isCircle { return Path(ellipseIn: inset) }
        return Path(roundedRect: inset, cornerRadius: 8)
    }

    func inset(by amount: CGFloat) -> GramolaCoverShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

private struct GramolaActionButton: View {
    let title: LocalizedStringKey
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 8.5, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 25)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}

private struct GramolaRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? .white.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

private extension View {
    func gramolaGlass(cornerRadius: CGFloat, opacity: Double = 0.32) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(.black.opacity(opacity), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .white.opacity(0.055)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            }
    }
}

private struct MusicShelfArtwork: View {
    let item: MusicShelfItem

    var body: some View {
        Group {
            if let path = item.artworkPath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let url = item.artworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: placeholder
                    case .empty: ZStack { placeholder; ProgressView().controlSize(.small) }
                    @unknown default: placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: item.kind == .artist
                    ? [.indigo.opacity(0.82), .purple.opacity(0.52), .black.opacity(0.86)]
                    : [item.provider.tint.opacity(0.62), .black.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if item.kind == .artist {
                Text(artistInitials)
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private var artistInitials: String {
        let words = item.title.split(whereSeparator: { $0.isWhitespace })
        return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

private struct MusicShelfTrackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? Color.white.opacity(0.12) : Color.white.opacity(0.001),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
