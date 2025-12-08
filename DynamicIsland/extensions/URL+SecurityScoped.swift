//
//  URL+SecurityScoped.swift
//  DynamicIsland
//
//  Ported from boringNotch shelf utilities.
//

import Foundation
import AppKit

extension URL {
    func accessSecurityScopedResource<Value>(accessor: (URL) throws -> Value) rethrows -> Value {
        let didStartAccessing = startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                stopAccessingSecurityScopedResource()
            }
        }
        return try accessor(self)
    }

    /// Async version of accessSecurityScopedResource
    func accessSecurityScopedResource<Value>(accessor: (URL) async throws -> Value) async rethrows -> Value {
        let didStartAccessing = startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                stopAccessingSecurityScopedResource()
            }
        }
        return try await accessor(self)
    }
}

extension Array where Element == URL {
    func accessSecurityScopedResources<Value>(accessor: ([URL]) async throws -> Value) async rethrows -> Value {
        let didStart = map { $0.startAccessingSecurityScopedResource() }
        defer {
            for (url, started) in zip(self, didStart) where started {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try await accessor(self)
    }
}
