//
//  IOKitHelpers.swift
//  DynamicIsland
//
//  Helper utilities borrowed from the Stats project for working with IORegistry and CFData blobs.
//

import Foundation
import IOKit
import Darwin

func di_getIOProperties(_ entry: io_registry_entry_t) -> NSDictionary? {
    var properties: Unmanaged<CFMutableDictionary>? = nil
    guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess else {
        return nil
    }
    defer { properties?.release() }
    return properties?.takeUnretainedValue()
}

func di_getIOName(_ entry: io_registry_entry_t) -> String? {
    let pointer = UnsafeMutablePointer<io_name_t>.allocate(capacity: 1)
    defer { pointer.deallocate() }
    let result = IORegistryEntryGetName(entry, pointer)
    guard result == kIOReturnSuccess else {
        if let message = String(validatingUTF8: mach_error_string(result)) {
            print("IORegistryEntryGetName error: \(message)")
        }
        return nil
    }
    return String(cString: UnsafeRawPointer(pointer).assumingMemoryBound(to: CChar.self))
}

func di_convertCFDataToFrequencies(_ data: Data, isM4: Bool = false) -> [Int32] {
    guard !data.isEmpty else { return [] }
    let bytes = [UInt8](data)

    let multiplier: UInt32 = isM4 ? 1_000 : 1_000_000
    var frequencies: [Int32] = []

    for chunkStart in stride(from: 0, to: bytes.count, by: 8) {
        let upperBound = min(chunkStart + 8, bytes.count)
        let chunk = bytes[chunkStart..<upperBound]
        if chunk.count < 4 { continue }
        let value = chunk.prefix(4).enumerated().reduce(UInt32(0)) { partial, element in
            partial | (UInt32(element.element) << (UInt32(element.offset) * 8))
        }
        frequencies.append(Int32(value / multiplier))
    }

    return frequencies
}
