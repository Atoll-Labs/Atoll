//
//  CPUStatsDetailView.swift
//  DynamicIsland
//
//  SwiftUI port of the stats app CPU popup layout.
//  Mirrors dashboard, history, detail rows, and top processes.
//
//  Created by GitHub Copilot on 18/10/2025.
//

import SwiftUI

struct CPUStatsDetailView: View {
    @ObservedObject private var statsManager = StatsManager.shared
    @State private var topProcesses: [ProcessStats] = []
    
    private let systemColor = Color(red: 0.94, green: 0.32, blue: 0.28)
    private let userColor = Color(red: 0.27, green: 0.52, blue: 0.97)
    private let idleColor = Color.gray.opacity(0.28)
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                StatsCard(title: "CPU Overview") {
                    CPUUsageDashboard(
                        breakdown: statsManager.cpuBreakdown,
                        loadAverage: statsManager.cpuLoadAverage,
                        uptime: statsManager.cpuUptime,
                        coreCount: statsManager.cpuCoreUsage.count,
                        systemColor: systemColor,
                        userColor: userColor,
                        idleColor: idleColor,
                        temperature: statsManager.cpuTemperature,
                        frequency: statsManager.cpuFrequency
                    )
                }

                StatsCard(title: "Top Processes") {
                    CPUProcessList(processes: topProcesses, accentColor: userColor)
                }
                
                if !statsManager.cpuCoreUsage.isEmpty {
                    StatsCard(title: "Per-Core Usage") {
                        CPUCoreUsageGrid(cores: statsManager.cpuCoreUsage, accentColor: userColor)
                    }
                }
            }
            .padding(16)
        }
        .onReceive(statsManager.$topCPUProcesses) { processes in
            topProcesses = Array(processes.prefix(8))
        }
        .onAppear {
            topProcesses = Array(statsManager.topCPUProcesses.prefix(8))
        }
    }
}
