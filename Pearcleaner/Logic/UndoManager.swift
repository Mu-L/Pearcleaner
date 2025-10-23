//
//  UndoManager.swift
//  Pearcleaner
//
//  Created by Alin Lupascu on 2/24/25.
//

import Foundation
import SwiftUI
import AlinFoundation

class FileManagerUndo {
    @AppStorage("settings.general.permanentDelete") private var permanentDelete: Bool = false

    // MARK: - Singleton Instance
    static let shared = FileManagerUndo()

    // Private initializer to enforce singleton pattern
    private init() {}

    // NSUndoManager instance to handle undo/redo actions
    let undoManager = UndoManager()

    func deleteFiles(at urls: [URL], isCLI: Bool = false, bundleName: String? = nil) -> Bool {
        let trashPath = (NSHomeDirectory() as NSString).appendingPathComponent(".Trash")
        let dispatchSemaphore = DispatchSemaphore(value: 0)  // Semaphore to make it synchronous
        var finalStatus = false  // Store the final success/failure status

        var tempFilePairs: [(trashURL: URL, originalURL: URL)] = []
        var seenFileNames: [String: Int] = [:]

        let hasProtectedFiles = urls.contains { $0.isProtected }

        // Create bundle folder name with app name and timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())

        let folderName: String
        if let customBundleName = bundleName {
            folderName = customBundleName
        } else if !AppState.shared.appInfo.appName.isEmpty {
            folderName = AppState.shared.appInfo.appName
        } else {
            // Fallback for plugins: use the first file's name or "Mixed Files"
            if let firstFile = urls.first {
                folderName = firstFile.deletingPathExtension().lastPathComponent
            } else {
                folderName = "Mixed Files"
            }
        }

        let bundleFolderName = "\(folderName)_\(timestamp)"
        let bundleFolderPath = (trashPath as NSString).appendingPathComponent(bundleFolderName)
        let bundleFolderURL = URL(fileURLWithPath: bundleFolderPath)

        // Create the bundle folder first
        let createFolderCommand = "/bin/mkdir -p \"\(bundleFolderPath)\""

        let mvCommands = urls.map { file -> String in
            if permanentDelete {
                return "/bin/rm -rf \"\(file.path)\""
            }
            guard !permanentDelete else { return "" }
            
            let baseName = file.lastPathComponent
            var count = seenFileNames[baseName] ?? 0
            var finalName = baseName

            // Check for duplicate names within the bundle folder
            repeat {
                if count > 0 {
                    finalName = "\(baseName)-\(count)"
                }
                count += 1
            } while FileManager.default.fileExists(atPath: (bundleFolderPath as NSString).appendingPathComponent(finalName))

            seenFileNames[baseName] = count

            let destinationURL = bundleFolderURL.appendingPathComponent(finalName)
            tempFilePairs.append((trashURL: destinationURL, originalURL: file))

            let source = "\"\(file.path)\""
            let destination = "\"\(destinationURL.path)\""
            return "/bin/mv \(source) \(destination)"
        }.joined(separator: " ; ")

        // Combine folder creation and file moves
        let finalCommands = permanentDelete ? mvCommands : "\(createFolderCommand) ; \(mvCommands)"
        let filePairs = tempFilePairs

        if executeFileCommands(finalCommands, isCLI: isCLI, hasProtectedFiles: hasProtectedFiles) {
            if !permanentDelete {
                undoManager.registerUndo(withTarget: self) { target in
                    let result = target.restoreFiles(filePairs: filePairs)
                    if !result {
                        printOS("Trash Error: Could not restore files.")
                    }
                }
                undoManager.setActionName("Delete File")
            }

            // Play trash sound after successful deletion
            if !isCLI {
                playTrashSound()
            }

            finalStatus = true
        } else {
            //            printOS("Trash Error: \(isCLI ? "Could not run commands directly with sudo." : "Could not perform privileged commands.")")
            updateOnMain {
                AppState.shared.trashError = true
            }
            finalStatus = false
        }

        dispatchSemaphore.signal()

        dispatchSemaphore.wait()
        return finalStatus
    }

