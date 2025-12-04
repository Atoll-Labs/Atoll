import Foundation
import Defaults
import SwiftUI

@MainActor
class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    
    @Published private(set) var isDownloading: Bool = false
    @Published private(set) var isDownloadCompleted: Bool = false
    
    private let coordinator = DynamicIslandViewCoordinator.shared
    private var source: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "com.dynamicisland.downloads.monitor", qos: .utility)
    private var completionTimer: Timer?
    private var hasPerformedInitialScan: Bool = false
    private var initialCrDownloadFiles: Set<String> = []
    private var previousAllFiles: Set<String> = []
    
    private var ignoredFiles: Set<String> = []
    
    private var downloadsDirectory: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }
    
    private init() {
        requestDownloadsPermissionIfNeeded()
        startMonitoringIfNeeded()
        
        Defaults.publisher(.enableDownloadListener)
            .sink { [weak self] change in
                guard let self else { return }
                Task { @MainActor in
                    self.startMonitoringIfNeeded()
                }
            }
    }
    
    private func startMonitoringIfNeeded() {
        if Defaults[.enableDownloadListener] {
            startMonitoring()
        } else {
            stopMonitoring()
            updateDownloadingState(isActive: false)
        }
    }
    
    private func startMonitoring() {
        guard source == nil, let downloadsDirectory else { return }
        
        hasPerformedInitialScan = false
        initialCrDownloadFiles.removeAll()
        previousAllFiles.removeAll()
        ignoredFiles.removeAll()
        isDownloading = false
        
        let path = downloadsDirectory.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            print("DownloadManager: Failed to open Downloads directory at \(path)")
            return
        }
        
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: queue
        )
        
        src.setEventHandler { [weak self] in
            self?.scanDownloadsDirectory()
        }
        
        src.setCancelHandler {
            close(fd)
        }
        
        source = src
        src.resume()
        
        // Initial scan
        scanDownloadsDirectory()
        
        print("DownloadManager: Started monitoring Downloads folder at \(path)")
    }
    
    private func stopMonitoring() {
        source?.cancel()
        source = nil
        hasPerformedInitialScan = false
        initialCrDownloadFiles.removeAll()
        previousAllFiles.removeAll()
        ignoredFiles.removeAll()
        isDownloading = false
        print("DownloadManager: Stopped monitoring Downloads folder")
    }
    
    private func scanDownloadsDirectory() {
        guard let downloadsDirectory else { return }
        
        let crDownloadFiles: Set<String>
        let allFiles: Set<String>
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: downloadsDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )
            crDownloadFiles = Set(contents
                .filter { 
                    let ext = $0.pathExtension.lowercased()
                    return ext == "crdownload" || ext == "download"
                }
                .map { $0.lastPathComponent }
            )
            allFiles = Set(contents.map { $0.lastPathComponent })
        } catch {
            print("DownloadManager: Failed to read Downloads directory: \(error)")
            crDownloadFiles = []
            allFiles = []
        }
        
        Task { @MainActor in
            self.processDownloadFiles(crDownloadFiles, allFiles: allFiles)
        }
    }
    
    private func processDownloadFiles(_ crDownloadFiles: Set<String>, allFiles: Set<String>) {
        // Initial scan - track and ignore existing files
        if !hasPerformedInitialScan {
            hasPerformedInitialScan = true
            initialCrDownloadFiles = crDownloadFiles
            previousAllFiles = allFiles
            ignoredFiles = crDownloadFiles
            isDownloading = false
            print("DownloadManager: initial scan - found \(crDownloadFiles.count) existing files, ignoring")
            return
        }
        
        // Calculate differences
        let newFiles = crDownloadFiles.subtracting(initialCrDownloadFiles)
        let disappearedFiles = initialCrDownloadFiles.subtracting(crDownloadFiles)
        let newRegularFiles = allFiles.subtracting(previousAllFiles).subtracting(crDownloadFiles)
        
        // Log disappeared files
        if !disappearedFiles.isEmpty {
            print("DownloadManager: files disappeared: \(disappearedFiles.joined(separator: ", "))")
            ignoredFiles.subtract(disappearedFiles)
        }
        
        // Log new regular files (potential completed downloads)
        if !newRegularFiles.isEmpty {
            print("DownloadManager: new regular files appeared: \(newRegularFiles.joined(separator: ", "))")
        }
        
        // Update tracked files BEFORE calculating active files
        initialCrDownloadFiles = crDownloadFiles
        previousAllFiles = allFiles
        
        // Calculate active downloads
        let activeFiles = crDownloadFiles.subtracting(ignoredFiles)
        let hasActiveDownloads = !activeFiles.isEmpty
        
        
        // Handle new downloads
        if !newFiles.isEmpty {
            let newActiveFiles = newFiles.subtracting(ignoredFiles)
            if !newActiveFiles.isEmpty {
                print("DownloadManager: new download detected: \(newActiveFiles.joined(separator: ", "))")
                
                if !isDownloading {
                    updateDownloadingState(isActive: true)
                }
            }
        }
        
        // Handle state changes based on active downloads
        if isDownloading {
            if !hasActiveDownloads {
                // No more active downloads
                // Check if new regular files appeared (indicating successful completion)
                if !newRegularFiles.isEmpty || disappearedFiles.isEmpty {
                    // Download completed successfully - show completion state
                    if !isDownloadCompleted {
                        print("DownloadManager: download completed successfully - showing completion")
                        updateDownloadingState(isActive: false)
                    }
                } else {
                    // Download files disappeared but no new regular files appeared - cancelled
                    print("DownloadManager: download cancelled - closing immediately")
                    closeDownloadViewImmediately()
                }
            } else if !disappearedFiles.isEmpty {
                // Some downloads finished but others remain
                print("DownloadManager: some finished, \(activeFiles.count) still active")
            }
        } else if hasActiveDownloads {
            // We're not showing UI but we have active downloads - this shouldn't happen
            // but let's handle it gracefully
            print("DownloadManager: active downloads found but UI closed - reopening")
            updateDownloadingState(isActive: true)
        }
    }
    
    private func requestDownloadsPermissionIfNeeded() {
        guard let downloadsDirectory else { return }
        
        _ = try? FileManager.default.contentsOfDirectory(
            at: downloadsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
    }
    
    private func updateDownloadingState(isActive: Bool) {
        completionTimer?.invalidate()
        completionTimer = nil
        
        if isActive {
            isDownloadCompleted = false
            
            if !isDownloading {
                withAnimation(.smooth) {
                    isDownloading = true
                }
                print("DownloadManager: download started")
                coordinator.toggleExpandingView(
                    status: true,
                    type: .download,
                    value: 0,
                    browser: .chromium
                )
            }
        } else {
            if isDownloading {
                print("DownloadManager: download finished - showing completion")
                withAnimation(.smooth) {
                    isDownloadCompleted = true
                }
                
                // Close after 2 seconds
                completionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        self?.closeDownloadView()
                    }
                }
            }
        }
    }
    
    private func closeDownloadView() {
        withAnimation(.smooth) {
            isDownloading = false
            isDownloadCompleted = false
        }
        print("DownloadManager: closing download view")
        coordinator.toggleExpandingView(
            status: false,
            type: .download,
            value: 0,
            browser: .chromium
        )
    }
    
    private func closeDownloadViewImmediately() {
        completionTimer?.invalidate()
        completionTimer = nil
        
        withAnimation(.smooth) {
            isDownloading = false
            isDownloadCompleted = false
        }
        print("DownloadManager: closing download view immediately (cancelled)")
        coordinator.toggleExpandingView(
            status: false,
            type: .download,
            value: 0,
            browser: .chromium
        )
    }
}
