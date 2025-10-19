//
//  StatsFormatting.swift
//  DynamicIsland
//
//  Lightweight formatters shared across stats detail popovers.
//
//  Created by GitHub Copilot on 19/10/2025.
//

import Foundation

enum StatsFormatting {
    static func bytes(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        formatter.includesUnit = true
        return formatter.string(fromByteCount: Int64(value))
    }
    
    static func mbPerSecond(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value >= 10 ? 1 : 2
        let number = NSNumber(value: value)
        let formatted = formatter.string(from: number) ?? String(format: "%.2f", value)
        return "\(formatted) MB/s"
    }

    static func throughput(_ valueInMegabytesPerSecond: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal

        if valueInMegabytesPerSecond >= 1 {
            formatter.maximumFractionDigits = valueInMegabytesPerSecond >= 10 ? 1 : 2
            let formatted = formatter.string(from: NSNumber(value: valueInMegabytesPerSecond))
                ?? String(format: "%.2f", valueInMegabytesPerSecond)
            return "\(formatted) MB/s"
        }

        let valueInKilobytesPerSecond = valueInMegabytesPerSecond * 1024
        if valueInKilobytesPerSecond >= 1 {
            formatter.maximumFractionDigits = valueInKilobytesPerSecond >= 10 ? 0 : 1
            let formatted = formatter.string(from: NSNumber(value: valueInKilobytesPerSecond))
                ?? String(format: valueInKilobytesPerSecond >= 10 ? "%.0f" : "%.1f", valueInKilobytesPerSecond)
            return "\(formatted) KB/s"
        }

        let valueInBytesPerSecond = valueInMegabytesPerSecond * 1_048_576
        if valueInBytesPerSecond >= 1 {
            formatter.maximumFractionDigits = 0
            let formatted = formatter.string(from: NSNumber(value: valueInBytesPerSecond))
                ?? String(format: "%.0f", valueInBytesPerSecond)
            return "\(formatted) B/s"
        }

        return "0 B/s"
    }
    
    static func percentage(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }
    
    static func gigabytes(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value >= 10 ? 1 : 2
        return (formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)) + " GB"
    }

    static func abbreviatedDuration(_ value: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: value) ?? "—"
    }
}
