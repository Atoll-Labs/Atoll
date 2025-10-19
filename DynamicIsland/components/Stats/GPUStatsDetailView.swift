//
//  GPUStatsDetailView.swift
//  DynamicIsland
//
//  GPU detail dashboard inspired by the Stats app layout.
//
//  Created by GitHub Copilot on 19/10/2025.
//

import SwiftUI

struct GPUStatsDetailView: View {
    @ObservedObject private var statsManager = StatsManager.shared
    @State private var topProcesses: [ProcessStats] = []
    
    private let accentColor = Color.purple
    private let cardBackground = Color(nsColor: .windowBackgroundColor).opacity(0.65)
    private let processDisplayLimit = 8
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                StatsCard(title: "GPU Overview", padding: 16, background: cardBackground, cornerRadius: 12) {
                    GPUUsageDashboard(
                        usage: statsManager.gpuUsage,
                        breakdown: statsManager.gpuBreakdown,
                        averageUsage: statsManager.avgGpuUsage,
                        lastUpdated: statsManager.lastUpdated,
                        accentColor: accentColor,
                        primaryDevice: statsManager.gpuDevices.first
                    )
                }
                
                StatsCard(title: "Top Processes", padding: 16, background: cardBackground, cornerRadius: 12) {
                    CPUProcessList(processes: topProcesses, accentColor: accentColor, displayLimit: processDisplayLimit)
                }

                if !statsManager.gpuDevices.isEmpty {
                    StatsCard(title: "Devices", padding: 16, background: cardBackground, cornerRadius: 12) {
                        GPUDeviceList(devices: statsManager.gpuDevices, accentColor: accentColor)
                    }
                }
            }
            .padding(16)
        }
        .frame(minWidth: 360, minHeight: 380)
        .onAppear(perform: refreshProcesses)
        .onReceive(statsManager.$lastUpdated) { _ in
            refreshProcesses()
        }
    }
    
    private func refreshProcesses() {
        let processes = statsManager.getProcessesRankedByGPU()
        topProcesses = Array(processes.prefix(processDisplayLimit))
    }
}

private struct GPUUsageDashboard: View {
    let usage: Double
    let breakdown: GPUBreakdown
    let averageUsage: Double
    let lastUpdated: Date
    let accentColor: Color
    let primaryDevice: GPUDeviceMetrics?
    
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                leftColumn
                breakdownAndMeta
            }
            VStack(alignment: .leading, spacing: 20) {
                leftColumn
                breakdownAndMeta
            }
        }
    }
    
    private func formattedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private var leftColumn: some View {
        VStack(alignment: .center, spacing: 16) {
            usageRing
            GPUEngineGauges(render: renderEngineUtilization, tiler: tilerUtilization, accentColor: accentColor)
        }
    }

    private var breakdownAndMeta: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                breakdownSection
                metaSection
            }
            VStack(alignment: .leading, spacing: 16) {
                breakdownSection
                Divider().padding(.vertical, 4)
                metaSection
            }
        }
    }

    private var usageRing: some View {
        ZStack {
            Circle()
                .stroke(accentColor.opacity(0.25), lineWidth: 12)
                .frame(width: 108, height: 108)

            RingArc(start: 0, end: CGFloat(min(max(usage / 100, 0), 1)), color: accentColor, lineWidth: 12)
                .frame(width: 108, height: 108)

            VStack(spacing: 4) {
                Text(StatsFormatting.percentage(usage))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Active")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailRow(color: accentColor.opacity(0.9), label: "Render", value: StatsFormatting.percentage(breakdown.render))
            DetailRow(color: accentColor.opacity(0.7), label: "Compute", value: StatsFormatting.percentage(breakdown.compute))
            DetailRow(color: accentColor.opacity(0.55), label: "Video", value: StatsFormatting.percentage(breakdown.video))
            DetailRow(color: accentColor.opacity(0.45), label: "Other", value: StatsFormatting.percentage(breakdown.other))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Averages")
                .font(.caption)
                .foregroundColor(.secondary)
            DetailRow(color: nil, label: "Session Avg", value: StatsFormatting.percentage(averageUsage))
            DetailRow(color: nil, label: "Last Update", value: formattedTimestamp(lastUpdated))
            if let device = primaryDevice {
                Divider().padding(.vertical, 4)
                DetailRow(color: nil, label: "Active GPU", value: device.formattedVendorModel)
                DetailRow(color: nil, label: "Status", value: device.isActive ? "Active" : "Idle")
                DetailRow(color: nil, label: "Temperature", value: device.temperatureText)
                if let cores = device.cores {
                    DetailRow(color: nil, label: "Cores", value: "\(cores)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var renderEngineUtilization: Double? {
        primaryDevice?.renderUtilization ?? breakdown.render
    }

    private var tilerUtilization: Double? {
        primaryDevice?.tilerUtilization
    }
}

private struct GPUEngineGauges: View {
    let render: Double?
    let tiler: Double?
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Engines")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(alignment: .center, spacing: 16) {
                EngineGaugeView(title: "Render", value: render, tint: accentColor)
                EngineGaugeView(title: "Tiler", value: tiler, tint: accentColor.opacity(0.75))
            }
        }
    }
}

private struct EngineGaugeView: View {
    let title: String
    let value: Double?
    let tint: Color
    private let size: CGFloat = 68

    var body: some View {
        if let value {
            CircularGaugeView(
                title: title,
                value: min(max(value / 100, 0), 1),
                tint: tint,
                centerPrimaryText: StatsFormatting.percentage(value),
                centerSecondaryText: nil,
                subtitle: nil,
                size: size,
                lineWidth: 7,
                backgroundTint: tint.opacity(0.18)
            )
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 7)
                    .frame(width: size, height: size)
                Text("—")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct GPUDeviceList: View {
    let devices: [GPUDeviceMetrics]
    let accentColor: Color

    var body: some View {
        VStack(spacing: 16) {
            ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                GPUDeviceRow(device: device, accentColor: accentColor)
                if index < devices.count - 1 {
                    Divider()
                }
            }
        }
    }
}

private struct GPUDeviceRow: View {
    let device: GPUDeviceMetrics
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle()
                    .fill(device.isActive ? Color.green.opacity(0.85) : Color.red.opacity(0.7))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.formattedVendorModel)
                        .font(.system(size: 13, weight: .semibold))
                    Text(device.isActive ? "Active" : "Idle")
                        .font(.caption2)
                        .foregroundColor(device.isActive ? .green : .secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(device.utilizationText)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(accentColor)
                    Text("Utilization")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            VStack(spacing: 8) {
                if let render = device.renderUtilization {
                    DetailRow(color: accentColor.opacity(0.9), label: "Renderer", value: StatsFormatting.percentage(render))
                }
                if let tiler = device.tilerUtilization {
                    DetailRow(color: accentColor.opacity(0.6), label: "Tiler", value: StatsFormatting.percentage(tiler))
                }
                if let temp = device.temperature {
                    DetailRow(color: nil, label: "Temperature", value: String(format: "%.0f°C", temp))
                }
                if let fan = device.fanSpeed {
                    DetailRow(color: nil, label: "Fan Speed", value: "\(fan)%")
                }
                if let coreClock = device.coreClock {
                    DetailRow(color: nil, label: "Core Clock", value: "\(coreClock) MHz")
                }
                if let memoryClock = device.memoryClock {
                    DetailRow(color: nil, label: "Memory Clock", value: "\(memoryClock) MHz")
                }
                if let cores = device.cores {
                    DetailRow(color: nil, label: "Cores", value: "\(cores)")
                }
            }
        }
    }
}
