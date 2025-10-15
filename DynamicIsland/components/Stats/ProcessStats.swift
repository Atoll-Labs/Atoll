//
//  ProcessStats.swift
//  DynamicIsland
//
//  Process information structure for stats monitoring
//  Adapted from boring.notch implementation

import Foundation
import AppKit
import SwiftUI

// Process information structure
struct ProcessStats: Identifiable, Hashable {
    let id = UUID()
    let pid: Int32
    let name: String
    let cpuUsage: Double
    let memoryUsage: UInt64 // in bytes
    let icon: NSImage?
    
    var memoryUsageString: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(memoryUsage))
    }
    
    var cpuUsageString: String {
        return String(format: "%.1f%%", cpuUsage)
    }
}

enum ProcessRankingType {
    case cpu
    case memory
    case gpu
    
    var title: String {
        switch self {
        case .cpu: return "CPU Usage"
        case .memory: return "Memory Usage" 
        case .gpu: return "GPU Usage"
        }
    }
    
    var icon: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .gpu: return "display"
        }
    }
    
    var color: Color {
        switch self {
        case .cpu: return .blue
        case .memory: return .green
        case .gpu: return .purple
        }
    }
}