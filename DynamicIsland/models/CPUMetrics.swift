//
//  CPUMetrics.swift
//  DynamicIsland
//
//  Lightweight CPU metric models derived from StatsManager sampling.
//
//  Created by GitHub Copilot on 18/10/2025.
//

import Foundation

struct CPULoadBreakdown: Equatable {
    var user: Double
    var system: Double
    var idle: Double
    
    static let zero = CPULoadBreakdown(user: 0, system: 0, idle: 100)
    
    var activeUsage: Double {
        let active = user + system
        return min(max(active, 0), 100)
    }
    
    var normalizedSegments: (user: Double, system: Double, idle: Double) {
        let total = max(user + system + idle, 0.001)
        let userFraction = min(max(user / total, 0), 1)
        let systemFraction = min(max(system / total, 0), 1)
        let idleFraction = min(max(idle / total, 0), 1)
        return (userFraction, systemFraction, idleFraction)
    }
}

struct LoadAverage: Equatable {
    var oneMinute: Double
    var fiveMinutes: Double
    var fifteenMinutes: Double
    
    static let zero = LoadAverage(oneMinute: 0, fiveMinutes: 0, fifteenMinutes: 0)
}
