//
//  DevelopmentView.swift
//  Pearcleaner
//
//  Created by Alin Lupascu on 11/15/24.
//
import SwiftUI
import AlinFoundation

struct PathEnv: Identifiable, Hashable, Equatable {
    let id = UUID()
    let name: String
    let paths: [String]
}

struct EnvironmentCleanerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @State private var paths: [PathEnv] = []
    @State private var selectedPaths: Set<String> = []
    @State private var searchText: String = ""
    @State private var lastRefreshDate: Date?
    @State private var isLoading: Bool = false
    @AppStorage("settings.interface.scrollIndicators") private var scrollIndicators: Bool = false
    @AppStorage("settings.interface.animationEnabled") private var animationEnabled: Bool = true

    // Store all paths, including "All" and each environment
    private var allPaths: [PathEnv] {
        let realPaths = PathLibrary.getPaths()
        let combined = realPaths.flatMap { $0.paths }
        return [PathEnv(name: "All", paths: combined)] + realPaths
    }

    private func refreshPaths() {
        isLoading = true

        Task {
            await refreshPathsAsync()
        }
    }

    private func refreshPathsAsync() async {
        let fileManager = FileManager.default
        let refreshedPaths = allPaths.map { env in
            let validPaths = env.paths.filter {
                let expanded = NSString(string: $0).expandingTildeInPath
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: expanded, isDirectory: &isDir) {
                    if isDir.boolValue {
                        if let contents = try? fileManager.contentsOfDirectory(atPath: expanded) {
                            return contents.filter { $0 != ".DS_Store" }.isEmpty == false
                        }
                    } else {
                        return true
                    }
                }
                return false
            }
            return PathEnv(name: env.name, paths: validPaths)
        }

        await MainActor.run {
            self.paths = refreshedPaths
            self.lastRefreshDate = Date()
            self.isLoading = false

            // Update selected environment to its refreshed version
            if let selected = appState.selectedEnvironment {
                if let updated = paths.first(where: { $0.name == selected.name }) {
                    appState.selectedEnvironment = updated
                } else {
                    appState.selectedEnvironment = nil
                }
            } else {
                // Default to "All" if no environment is selected and paths exist
                if let allEnvironment = paths.first(where: { $0.name == "All" }),
                   !allEnvironment.paths.isEmpty {
                    appState.selectedEnvironment = allEnvironment
                }
            }

            // Clear selection when refreshing paths
            selectedPaths.removeAll()
        }
    }

    // Computed property for filtered paths
    private var filteredPaths: [PathEnv] {
        guard let selectedEnvironment = appState.selectedEnvironment else { return [] }

        if searchText.isEmpty {
            return [selectedEnvironment]
        }

        let filteredEnvironment = PathEnv(
            name: selectedEnvironment.name,
            paths: selectedEnvironment.paths.filter { path in
                path.localizedCaseInsensitiveContains(searchText)
            }
        )

        return [filteredEnvironment]
    }

    // Total count of paths for stats
    private var totalPathsCount: Int {
        if let selectedEnvironment = appState.selectedEnvironment {
            return selectedEnvironment.paths.count
        }
        return 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ThemeColors.shared(for: colorScheme).secondaryText)

                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(ThemeColors.shared(for: colorScheme).primaryText)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(ThemeColors.shared(for: colorScheme).secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(ThemeColors.shared(for: colorScheme).accent)
            .controlGroup(Capsule(style: .continuous), level: .primary)
            .padding(.top, 5)

            if let selectedEnvironment = appState.selectedEnvironment, filteredPaths.count > 0 {

                // Stats header
                HStack {
                    let filteredCount = filteredPaths.first?.paths.count ?? 0
                    Text("\(filteredCount) path\(filteredCount == 1 ? "" : "s")")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(ThemeColors.shared(for: colorScheme).secondaryText)

                    if isLoading {
                        Text("Loading...")
                            .font(.caption)
                            .foregroundStyle(ThemeColors.shared(for: colorScheme).secondaryText)
                    }

                    Spacer()

                    if let lastRefresh = lastRefreshDate {
                        TimelineView(.periodic(from: lastRefresh, by: 1.0)) { _ in
                            Text("Updated \(formatRelativeTime(lastRefresh))")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(ThemeColors.shared(for: colorScheme).secondaryText)
                        }
                    }
                }
                .padding(.vertical)

                // Add workspace storage cleaner for certain IDEs
                let workspaceIDEs = ["VS Code", "Cursor", "Zed"]

                if workspaceIDEs.contains(selectedEnvironment.name) {
                    WorkspaceStorageCleanerView(ideName: selectedEnvironment.name)
                        .id(selectedEnvironment.name)
                        .padding(.bottom, 10)
                }

                ScrollView {
                    LazyVStack(spacing: 10) {
                        if selectedEnvironment.name == "All" {
                            // Show categorized view for "All" environment
                            ForEach(paths.filter { !$0.paths.isEmpty && $0.name != "All" }, id: \.name) { environment in
                                let environmentPaths = environment.paths.filter { path in
                                    searchText.isEmpty || path.localizedCaseInsensitiveContains(searchText)
                                }

                                if !environmentPaths.isEmpty {
                                    EnvironmentCategorySection(
                                        environment: PathEnv(name: environment.name, paths: environmentPaths),
                                        selectedPaths: $selectedPaths,
                                        onRefresh: refreshPaths
                                    )
                                }
                            }
                        } else {
                            // Show regular path list for specific environments
                            if let filteredEnvironment = filteredPaths.first {
                                ForEach(filteredEnvironment.paths, id: \.self) { path in
                                    PathRowView(
                                        path: path,
                                        isSelected: Binding(
                                            get: { selectedPaths.contains(path) },
                                            set: { isSelected in
                                                if isSelected {
                                                    selectedPaths.insert(path)
                                                } else {
                                                    selectedPaths.remove(path)
                                                }
                                            }
                                        )
                                    ) {
                                        refreshPaths()
                                        selectedPaths.remove(path)
                                        if let env = appState.selectedEnvironment,
                                           paths.first(where: { $0.name == env.name })?.paths.isEmpty ?? true {
                                            appState.selectedEnvironment = nil
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(scrollIndicators ? .automatic : .never)
            } else {
                VStack(alignment: .center) {
                    Spacer()
                    Text("Select an environment to view stored cache")
                        .font(.title2)
                        .foregroundStyle(ThemeColors.shared(for: colorScheme).secondaryText)
                    Spacer()
                }
                .frame(maxWidth: .infinity)

            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
        .padding(.bottom, !selectedPaths.isEmpty ? 10 : 20)
        .safeAreaInset(edge: .bottom) {
            if !selectedPaths.isEmpty {
                // Show selection toolbar only when items are selected
                if let selectedEnvironment = appState.selectedEnvironment, !selectedEnvironment.paths.isEmpty {
                    HStack {
                        Spacer()

                        HStack(spacing: 10) {
                            let availablePaths = selectedEnvironment.name == "All" ?
                                paths.filter { !$0.paths.isEmpty && $0.name != "All" }.flatMap { env in
                                    env.paths.filter { path in
                                        searchText.isEmpty || path.localizedCaseInsensitiveContains(searchText)
                                    }
                                } :
                                (filteredPaths.first?.paths ?? [])

                            Button(selectedPaths.count == availablePaths.count ? "Deselect All" : "Select All") {
                                if selectedPaths.count == availablePaths.count {
                                    selectedPaths.removeAll()
                                } else {
                                    selectedPaths = Set(availablePaths)
                                }
                            }
                            .buttonStyle(ControlGroupButtonStyle(
                                foregroundColor: ThemeColors.shared(for: colorScheme).accent,
                                shape: Capsule(style: .continuous),
                                level: .primary,
                                skipControlGroup: true
                            ))

                            Divider().frame(height: 10)

                            Button("Delete \(selectedPaths.count) Selected Folders") {
                                showCustomAlert(title: "Warning", message: "This will delete \(selectedPaths.count) selected folders. Are you sure?", style: .warning, onOk: {
                                    let urls = selectedPaths.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
                                    let bundleName = "Development - Folders (\(selectedPaths.count))"
                                    let _ = FileManagerUndo.shared.deleteFiles(at: urls, bundleName: bundleName)
                                    selectedPaths.removeAll()
                                    refreshPaths()
                                    if let env = appState.selectedEnvironment,
                                       paths.first(where: { $0.name == env.name })?.paths.isEmpty ?? true {
                                        appState.selectedEnvironment = nil
                                    }
                                })
                            }
                            .buttonStyle(ControlGroupButtonStyle(
                                foregroundColor: ThemeColors.shared(for: colorScheme).accent,
                                shape: Capsule(style: .continuous),
                                level: .primary,
                                skipControlGroup: true
                            ))

                            Divider().frame(height: 10)

                            Button("Delete \(selectedPaths.count) Selected Contents") {
                                showCustomAlert(title: "Warning", message: "This will delete the contents of \(selectedPaths.count) selected folders. Are you sure?", style: .warning, onOk: {
                                    var allContentURLs: [URL] = []
                                    let fm = FileManager.default
                                    for path in selectedPaths {
                                        let expanded = NSString(string: path).expandingTildeInPath
                                        if let contents = try? fm.contentsOfDirectory(atPath: expanded) {
                                            for item in contents {
                                                let itemPath = (expanded as NSString).appendingPathComponent(item)
                                                allContentURLs.append(URL(fileURLWithPath: itemPath))
                                            }
                                        }
                                    }
                                    if !allContentURLs.isEmpty {
                                        let bundleName = "Development - Contents (\(selectedPaths.count))"
                                        let _ = FileManagerUndo.shared.deleteFiles(at: allContentURLs, bundleName: bundleName)
                                    }
                                    selectedPaths.removeAll()
                                    refreshPaths()
                                    if let env = appState.selectedEnvironment,
                                       paths.first(where: { $0.name == env.name })?.paths.isEmpty ?? true {
                                        appState.selectedEnvironment = nil
                                    }
                                })
                            }
                            .buttonStyle(ControlGroupButtonStyle(
                                foregroundColor: ThemeColors.shared(for: colorScheme).accent,
                                shape: Capsule(style: .continuous),
                                level: .primary,
                                skipControlGroup: true
                            ))
                        }
                        .controlGroup(Capsule(style: .continuous), level: .primary)

                        Spacer()
                    }
                    .padding([.horizontal, .bottom])
                }
            }
        }
        .onAppear {
            refreshPaths()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DevelopmentViewShouldRefresh"))) { _ in
            refreshPaths()
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbar {
            TahoeToolbarItem(placement: .navigation) {
                VStack(alignment: .leading){
                    Text("Development Environments").foregroundStyle(ThemeColors.shared(for: colorScheme).primaryText).font(.title2).fontWeight(.bold)
                    Text("Clean stored files and cache for common IDEs")
                        .font(.callout).foregroundStyle(ThemeColors.shared(for: colorScheme).secondaryText)
                }
            }

            ToolbarItem { Spacer() }

            TahoeToolbarItem(isGroup: true) {
                Menu {
                    ForEach(paths, id: \.self) { environment in
                        Group {
                            if environment.paths.isEmpty {
                                Text(verbatim: "\(environment.name) (0)")
                                    .foregroundStyle(ThemeColors.shared(for: colorScheme).secondaryText)
                            } else {
                                Button {
                                    appState.selectedEnvironment = environment
                                    selectedPaths.removeAll()
                                } label: {
                                    Text(verbatim: "\(environment.name) (\(environment.paths.count))")
                                }
                            }
                        }
                    }
                } label: {
                    Label(appState.selectedEnvironment?.name ?? "Select Environment", systemImage: "list.bullet")
                }
                .labelStyle(.titleAndIcon)
                .menuIndicator(.hidden)

                Button {
                    refreshPaths()
                } label: {
                    Label("Refresh", systemImage: "arrow.counterclockwise")
                }
            }
        }
    }
}

// MARK: - Environment Category Section

struct EnvironmentCategorySection: View {
    let environment: PathEnv
    @Binding var selectedPaths: Set<String>
    let onRefresh: () -> Void
    @Environment(\.colorScheme) var colorScheme
    @State private var isCollapsed: Bool = false
    @AppStorage("settings.interface.animationEnabled") private var animationEnabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Category header
            Button(action: {
                withAnimation(.easeInOut(duration: animationEnabled ? 0.3 : 0)) {
                    isCollapsed.toggle()
                }
            }) {
                HStack {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(ThemeColors.shared(for: colorScheme).secondaryText)
                        .frame(width: 10)

                    Text(environment.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(ThemeColors.shared(for: colorScheme).primaryText)

                    Text(verbatim: "(\(environment.paths.count))")
                        .font(.caption)
                        .foregroundStyle(ThemeColors.shared(for: colorScheme).secondaryText)

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            // Path rows
            if !isCollapsed {
                ForEach(environment.paths, id: \.self) { path in
                    PathRowView(
                        path: path,
                        isSelected: Binding(
                            get: { selectedPaths.contains(path) },
                            set: { isSelected in
                                if isSelected {
                                    selectedPaths.insert(path)
                                } else {
                                    selectedPaths.remove(path)
                                }
                            }
                        )
                    ) {
                        onRefresh()
                        selectedPaths.remove(path)
                    }
                }
                .transition(.opacity.combined(with: .slide))
            }
        }
    }
}

struct PathRowView: View {
    @Environment(\.colorScheme) var colorScheme
    let path: String
    @Binding var isSelected: Bool
    let onDelete: () -> Void
    @State private var exists: Bool = false
    @State private var isEmpty: Bool = false
    @State private var matchingPaths: [String] = []
    @State private var sizeLoading: Bool = true
    @State private var size: Int64 = 0

    var body: some View {

        VStack(alignment: .leading, spacing: 10) {
            if !matchingPaths.isEmpty {
                ForEach(matchingPaths, id: \.self) { matchedPath in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {

                            // Selection checkbox
                            Button(action: { isSelected.toggle() }) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? .blue : ThemeColors.shared(for: colorScheme).secondaryText)
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)

                            Button {
                                openInFinder(matchedPath)
                            } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(ThemeColors.shared(for: colorScheme).accent)

                            matchedPath.pathWithArrows()
                                .foregroundStyle(ThemeColors.shared(for: colorScheme).primaryText)
                                .font(.headline)

                            Spacer()

                            Text(formatByte(size: size).human)
                                .foregroundStyle(ThemeColors.shared(for: colorScheme).secondaryText)

                            HStack(spacing: 10) {
                                Button("Delete Folder") {
                                    deleteFolder(matchedPath)
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.mini)
                                .foregroundStyle(.red)
                                .help("Delete the folder")

                                Divider().frame(height: 10)

                                Button("Delete Contents") {
                                    deleteFolderContents(matchedPath)
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.mini)
                                .foregroundStyle(.red)
                                .disabled(isEmpty)
                                .help("Delete all files within this folder")
                            }

                        }
                        .onAppear {
                            DispatchQueue.global(qos: .userInitiated).async {
                                if let url = URL(string: matchedPath) {
                                    let calculatedSize = totalSizeOnDisk(for: url)

                                    DispatchQueue.main.async {
                                        self.size = calculatedSize
                                    }
                                }
                            }
                        }

                    }

                }
            } else {
                HStack {
                    Text(expandTilde(path))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(ThemeColors.shared(for: colorScheme).secondaryText)

                    Spacer()
                    Text("Not Found")
                        .foregroundStyle(ThemeColors.shared(for: colorScheme).secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(ThemeColors.shared(for: colorScheme).secondaryBG.clipShape(RoundedRectangle(cornerRadius: 8)))
        .onAppear {
            checkPath(path)
        }
    }

    private func checkPath(_ path: String) {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let fileManager = FileManager.default

        if path.contains("*") {
            // Handle wildcard paths
            if expandedPath.contains("/*/") {
                // Handle middle wildcard like ~/.gem/ruby/*/cache/
                let components = expandedPath.split(separator: "*", maxSplits: 1, omittingEmptySubsequences: true)
                guard components.count == 2 else {
                    exists = false
                    matchingPaths = []
                    return
                }

                let basePath = String(components[0]) // Path before wildcard
                let remainderPath = String(components[1]) // Path after wildcard

                do {
                    let contents = try fileManager.contentsOfDirectory(atPath: basePath)
                        .filter { $0 != ".DS_Store" } // Exclude .DS_Store

                    let matchingFolders = contents.filter {
                        fileManager.fileExists(atPath: (basePath as NSString).appendingPathComponent($0), isDirectory: nil)
                    }.map { (basePath as NSString).appendingPathComponent($0) }

                    matchingPaths = matchingFolders.compactMap { folder in
                        let fullPath = (folder as NSString).appendingPathComponent(remainderPath)
                        return fileManager.fileExists(atPath: fullPath) ? fullPath : nil
                    }

                    exists = !matchingPaths.isEmpty
                    isEmpty = matchingPaths.allSatisfy { folder in
                        if let innerContents = try? fileManager.contentsOfDirectory(atPath: folder) {
                            return innerContents.filter { $0 != ".DS_Store" }.isEmpty
                        }
                        return true
                    }
                } catch {
                    exists = false
                    matchingPaths = []
                }
            } else {
                // Handle partial folder wildcard like ~/Library/Application Support/Google/AndroidStudio*/
                let basePath = NSString(string: expandedPath).deletingLastPathComponent
                let partialComponent = NSString(string: expandedPath).lastPathComponent.replacingOccurrences(of: "*", with: "")

                do {
                    let contents = try fileManager.contentsOfDirectory(atPath: basePath)
                        .filter { $0 != ".DS_Store" } // Exclude .DS_Store

                    matchingPaths = contents.filter { $0.hasPrefix(partialComponent) }
                        .map { (basePath as NSString).appendingPathComponent($0) }

                    exists = !matchingPaths.isEmpty
                    isEmpty = matchingPaths.allSatisfy { folder in
                        if let innerContents = try? fileManager.contentsOfDirectory(atPath: folder) {
                            return innerContents.filter { $0 != ".DS_Store" }.isEmpty
                        }
                        return true
                    }
                } catch {
                    exists = false
                    matchingPaths = []
                }
            }
        } else {
            // Normal path handling
            exists = fileManager.fileExists(atPath: expandedPath)
            if exists {
                if let contents = try? fileManager.contentsOfDirectory(atPath: expandedPath) {
                    isEmpty = contents.filter { $0 != ".DS_Store" }.isEmpty // Exclude .DS_Store
                } else {
                    isEmpty = true
                }
                matchingPaths = [expandedPath]
            } else {
                matchingPaths = []
            }
        }
    }

    private func expandTilde(_ path: String) -> String {
        return NSString(string: path).expandingTildeInPath
    }

    private func openInFinder(_ matchedPath: String) {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: matchedPath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: matchedPath))
        }
    }

    private func deleteFolderContents(_ matchedPath: String) {
        let fileManager = FileManager.default
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: matchedPath)
            var contentURLs: [URL] = []
            for item in contents {
                let itemPath = (matchedPath as NSString).appendingPathComponent(item)
                contentURLs.append(URL(fileURLWithPath: itemPath))
            }
            if !contentURLs.isEmpty {
                let folderName = (matchedPath as NSString).lastPathComponent
                let bundleName = "Development - \(folderName) Contents"
                let _ = FileManagerUndo.shared.deleteFiles(at: contentURLs, bundleName: bundleName)
            }
            checkPath(path) // Recheck the state after deletion
        } catch {
            printOS("Error deleting contents of folder: \(error)")
        }
    }

    private func deleteFolder(_ matchedPath: String) {
        let folderName = (matchedPath as NSString).lastPathComponent
        let bundleName = "Development - \(folderName)"
        let url = URL(fileURLWithPath: matchedPath)
        let result = FileManagerUndo.shared.deleteFiles(at: [url], bundleName: bundleName)
        if result {
            onDelete()
        }
    }
}

struct WorkspaceStorageCleanerView: View {
    @AppStorage("settings.interface.scrollIndicators") private var scrollIndicators: Bool = false
    @Environment(\.colorScheme) var colorScheme
    let ideName: String
    @State private var orphanedWorkspaces: [OrphanedWorkspace] = []
    @State private var isScanning = false
    @State private var lastScanDate: Date?
    
    struct OrphanedWorkspace {
        let id = UUID()
        let name: String
        let path: String
        let folderPath: String
        let size: String
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "macwindow")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workspace Storage Cleaner")
                        .font(.headline)
                        .foregroundStyle(ThemeColors.shared(for: colorScheme).primaryText)
                    Text("Remove workspace storage for deleted project folders")
                        .font(.caption)
                        .foregroundStyle(ThemeColors.shared(for: colorScheme).secondaryText)
                }
                
                Spacer()
                
                Button(action: scanForOrphanedWorkspaces) {
                    HStack(spacing: 6) {
                        if isScanning {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                        Text(isScanning ? "Scanning..." : "Scan")
                    }
                }
                .disabled(isScanning)
                .controlSize(.small)
                .buttonStyle(.plain)
                .foregroundStyle(ThemeColors.shared(for: colorScheme).accent)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .controlGroup(Capsule(style: .continuous), level: .primary)
            }
            
            if !orphanedWorkspaces.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Found \(orphanedWorkspaces.count) orphaned workspace\(orphanedWorkspaces.count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                        
                        Spacer()
                    }

                    ScrollView {
                        ForEach(orphanedWorkspaces, id: \.id) { workspace in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workspace.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    Text(verbatim: "\(workspace.folderPath)")
                                        .font(.caption)
                                        .foregroundStyle(ThemeColors.shared(for: colorScheme).secondaryText)
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                }

                                Spacer()

                                Text(workspace.size)
                                    .font(.caption2)
                                    .foregroundStyle(ThemeColors.shared(for: colorScheme).secondaryText)

                                Button("Delete") {
                                    cleanOrphanedWorkspace(workspace)
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.mini)
                                .foregroundStyle(.red)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(ThemeColors.shared(for: colorScheme).secondaryText.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                    .scrollIndicators(scrollIndicators ? .automatic : .never)
                    .frame(maxHeight: 180)
                    .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Spacer()

                        Button("Delete All") {
                            cleanAllOrphanedWorkspaces()
                        }
                        .disabled(isScanning)
                        .controlSize(.small)
                        .buttonStyle(.plain)
                        .foregroundStyle(ThemeColors.shared(for: colorScheme).accent)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .controlGroup(Capsule(style: .continuous), level: .primary)

                        Button("Cancel") {
                            cancelWorkspaceCleanup()
                        }
                        .disabled(isScanning)
                        .controlSize(.small)
                        .buttonStyle(.plain)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .controlGroup(Capsule(style: .continuous), level: .primary)
                    }
                }
            } else if lastScanDate != nil {
                Text("No orphaned workspaces found")
                    .font(.caption)
                    .foregroundStyle(ThemeColors.shared(for: colorScheme).secondaryText)
                    .italic()
            }
        }
        .padding()
        .background(ThemeColors.shared(for: colorScheme).primaryText.opacity(0.05))
        .cornerRadius(10)
    }
    
    private func scanForOrphanedWorkspaces() {
        isScanning = true
        orphanedWorkspaces = []
        
        Task {
            let found = await findOrphanedWorkspaces()
            
            await MainActor.run {
                self.orphanedWorkspaces = found
                self.lastScanDate = Date()
                self.isScanning = false
            }
        }
    }
    
    private func findOrphanedWorkspaces() async -> [OrphanedWorkspace] {
        let configPath = ideName == "VS Code" ? 
            "~/Library/Application Support/Code" : 
            "~/Library/Application Support/Cursor"
        
        let expandedPath = NSString(string: configPath).expandingTildeInPath
        let workspaceStoragePath = "\(expandedPath)/User/workspaceStorage"
        
        let fileManager = FileManager.default
        var orphaned: [OrphanedWorkspace] = []
        
        guard let workspaceDirs = try? fileManager.contentsOfDirectory(atPath: workspaceStoragePath) else {
            return orphaned
        }
        
        for workspaceDir in workspaceDirs {
            let workspacePath = "\(workspaceStoragePath)/\(workspaceDir)"
            let workspaceJsonPath = "\(workspacePath)/workspace.json"
            
            if fileManager.fileExists(atPath: workspaceJsonPath) {
                if let folderPath = extractFolderPath(from: workspaceJsonPath),
                   !fileManager.fileExists(atPath: folderPath) {
                    
                    let size = calculateDirectorySize(at: workspacePath)
                    
                    orphaned.append(OrphanedWorkspace(
                        name: workspaceDir,
                        path: workspacePath,
                        folderPath: folderPath,
                        size: size
                    ))
                }
            }
        }
        
        return orphaned
    }
    
    private func extractFolderPath(from workspaceJsonPath: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: workspaceJsonPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let folder = json["folder"] as? String else {
            return nil
        }
        
        // Remove file:// prefix and decode URL encoding
        var cleanPath = folder.replacingOccurrences(of: "file://", with: "")
        cleanPath = cleanPath.removingPercentEncoding ?? cleanPath
        cleanPath = cleanPath.replacingOccurrences(of: "+", with: " ")
        
        return cleanPath
    }
    
    private func calculateDirectorySize(at path: String) -> String {
        let url = URL(fileURLWithPath: path)
        
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return "0 B"
        }
        
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  let fileSize = resourceValues.fileSize,
                  let isDirectory = resourceValues.isDirectory,
                  !isDirectory else {
                continue
            }
            
            totalSize += Int64(fileSize)
        }
        
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    private func cleanOrphanedWorkspace(_ workspace: OrphanedWorkspace) {
        let bundleName = "Development - Workspace (\(workspace.name))"
        let url = URL(fileURLWithPath: workspace.path)
        let result = FileManagerUndo.shared.deleteFiles(at: [url], bundleName: bundleName)
        if result {
            orphanedWorkspaces.removeAll { $0.id == workspace.id }
        }
    }

    private func cleanAllOrphanedWorkspaces() {
        let urls = orphanedWorkspaces.map { URL(fileURLWithPath: $0.path) }
        let bundleName = "Development - Workspaces (\(orphanedWorkspaces.count))"
        let result = FileManagerUndo.shared.deleteFiles(at: urls, bundleName: bundleName)
        if result {
            orphanedWorkspaces.removeAll()
        }
    }

    private func cancelWorkspaceCleanup() {
        orphanedWorkspaces = []
        lastScanDate = nil
        isScanning = false
    }
}

