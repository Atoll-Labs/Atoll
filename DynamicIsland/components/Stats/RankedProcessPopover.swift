//
//  RankedProcessPopover.swift
//  DynamicIsland
//
//  Popover component for displaying ranked processes by different metrics
//  Adapted from boring.notch implementation

import SwiftUI

struct RankedProcessPopover: View {
    let rankingType: ProcessRankingType
    @ObservedObject var statsManager = StatsManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isHovering = false
    
    // Callback to notify parent about hover state
    var onHoverChange: ((Bool) -> Void)?
    
    private var rankedProcesses: [ProcessStats] {
        switch rankingType {
        case .cpu:
            return statsManager.getProcessesRankedByCPU()
        case .memory:
            return statsManager.getProcessesRankedByMemory()
        case .gpu:
            return statsManager.getProcessesRankedByGPU()
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: rankingType.icon)
                    .font(.title3)
                    .foregroundColor(rankingType.color)
                
                Text("Top Processes by \(rankingType.title)")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 4)
            
            Divider()
            
            // Process list
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(rankedProcesses.prefix(15).enumerated()), id: \.element.id) { index, process in
                        RankedProcessRow(
                            process: process,
                            rank: index + 1,
                            rankingType: rankingType
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 300)
            
            // Footer with refresh button
            HStack {
                Text("\(rankedProcesses.count) processes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Refresh") {
                    // Trigger stats update
                    if statsManager.isMonitoring {
                        // Stats will auto-refresh
                    }
                }
                .font(.caption)
                .foregroundColor(rankingType.color)
            }
        }
        .padding()
        .frame(width: 320)
        .frame(minHeight: 200)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        .onHover { hovering in
            isHovering = hovering
            onHoverChange?(hovering)
        }
    }
}

struct RankedProcessRow: View {
    let process: ProcessStats
    let rank: Int
    let rankingType: ProcessRankingType
    @State private var isHovered = false
    
    private var primaryValue: String {
        switch rankingType {
        case .cpu:
            return process.cpuUsageString
        case .memory:
            return process.memoryUsageString
        case .gpu:
            return process.cpuUsageString // Using CPU as proxy for GPU
        }
    }
    
    private var secondaryValue: String {
        switch rankingType {
        case .cpu:
            return process.memoryUsageString
        case .memory:
            return process.cpuUsageString
        case .gpu:
            return process.memoryUsageString
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Rank
            Text("\(rank)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(rankingType.color)
                .frame(width: 24, alignment: .center)
            
            // App icon
            Group {
                if let icon = process.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "app")
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 20, height: 20)
            
            // Process info
            VStack(alignment: .leading, spacing: 2) {
                Text(process.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                HStack(spacing: 8) {
                    Text(primaryValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(rankingType.color)
                    
                    Text(secondaryValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // PID
            Text("PID: \(process.pid)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .opacity(0.7)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color(NSColor.selectedControlColor).opacity(0.2) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    RankedProcessPopover(rankingType: .cpu)
        .background(Color.black)
}