//
//  MinimalisticMusicPlayerView.swift
//  DynamicIsland
//
//  Created for minimalistic UI mode - Open state music player
//

import SwiftUI
import Defaults

#if canImport(AppKit)
import AppKit
#endif

struct MinimalisticMusicPlayerView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    let albumArtNamespace: Namespace.ID
    @Default(.showMediaOutputControl) var showMediaOutputControl
    @ObservedObject private var reminderManager = ReminderLiveActivityManager.shared
    @Default(.enableReminderLiveActivity) private var enableReminderLiveActivity

    var body: some View {
        VStack(spacing: 0) {
            // Header area with album art (matching DynamicIslandHeader height of 24pt)
            GeometryReader { headerGeo in
                let albumArtWidth: CGFloat = 50
                let spacing: CGFloat = 10
                let visualizerWidth: CGFloat = useMusicVisualizer ? 24 : 0
                let textWidth = max(0, headerGeo.size.width - albumArtWidth - spacing - (useMusicVisualizer ? (visualizerWidth + spacing) : 0))
                HStack(alignment: .center, spacing: spacing) {
                    MinimalisticAlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace)
                        .frame(width: albumArtWidth, height: albumArtWidth)

                    VStack(alignment: .leading, spacing: 1) {
                        if !musicManager.songTitle.isEmpty {
                            MarqueeText(
                                $musicManager.songTitle,
                                font: .system(size: 12, weight: .semibold),
                                nsFont: .subheadline,
                                textColor: .white,
                                frameWidth: textWidth
                            )
                        }

                        Text(musicManager.artistName)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray)
                            .lineLimit(1)
                    }
                    .frame(width: textWidth, alignment: .leading)

                    if useMusicVisualizer {
                        visualizer
                            .frame(width: visualizerWidth)
                    }
                }
            }
            .frame(height: 50)
            
            // Compact progress bar
            progressBar
                .padding(.top, 6)
            
            // Compact playback controls
            playbackControls
                .padding(.top, 4)

            if shouldShowReminderList {
                MinimalisticReminderEventListView(reminders: reminderEntries, currentDate: reminderManager.currentDate)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, -15)
    .padding(.bottom, shouldShowReminderList ? ReminderLiveActivityManager.listBottomPadding : ReminderLiveActivityManager.baselineMinimalisticBottomPadding)
        .frame(maxWidth: .infinity)
    }

    private var reminderEntries: [ReminderLiveActivityManager.ReminderEntry] {
        reminderManager.activeWindowReminders
    }

    private var shouldShowReminderList: Bool {
        enableReminderLiveActivity && !reminderEntries.isEmpty
    }
    

private struct MinimalisticReminderEventListView: View {
    let reminders: [ReminderLiveActivityManager.ReminderEntry]
    let currentDate: Date

    private let textFont = Font.system(size: 13, weight: .semibold)
    private let separatorSpacing: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: ReminderLiveActivityManager.listRowSpacing) {
            ForEach(reminders) { entry in
                MinimalisticReminderEventRow(entry: entry, now: currentDate, textFont: textFont, separatorSpacing: separatorSpacing)
            }
        }
        .padding(.top, ReminderLiveActivityManager.listTopPadding)
    }
}

private struct MinimalisticReminderEventRow: View {
    let entry: ReminderLiveActivityManager.ReminderEntry
    let now: Date
    let textFont: Font
    let separatorSpacing: CGFloat

    @State private var isDetailsPresented = false

    private let ringDiameter: CGFloat = 20
    private let ringLineWidth: CGFloat = 3

    var body: some View {
        HStack(spacing: separatorSpacing) {
            RoundedRectangle(cornerRadius: 3)
                .fill(eventColor)
                .frame(width: 8, height: ringDiameter)

            Text(entry.event.title)
                .font(textFont)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 12)

            HStack(spacing: separatorSpacing) {
                if let url = linkURL {
                    Button {
                        copyToClipboard(url: url)
                    } label: {
                        Image(systemName: "link")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help("Copy event link")
                }

                if hasDetails {
                    Button {
                        isDetailsPresented.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isDetailsPresented, arrowEdge: .top) {
                        MinimalisticReminderDetailsView(entry: entry, linkURL: linkURL)
                    }
                }

                ReminderProgressRing(progress: progress, accent: accentColor, diameter: ringDiameter, lineWidth: ringLineWidth)
            }
        }
        .frame(height: ReminderLiveActivityManager.listRowHeight)
    }

    private var progress: Double {
        guard entry.leadTime > 0 else { return 1 }
        let remaining = max(entry.event.start.timeIntervalSince(now), 0)
        let elapsed = entry.leadTime - remaining
        let ratio = elapsed / entry.leadTime
        return min(max(ratio, 0), 1)
    }

    private var accentColor: Color {
        if isCritical {
            return .red
        }
        return eventColor
    }