struct PathLibrary {
    static func getPaths() -> [PathEnv] {
        return [
            PathEnv(name: "Android Studio", paths: [
                "~/.android/",
                "~/Library/Application Support/Google/AndroidStudio*/",
                "~/Library/Logs/AndroidStudio/",
                "~/Library/Caches/Google/AndroidStudio*/"
            ]),
            PathEnv(name: "Cargo", paths: [
                "~/.cargo/",
                "~/.cargo/git/",
                "~/.cargo/registry/"
            ]),
            PathEnv(name: "Carthage", paths: [
                "~/Carthage/",
                "~/Library/Caches/org.carthage.CarthageKit/"
            ]),
            PathEnv(name: "CocoaPods", paths: [
                "~/Library/Caches/CocoaPods/",
                "~/.cocoapods/repos/"
            ]),
            PathEnv(name: "Composer", paths: [
                "~/.composer/cache/"
            ]),
            PathEnv(name: "Conda", paths: [
                "~/.conda/",
                "~/anaconda3/",
                "~/miniconda3/"
            ]),
            PathEnv(name: "Cursor", paths: [
                "~/Library/Application Support/Cursor/",
                "~/Library/Application Support/Cursor/Cache",
                "~/Library/Application Support/Cursor/GPUCache",
                "~/Library/Application Support/Cursor/CachedConfigurations",
                "~/Library/Application Support/Cursor/CachedData",
                "~/Library/Application Support/Cursor/CachedExtensionVSIXs",
                "~/Library/Application Support/Cursor/CachedExtensions",
                "~/Library/Application Support/Cursor/CachedProfilesData",
                "~/Library/Application Support/Cursor/Code Cache",
                "~/Library/Application Support/Cursor/User",
                "~/.cursor/",
                "~/.cursor/extensions/"
            ]),
            PathEnv(name: "Deno", paths: [
                "~/Library/Caches/deno"
            ]),
            PathEnv(name: "Go Modules", paths: [
                "~/go/bin/",
                "~/go/pkg/mod/"
            ]),
            PathEnv(name: "Gradle", paths: [
                "~/.gradle/caches/",
                "~/.gradle/wrapper/"
            ]),
            PathEnv(name: "Haskell Stack", paths: [
                "~/.stack/",
                "~/.stack/global-project/",
                "~/.stack/snapshots/"
            ]),
            PathEnv(name: "IntelliJ IDEA", paths: [
                "~/Library/Application Support/JetBrains/",
                "~/Library/Caches/JetBrains/",
                "~/Library/Logs/JetBrains/"
            ]),
            PathEnv(name: "Maven", paths: [
                "~/.m2/"
            ]),
            PathEnv(name: "Nix", paths: [
                "/nix/store/",
                "~/.cache/nix/"
            ]),
            PathEnv(name: "Npm", paths: [
                "/usr/local/lib/node_modules/",
                "~/.nvm/versions/node/*/",
                "~/.npm/",
                "~/.nvm/",
                "~/Library/pnpm/store"
            ]),
            PathEnv(name: "Pip", paths: [
                "~/Library/Caches/pip/"
            ]),
            PathEnv(name: "Poetry", paths: [
                "~/Library/Caches/pypoetry/",
                "~/Library/Application Support/pypoetry/"
            ]),
            PathEnv(name: "Pub", paths: [
                "~/.pub-cache/",
                "~/Library/Caches/flutter_engine/"
            ]),
            PathEnv(name: "Pyenv", paths: [
                "~/.pyenv/",
                "~/.pyenv/cache/"
            ]),
            PathEnv(name: "Ruby Gems", paths: [
                "~/.gem/",
                "~/.gem/ruby/*/"
            ]),
            PathEnv(name: "Swift", paths: [
                "~/.swiftpm/"
            ]),
            PathEnv(name: "Uv", paths: [
                "~/.cache/uv/",
                "~/.config/uv/",
                "~/.local/share/uv/"
            ]),
            PathEnv(name: "VS Code", paths: [
                "~/Library/Application Support/Code/",
                "~/Library/Application Support/Code/Cache",
                "~/Library/Application Support/Code/GPUCache",
                "~/Library/Application Support/Code/CachedConfigurations",
                "~/Library/Application Support/Code/CachedData",
                "~/Library/Application Support/Code/CachedExtensionVSIXs",
                "~/Library/Application Support/Code/CachedExtensions",
                "~/Library/Application Support/Code/CachedProfilesData",
                "~/Library/Application Support/Code/Code Cache",
                "~/Library/Application Support/Code/User",
                "~/.vscode/",
                "~/.vscode/extensions/",
                "~/.vscode/cli/"
            ]),
            PathEnv(name: "Xcode", paths: [
                "~/Library/Caches/com.apple.dt.xcodebuild/",
                "~/Library/Caches/com.apple.dt.Xcode.sourcecontrol.Git/",
                "~/Library/Developer/CoreSimulator/Devices/",
                "~/Library/Developer/DeveloperDiskImages/",
                "~/Library/Developer/Xcode/Archives/",
                "~/Library/Developer/Xcode/DerivedData/",
                "~/Library/Developer/Xcode/DocumentationCache/",
                "~/Library/Developer/Xcode/iOS DeviceSupport/",
                "~/Library/Developer/Xcode/tvOS DeviceSupport/",
                "~/Library/Developer/Xcode/watchOS DeviceSupport/",
                "~/Library/Developer/Xcode/macOS DeviceSupport/",
                "~/Library/Developer/Xcode/UserData/"
            ]),
            PathEnv(name: "Yarn", paths: [
                "~/.cache/yarn/",
                "~/.yarn-cache/",
                "~/.yarn/global/"
            ]),
            PathEnv(name: "Zed", paths: [
                "~/.config/zed/",
                "~/Library/Caches/Zed/",
                "~/Library/Application Support/Zed/",
                "~/Library/Application Support/Zed/node/cache/"
            ])
        ]
            .map { PathEnv(name: $0.name, paths: $0.paths.sorted()) } // Sort paths within each environment
            .sorted { $0.name < $1.name } // Sort environments by name
    }
}
