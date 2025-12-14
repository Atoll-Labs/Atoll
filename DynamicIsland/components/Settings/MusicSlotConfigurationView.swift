import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct MusicSlotConfigurationView: View {
    @Default(.musicControlSlots) private var musicControlSlots
    @Default(.showMediaOutputControl) private var showMediaOutputControl
    @ObservedObject private var musicManager = MusicManager.shared

    private let slotCount = MusicControlButton.slotCount

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            layoutPreview
            Divider()
            palette
            resetButton
        }
        .onAppear {
            ensureSlotCapacity(slotCount)
            removeDisallowedControls()
        }
        .onChange(of: showMediaOutputControl) { _, _ in
            removeDisallowedControls()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Layout Preview")
                .font(.headline)
            Text("Drag items between slots or drop from the palette to remap controls.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var layoutPreview: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(0..<slotCount, id: \.self) { index in
                    slotPreview(for: index)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(width: 56, height: 56)
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                }
                .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
                    handleDropOnTrash(providers)
                }

                Text("Clear slot")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 72)
            }
        }
    }

    private var palette: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Control Palette")
                .font(.headline)
            Text("Drag a control onto a slot or tap to place it in the first empty slot.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 12) {
                    ForEach(pickerOptions, id: \.self) { control in
                        paletteItem(for: control)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var resetButton: some View {
        HStack {
            Spacer()
            Button("Reset to defaults") {
                withAnimation {
                    musicControlSlots = MusicControlButton.defaultLayout
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private func slotPreview(for index: Int) -> some View {
        let slot = slotValue(at: index)
        return Group {
            if slot != .none {
                slotPreview(for: slot)
                    .frame(width: 48, height: 48)
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                    .onDrag {
                        NSItemProvider(object: NSString(string: "slot:\(index)"))
                    }
                    .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
                        handleDrop(providers, toIndex: index)
                    }
            } else {
                slotPreview(for: slot)
                    .frame(width: 48, height: 48)
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                    .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
                        handleDrop(providers, toIndex: index)
                    }
            }
        }
    }

    @ViewBuilder
    private func slotPreview(for slot: MusicControlButton) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))

            if slot == .none {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .frame(width: 26, height: 26)
            } else {
                Image(systemName: slot.iconName)
                    .font(.system(size: slot.prefersLargeScale ? 18 : 15, weight: .medium))
                    .foregroundStyle(previewIconColor(for: slot))
            }
        }
    }

    private func paletteItem(for control: MusicControlButton) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: control.iconName)
                        .font(.system(size: control.prefersLargeScale ? 18 : 15, weight: .medium))
                        .foregroundStyle(control == .mediaOutput && !showMediaOutputControl ? .secondary : .primary)
                }
                .onDrag {
                    NSItemProvider(object: NSString(string: "control:\(control.rawValue)"))
                }
                .onTapGesture {
                    place(control)
                }

            Text(control.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 72)
                .multilineTextAlignment(.center)
        }
        .opacity(control == .mediaOutput && !showMediaOutputControl ? 0.4 : 1)
        .disabled(control == .mediaOutput && !showMediaOutputControl)
    }

    private func place(_ control: MusicControlButton) {
        if let emptyIndex = musicControlSlots.firstIndex(of: .none) {
            updateSlot(control, at: emptyIndex)
        } else {
            updateSlot(control, at: 0)
        }
    }

    private func slotValue(at index: Int) -> MusicControlButton {
        let normalized = musicControlSlots.normalized(allowingMediaOutput: showMediaOutputControl)
        guard normalized.indices.contains(index) else { return .none }
        return normalized[index]
    }

    private var pickerOptions: [MusicControlButton] {
        let base = MusicControlButton.pickerOptions
        if showMediaOutputControl {
            return base
        }
        return base.filter { $0 != .mediaOutput }
    }

    private func previewIconColor(for slot: MusicControlButton) -> Color {
        switch slot {
        case .shuffle:
            return musicManager.isShuffled ? .red : .primary
        case .repeatMode:
            return musicManager.repeatMode == .off ? .primary : .red
        case .lyrics:
            return Defaults[.enableLyrics] ? .accentColor : .primary
        default:
            return .primary
        }
    }

    private func ensureSlotCapacity(_ target: Int) {
        guard target > musicControlSlots.count else { return }
        let padding = target - musicControlSlots.count
        musicControlSlots.append(contentsOf: Array(repeating: .none, count: padding))
    }

    private func handleDrop(_ providers: [NSItemProvider], toIndex: Int) -> Bool {
        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { item, _ in
                guard let raw = item as? String else { return }
                DispatchQueue.main.async {
                    processDropString(raw, toIndex: toIndex)
                }
            }
            return true
        }
        return false
    }

    private func handleDropOnTrash(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { item, _ in
                guard let raw = item as? String else { return }
                DispatchQueue.main.async {
                    if raw.hasPrefix("slot:"), let index = Int(raw.dropFirst(5)) {
                        clearSlot(at: index)
                    }
                }
            }
            return true
        }
        return false
    }

    private func processDropString(_ raw: String, toIndex: Int) {
        if raw.hasPrefix("slot:"), let source = Int(raw.dropFirst(5)) {
            swapSlot(from: source, to: toIndex)
        } else if raw.hasPrefix("control:"), let control = MusicControlButton(rawValue: String(raw.dropFirst(8))) {
            updateSlot(control, at: toIndex)
        }
    }

    private func clearSlot(at index: Int) {
        guard index >= 0 && index < musicControlSlots.count else { return }
        musicControlSlots[index] = .none
    }

    private func swapSlot(from source: Int, to destination: Int) {
        guard source != destination else { return }
        ensureSlotCapacity(max(source, destination) + 1)
        musicControlSlots.swapAt(source, destination)
    }

    private func updateSlot(_ value: MusicControlButton, at index: Int) {
        ensureSlotCapacity(index + 1)
        var current = musicControlSlots
        current[index] = value
        musicControlSlots = current
    }

    private func removeDisallowedControls() {
        if showMediaOutputControl { return }
        let filtered = musicControlSlots.map { $0 == .mediaOutput ? .none : $0 }
        musicControlSlots = filtered
    }
}