    private var eventColor: Color {
        Color(nsColor: entry.event.calendar.color).ensureMinimumBrightness(factor: 0.7)
    }

    private var isCritical: Bool {
        let window = TimeInterval(Defaults[.reminderSneakPeekDuration])
        guard window > 0 else { return false }
        let remaining = entry.event.start.timeIntervalSince(now)
        return remaining > 0 && remaining <= window
    }

    private var hasDetails: Bool {
        let location = entry.event.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let notes = entry.event.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !location.isEmpty || !notes.isEmpty
    }

    private var linkURL: URL? {
        entry.event.url ?? entry.event.calendarAppURL()
    }

    private func copyToClipboard(url: URL) {
#if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
#endif
    }
}

private struct ReminderProgressRing: View {
    let progress: Double
    let accent: Color
    let diameter: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
        .animation(.smooth(duration: 0.25), value: progress)
    }
}

private struct MinimalisticReminderDetailsView: View {
    let entry: ReminderLiveActivityManager.ReminderEntry
    let linkURL: URL?

    private let detailFont = Font.system(size: 13, weight: .regular)
    private let smallLabelFont = Font.system(size: 12, weight: .semibold)
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entry.event.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 6) {
                if let timeRange = timeRangeText {
                    detailRow(icon: "clock", label: "Time", value: timeRange)
                }

                if let location = entry.event.location, !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    detailRow(icon: "mappin.and.ellipse", label: "Location", value: location)
                }

                if let notes = entry.event.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    detailRow(icon: "note.text", label: "Notes", value: notes)
                }
            }

            if let url = linkURL {
                Button {
                    open(url: url)
                } label: {
                    Label("Open in Calendar", systemImage: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.link)
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding(16)
        .frame(minWidth: 220)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(smallLabelFont)
                .foregroundStyle(Color.white.opacity(0.8))
            Text(value)
                .font(detailFont)
                .foregroundStyle(Color.white)
        }
    }

    private var timeRangeText: String? {
        let startText = Self.timeFormatter.string(from: entry.event.start)
        let endText = Self.timeFormatter.string(from: entry.event.end)
        return startText == endText ? startText : "\(startText) – \(endText)"
    }

    private func open(url: URL) {
#if canImport(AppKit)
        NSWorkspace.shared.open(url)
#endif
    }
}
    // MARK: - Visualizer
    
    @Default(.useMusicVisualizer) var useMusicVisualizer
    
    private var visualizer: some View {
        Rectangle()
            .fill(Defaults[.coloredSpectrogram] ? Color(nsColor: MusicManager.shared.avgColor).gradient : Color.gray.gradient)
            .mask {
                AudioSpectrumView(isPlaying: .constant(MusicManager.shared.isPlaying))
                    .frame(width: 20, height: 16)
            }
            .frame(width: 20, height: 16)
            .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
    }
    
    // MARK: - Progress Bar (Full Width)
    
    @ObservedObject var musicManager = MusicManager.shared
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    
    private var progressBar: some View {
        TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.1 : nil)) { timeline in
            if musicManager.isLiveStream {
                HStack(spacing: 8) {
                    Spacer()
                        .frame(width: 42)
                    LiveStreamProgressIndicator(tint: sliderColor)
                        .frame(maxWidth: .infinity, minHeight: 6, maxHeight: 6)
                    Spacer()
                        .frame(width: 48)
                }
                .allowsHitTesting(false)
            } else {
                let currentElapsed = currentSliderValue(timeline.date)

                HStack(spacing: 8) {
                    Text(formatTime(dragging ? sliderValue : currentElapsed))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 42, alignment: .leading)

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(sliderColor)
                                .frame(width: max(0, geometry.size.width * (currentSliderValue(timeline.date) / max(musicManager.songDuration, 1))), height: 6)
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    dragging = true
                                    let newValue = min(max(0, Double(value.location.x / geometry.size.width) * musicManager.songDuration), musicManager.songDuration)
                                    sliderValue = newValue
                                    lastDragged = Date()
                                }
                                .onEnded { _ in
                                    musicManager.seek(to: sliderValue)
                                    dragging = false
                                }
                        )
                    }
                    .frame(height: 6)

                    Text("-\(formatTime(musicManager.songDuration - (dragging ? sliderValue : currentElapsed)))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 48, alignment: .trailing)
                }
            }
        }
        .onAppear {
            sliderValue = musicManager.elapsedTime
        }
    }
    
    private func currentSliderValue(_ date: Date) -> Double {
        if dragging {
            return sliderValue
        }
        
        // Update slider value based on playback
        if musicManager.isPlaying {
            let timeSinceLastUpdate = date.timeIntervalSince(musicManager.timestampDate)
            let estimatedElapsed = musicManager.elapsedTime + (timeSinceLastUpdate * musicManager.playbackRate)
            return min(estimatedElapsed, musicManager.songDuration)
        }
        
        return musicManager.elapsedTime
    }
    
    private var sliderColor: Color {
        switch Defaults[.sliderColor] {
        case .white:
            return .white
        case .albumArt:
            return Color(nsColor: musicManager.avgColor)
        case .accent:
            return .accentColor
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Playback Controls (Larger)
    
    private var playbackControls: some View {
        HStack(spacing: 20) {
            if Defaults[.showShuffleAndRepeat] {
                controlButton(icon: "shuffle", isActive: musicManager.isShuffled) {
                    Task { await musicManager.toggleShuffle() }
                }
            }
            
            controlButton(icon: "backward.fill", size: 18) {
                Task { await musicManager.previousTrack() }
            }
            
            playPauseButton
            
            controlButton(icon: "forward.fill", size: 18) {
                Task { await musicManager.nextTrack() }
            }
            
            if Defaults[.showShuffleAndRepeat] {
                if showMediaOutputControl {
                    MinimalisticMediaOutputButton()
                } else {
                    controlButton(icon: repeatIcon, isActive: musicManager.repeatMode != .off) {
                        Task { await musicManager.toggleRepeat() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
    }
    
    private var playPauseButton: some View {
        MinimalisticSquircircleButton(
            icon: musicManager.isPlaying ? "pause.fill" : "play.fill",
            fontSize: 24,
            fontWeight: .semibold,
            frameSize: CGSize(width: 54, height: 54),
            cornerRadius: 20,
            foregroundColor: .white,
            action: {
                Task { await musicManager.togglePlay() }
            }
        )
    }
    
    private func controlButton(icon: String, size: CGFloat = 18, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        MinimalisticSquircircleButton(
            icon: icon,
            fontSize: size,
            fontWeight: .medium,
            frameSize: CGSize(width: 40, height: 40),
            cornerRadius: 16,
            foregroundColor: isActive ? .red : .white.opacity(0.85),
            action: action
        )
    }
    private struct MinimalisticMediaOutputButton: View {
        @ObservedObject private var routeManager = AudioRouteManager.shared
        @StateObject private var volumeModel = MediaOutputVolumeViewModel()
        @EnvironmentObject private var vm: DynamicIslandViewModel
        @State private var isPopoverPresented = false
        @State private var isHoveringPopover = false

        var body: some View {
            MinimalisticSquircircleButton(
                icon: routeManager.activeDevice?.iconName ?? "speaker.wave.2",
                fontSize: 18,
                fontWeight: .medium,
                frameSize: CGSize(width: 40, height: 40),
                cornerRadius: 16,
                foregroundColor: .white.opacity(0.85)
            ) {
                isPopoverPresented.toggle()
                if isPopoverPresented {
                    routeManager.refreshDevices()
                }
            }
            .accessibilityLabel("Media output")
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                MediaOutputSelectorPopover(
                    routeManager: routeManager,
                    volumeModel: volumeModel,
                    onHoverChanged: { hovering in
                        isHoveringPopover = hovering
                        updateActivity()
                    }
                ) {
                    isPopoverPresented = false
                    isHoveringPopover = false
                    updateActivity()
                }
            }
            .onChange(of: isPopoverPresented) { _, presented in
                if !presented {
                    isHoveringPopover = false
                }
                updateActivity()
            }
            .onAppear {
                routeManager.refreshDevices()
            }
            .onDisappear {
                vm.isMediaOutputPopoverActive = false
            }
        }

        private func updateActivity() {
            vm.isMediaOutputPopoverActive = isPopoverPresented && isHoveringPopover
        }
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

// MARK: - Minimalistic Album Art

struct MinimalisticAlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var vm: DynamicIslandViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if Defaults[.lightingEffect] {
                albumArtBackground
            }
            albumArtButton
        }
    }
    
    private var albumArtBackground: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background(
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            )
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(x: 1.3, y: 1.4)
            .rotationEffect(.degrees(92))
            .blur(radius: 35)
            .opacity(min(0.6, 1 - max(musicManager.albumArt.getBrightness(), 0.3)))
    }
    
    private var albumArtButton: some View {
        Button {
            musicManager.openMusicApp()
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .background(
                    Image(nsImage: musicManager.albumArt)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                )
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .albumArtFlip(angle: musicManager.flipAngle)
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(musicManager.isPlaying ? 1 : 0.4)
        .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
    }
}

// MARK: - Hover-highlighted control button

private struct MinimalisticSquircircleButton: View {
    let icon: String
    let fontSize: CGFloat
    let fontWeight: Font.Weight
    let frameSize: CGSize
    let cornerRadius: CGFloat
    let foregroundColor: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: fontSize, weight: fontWeight))
                .foregroundColor(foregroundColor)
                .frame(width: frameSize.width, height: frameSize.height)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(isHovering ? Color.white.opacity(0.18) : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) {
                isHovering = hovering
            }
        }
    }
}