    func restoreFiles(filePairs: [(trashURL: URL, originalURL: URL)], isCLI: Bool = false) -> Bool {
        if permanentDelete { return false }
        let dispatchSemaphore = DispatchSemaphore(value: 0)
        var finalStatus = true

        let hasProtectedFiles = filePairs.contains {
            $0.originalURL.deletingLastPathComponent().isProtected
        }

        let commands = filePairs.map {
            let source = "\"\($0.trashURL.path)\""
            let destination = "\"\($0.originalURL.path)\""
            return "/bin/mv \(source) \(destination)"
        }.joined(separator: " ; ")

        // Determine the bundle folder to clean up after restore
        var bundleFolderToRemove: String? = nil
        if let firstFilePair = filePairs.first {
            let bundleFolder = firstFilePair.trashURL.deletingLastPathComponent()
            // Only remove if it looks like our generated bundle folder (contains underscore for timestamp)
            if bundleFolder.lastPathComponent.contains("_") {
                bundleFolderToRemove = bundleFolder.path
            }
        }

        // Add bundle folder cleanup command if we have one to remove
        let finalCommands = if let bundleFolder = bundleFolderToRemove {
            "\(commands) ; /bin/rmdir \"\(bundleFolder)\""
        } else {
            commands
        }

        if executeFileCommands(finalCommands, isCLI: isCLI, hasProtectedFiles: hasProtectedFiles, isRestore: true) {
            finalStatus = true
        } else {
            //            printOS("Trash Error: \(isCLI ? "Failed to run restore CLI commands" : "Failed to run restore privileged commands")")
            updateOnMain {
                AppState.shared.trashError = true
            }
            finalStatus = false
        }

        dispatchSemaphore.signal()
        dispatchSemaphore.wait()
        return finalStatus
    }

    // Helper function to perform shell commands based on available privileges
    private func executeFileCommands(_ commands: String, isCLI: Bool, hasProtectedFiles: Bool, isRestore: Bool = false) -> Bool {
        var status = false

        if HelperToolManager.shared.isHelperToolInstalled {
//            printOS(isRestore ? "Attempting restore using helper tool" : "Attempting delete using helper tool")
            let semaphore = DispatchSemaphore(value: 0)
            var success = false
            var output = ""

            Task {
                let result = await HelperToolManager.shared.runCommand(commands)
                success = result.0
                output = result.1
                semaphore.signal()
            }
            semaphore.wait()

            status = success
            if !success {
                printOS(isRestore ? "Restore Error: \(output)" : "Trash Error: \(output)")
                updateOnMain {
                    AppState.shared.trashError = true
                }
            }
        } else {
            if isCLI || !hasProtectedFiles {
//                printOS(isRestore ? "Attempting restore using direct shell command" : "Attempting delete using direct shell command")
                let result = runDirectShellCommand(command: commands)
                status = result.0
                if !status {
                    printOS(isRestore ? "Restore Error: \(result.1)" : "Trash Error: \(result.1)")
                    updateOnMain {
                        AppState.shared.trashError = true
                    }
                }
            } else {
                // Helper required but not installed - trigger overlay and fail immediately
                printOS(isRestore ? "Helper tool required for protected file restore. Authorization Services has been removed." : "Helper tool required for protected file deletion. Authorization Services has been removed.")
                HelperToolManager.shared.triggerHelperRequiredAlert()
                updateOnMain {
                    AppState.shared.trashError = true
                }
                return false
            }
        }

        return status
    }

    // Helper to run direct non-privileged shell commands
    private func runDirectShellCommand(command: String) -> (Bool, String) {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", command]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        task.launch()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if output.lowercased().contains("permission denied") {
            return (false, output)
        }

        return (task.terminationStatus == 0, output)
    }

}

extension URL {
    var isProtected: Bool {
        !FileManager.default.isWritableFile(atPath: self.path)
    }
}
