//
//  LockScreenMusicPanel.swift
//  DynamicIsland
//
//  Created for lock screen music panel with liquid glass effect
//

import SwiftUI
import Defaults

struct LockScreenMusicPanel: View {
    static let defaultSize = CGSize(width: 420, height: 180)

    @ObservedObject var musicManager = MusicManager.shared
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    @State private var isActive = true
    @Default(.lockScreenGlassStyle) var lockScreenGlassStyle
    
    private let cornerRadius: CGFloat = 28
    private var panelSize: CGSize { Self.defaultSize }

    private var usesLiquidGlass: Bool {
        if #available(macOS 26.0, *) {
            return lockScreenGlassStyle == .liquid
        }
        return false
    }
    
    var body: some View {
        if isActive {
            panelContent
                .onDisappear {
                    isActive = false
                }
        } else {
            Color.clear
                .frame(width: panelSize.width, height: panelSize.height)
        }
    }
    
    private var panelContent: some View {
        VStack(spacing: 12) {
            // Header area with album art
            HStack(alignment: .center, spacing: 16) {
                // Album art
                Button {
                    musicManager.openMusicApp()
                } label: {
                    Image(nsImage: musicManager.albumArt)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(PlainButtonStyle())
                .opacity(musicManager.isPlaying ? 1 : 0.4)
                .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
                
                // Song info
                VStack(alignment: .leading, spacing: 1) {
                    Text(musicManager.songTitle.isEmpty ? "No Music Playing" : musicManager.songTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(musicManager.artistName.isEmpty ? "Unknown Artist" : musicManager.artistName)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Visualizer
                if Defaults[.useMusicVisualizer] {
                    Rectangle()
                        .fill(Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor).gradient : Color.gray.gradient)
                        .mask {
                            AudioSpectrumView(isPlaying: .constant(musicManager.isPlaying))
                                .frame(width: 20, height: 16)
                        }
                        .frame(width: 20, height: 16)
                }
            }
            .frame(height: 60)
            
            // Progress bar
            progressBar
                .padding(.top, 4)
            
            // Playback controls
            playbackControls
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: panelSize.width, height: panelSize.height)
        .background(panelBackground)
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(0.35), lineWidth: 1.4)
        }
        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
        .onAppear {
            sliderValue = musicManager.elapsedTime
            isActive = true
            logPanelAppearance()
        }
    }
    
    // MARK: - Progress Bar
    
    private var progressBar: some View {
        TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.1 : nil)) { timeline in
            let currentElapsed = currentSliderValue(timeline.date)
            
            HStack(spacing: 8) {
                // Elapsed time
                Text(formatTime(dragging ? sliderValue : currentElapsed))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 42, alignment: .leading)
                
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 6)
                        
                        // Filled portion
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
                
                // Time remaining
                Text("-\(formatTime(musicManager.songDuration - (dragging ? sliderValue : currentElapsed)))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 48, alignment: .trailing)
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
    
    // MARK: - Playback Controls
    
    private var playbackControls: some View {
        HStack(spacing: 20) {
            // Always show shuffle on lock screen
            controlButton(icon: "shuffle", isActive: musicManager.isShuffled) {
                Task { await musicManager.toggleShuffle() }
            }
            
            controlButton(icon: "backward.fill", size: 18) {
                Task { await musicManager.previousTrack() }
            }
            
            playPauseButton
            
            controlButton(icon: "forward.fill", size: 18) {
                Task { await musicManager.nextTrack() }
            }
            
            // Always show repeat on lock screen
            controlButton(icon: repeatIcon, isActive: musicManager.repeatMode != .off) {
                Task { await musicManager.toggleRepeat() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
    }
    
    private var playPauseButton: some View {
        Button(action: {
            Task { await musicManager.togglePlay() }
        }) {
            Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func controlButton(icon: String, size: CGFloat = 18, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(isActive ? .red : .white.opacity(0.8))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    @ViewBuilder
    private var panelBackground: some View {
        if usesLiquidGlass {
            liquidPanelBackground
        } else {
            frostedPanelBackground
        }
    }

    @ViewBuilder
    private var liquidPanelBackground: some View {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .glassEffect(
                    .regular
                        .tint(Color.white.opacity(0.12))
                        .interactive(),
                    in: .rect(cornerRadius: cornerRadius)
                )
        }
    }

    private var frostedPanelBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.ultraThinMaterial)
    }

    private func logPanelAppearance(event: String = "✅ View appeared") {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let styleDescriptor = usesLiquidGlass ? "Liquid Glass" : "Frosted"
        print("[\(formatter.string(from: Date()))] LockScreenMusicPanel: \(event) – \(styleDescriptor)")
    }
}
