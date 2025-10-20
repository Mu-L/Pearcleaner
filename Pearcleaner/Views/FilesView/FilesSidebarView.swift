//
//  SidebarView.swift
//  Pearcleaner
//
//  Created by Alin Lupascu on 7/31/25.
//

import Foundation
import SwiftUI
import AlinFoundation

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @Binding var infoSidebar: Bool
    let displaySizeTotal: String

    var body: some View {
        if infoSidebar {
            HStack {
                Spacer()

                VStack(spacing: 0) {
                    AppDetailsHeaderView(displaySizeTotal: displaySizeTotal)
                    Divider().padding(.vertical, 5)
                    AppDetails()
                    Spacer()
                    ExtraOptions()
                }
                .padding()
                .frame(width: 250)
                .ifGlassSidebar()
            }
            .background(.black.opacity(0.00000000001))
            .transition(.move(edge: .trailing))
            .onTapGesture {
                infoSidebar = false
            }
        }
    }
}

struct AppDetailsHeaderView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    let displaySizeTotal: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            headerMain()

            headerDetailRow(label: "Version", value: appState.appInfo.appVersion)
            headerDetailRow(label: "Bundle", value: appState.appInfo.bundleIdentifier)
            headerDetailRow(label: "Total size of all files", value: displaySizeTotal)

            //MARK: Badges
            HStack(alignment: .center, spacing: 5) {

                if appState.appInfo.webApp { badge("web") }
                if appState.appInfo.wrapped { badge("iOS") }
                if appState.appInfo.arch != .empty { badge(appState.appInfo.arch.type) }
                badge(appState.appInfo.system ? "system" : "user")
                if appState.appInfo.cask != nil { badge("brew") }
                if appState.appInfo.steam { badge("steam") }

            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func headerMain() -> some View {
        VStack(alignment: .center) {
            if let appIcon = appState.appInfo.appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .shadow(color: appState.appInfo.averageColor ?? .black, radius: 6)
            }

            Text(appState.appInfo.appName)
                .font(.title3)
                .fontWeight(.bold)
                .lineLimit(2)
                .padding(4)
                .padding(.horizontal, 2)
//                .background {
//                    RoundedRectangle(cornerRadius: 8)
//                        .fill(appState.appInfo.averageColor ?? .clear)
//                }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func headerDetailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(ThemeColors.shared(for: colorScheme).secondaryText)
            Text(value)
        }
        .padding(.bottom, 5)
    }

    @ViewBuilder
    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(ThemeColors.shared(for: colorScheme).primaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(ThemeColors.shared(for: colorScheme).primaryText.opacity(0.1))
            .clipShape(Capsule())
    }
}


struct AppDetails: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var locations: Locations
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("settings.general.searchSensitivity") private var globalSensitivityLevel: SearchSensitivityLevel = .strict
    @State private var localSensitivityLevel: SearchSensitivityLevel = .strict
    @State private var isSliderActive: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            detailRow(label: "Location", value: appState.appInfo.path.deletingLastPathComponent().path, location: true)
            detailRow(label: "Install Date", value: appState.appInfo.creationDate.map { formattedMDDate(from: $0) })
            detailRow(label: "Modified Date", value: appState.appInfo.contentChangeDate.map { formattedMDDate(from: $0) })
            detailRow(label: "Last Used Date".localized(), value: appState.appInfo.lastUsedDate.map { formattedMDDate(from: $0) })

            Divider().padding(.vertical, 5)

            // Sensitivity Level Slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Custom Sensitivity")
                        .font(.subheadline)
                        .foregroundStyle(ThemeColors.shared(for: colorScheme).secondaryText)
                    Spacer()
                    Text(localSensitivityLevel.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(localSensitivityLevel.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(ThemeColors.shared(for: colorScheme).secondaryBG)
                        }
                }

                HStack {
                    Text("Fewer files").textCase(.uppercase).font(.caption2).foregroundStyle(ThemeColors.shared(for: colorScheme).secondaryText)
                    Slider(value: Binding(
                        get: { Double(localSensitivityLevel.rawValue) },
                        set: { newValue in
                            let newLevel = SearchSensitivityLevel(rawValue: Int(newValue)) ?? .strict
                            localSensitivityLevel = newLevel
                        }
                    ), in: 0...Double(SearchSensitivityLevel.allCases.count - 1), step: 1,
                           onEditingChanged: { editing in
                        isSliderActive = editing
                        if !editing {
                            // User finished adjusting the slider, now save and refresh
                            appState.perAppSensitivity[appState.appInfo.bundleIdentifier] = localSensitivityLevel
                            refreshFiles()
                        }
                    })
                    .tint(localSensitivityLevel.color)
                    Text("Most files").textCase(.uppercase).font(.caption2).foregroundStyle(ThemeColors.shared(for: colorScheme).secondaryText)
                }
            }
            .padding(.bottom, 8)
            .onAppear {
                // Initialize local sensitivity level from stored per-app setting or global setting
                localSensitivityLevel = appState.perAppSensitivity[appState.appInfo.bundleIdentifier] ?? globalSensitivityLevel
            }
            .onChange(of: appState.appInfo.bundleIdentifier) { _ in
                // Update when app changes
                localSensitivityLevel = appState.perAppSensitivity[appState.appInfo.bundleIdentifier] ?? globalSensitivityLevel
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
    }
    
    private func refreshFiles() {
        // Refresh the file search with the new sensitivity level
        let sensitivityOverride = appState.perAppSensitivity[appState.appInfo.bundleIdentifier]
        showAppInFiles(appInfo: appState.appInfo, appState: appState, locations: locations, sensitivityOverride: sensitivityOverride)
    }

    @ViewBuilder
    private func detailRow(label: String, value: String?, location: Bool = false) -> some View {
        VStack(alignment: .leading) {
            HStack(spacing: 2) {
                Text(label.localized())
                if location {
                    Button {
                        NSWorkspace.shared.selectFile(appState.appInfo.path.path, inFileViewerRootedAtPath: appState.appInfo.path.deletingLastPathComponent().path)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                }

            }
            .font(.subheadline)
            .foregroundStyle(ThemeColors.shared(for: colorScheme).secondaryText)

            Text(value ?? "Metadata not available")
        }
        .padding(.bottom, 5)
    }
}



struct ExtraOptions: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("settings.files.showSidebarOnLoad") private var showSidebarOnLoad: Bool = false

    // Translation selection sheet state
    @State private var languageSheetWindow: NSWindow?
    @State private var availableLanguages: [LanguageInfo] = []
    @State private var selectedLanguagesToRemove: Set<String> = []
    @State private var isLoadingLanguages: Bool = false

    var body: some View {
        HStack() {
            Text("Click to dismiss").font(.caption).foregroundStyle(ThemeColors.shared(for: colorScheme).primaryText.opacity(0.5))
            Spacer()
            Menu {
                Toggle("Show sidebar on view load", isOn: $showSidebarOnLoad)

                Divider()

                if appState.appInfo.arch == .universal {
                    Button("Lipo Architectures") {
                        let title = NSLocalizedString("App Lipo", comment: "Lipo alert title")
                        let message = String(format: NSLocalizedString("Pearcleaner will strip the %@ architecture from %@'s executable file to save space. Would you like to proceed?", comment: "Lipo alert message"), isOSArm() ? "intel" : "arm64", appState.appInfo.appName)
                        showCustomAlert(title: title, message: message, style: .informational, onOk: {
                            // Kill app if running before lipo'ing to prevent corruption
                            killApp(appId: appState.appInfo.bundleIdentifier) {
                                let _ = thinAppBundleArchitecture(at: appState.appInfo.path, of: appState.appInfo.arch)
                            }
                        })
                    }
                }

                Menu("Translations") {
                    Button("Auto Prune (Keep macOS Language)") {
                        let title = NSLocalizedString("Prune Translations", comment: "Prune alert title")
                        let message = String(format: NSLocalizedString("This will remove all unused language translation files except your macOS language", comment: "Prune alert message"))
                        showCustomAlert(title: title, message: message, style: .warning, onOk: {
                            Task {
                                do {
                                    try await pruneLanguages(in: appState.appInfo.path.path, showAlert: true)
                                } catch {
                                    printOS("Translation prune error: \(error)")
                                }
                            }
                        })
                    }

                    Button("Choose Languages...") {
                        Task {
                            await showLanguageSelectionSheet()
                        }
                    }
                }
            } label: {
                Label("Options", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    // MARK: - Language Selection Sheet

    private func showLanguageSelectionSheet() async {
        guard let parentWindow = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else {
            return
        }

        await MainActor.run {
            // Set initial loading state
            self.isLoadingLanguages = true
            self.availableLanguages = []
            self.selectedLanguagesToRemove = []

            // Create the SwiftUI view with loading state
            let contentView = TranslationSelectionSheet(
                appName: appState.appInfo.appName,
                appPath: appState.appInfo.path.path,
                languages: $availableLanguages,
                selectedLanguages: $selectedLanguagesToRemove,
                isLoading: $isLoadingLanguages,
                onConfirm: {
                    if let sheetWindow = self.languageSheetWindow {
                        parentWindow.endSheet(sheetWindow)
                    }
                    self.languageSheetWindow = nil
                    Task {
                        await performManualPrune()
                    }
                },
                onCancel: {
                    if let sheetWindow = self.languageSheetWindow {
                        parentWindow.endSheet(sheetWindow)
                    }
                    self.languageSheetWindow = nil
                }
            )

            // Create sheet window
            let hostingController = NSHostingController(rootView: contentView)

            let sheetWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            sheetWindow.title = "Choose Translations"
            sheetWindow.contentViewController = hostingController
            sheetWindow.isReleasedWhenClosed = false

            // Present as sheet (shows loading state immediately)
            parentWindow.beginSheet(sheetWindow)

            self.languageSheetWindow = sheetWindow
        }

        // Load languages in background
        let languages = await findAvailableLanguages(in: appState.appInfo.path.path)

        // Update with results
        await MainActor.run {
            self.availableLanguages = languages
            self.isLoadingLanguages = false
        }
    }

    private func performManualPrune() async {
        // Filter selected languages from available languages by code
        let languagesToRemove = availableLanguages.filter { language in
            selectedLanguagesToRemove.contains(language.code)
        }

        do {
            try await pruneLanguagesManual(languagesToRemove: languagesToRemove)

            // Show success message
            await MainActor.run {
                let removedCount = languagesToRemove.count
                let keptCount = availableLanguages.count - removedCount
                showCustomAlert(
                    title: "Translations Pruned",
                    message: "Successfully removed \(removedCount) language\(removedCount == 1 ? "" : "s"). Kept \(keptCount) language\(keptCount == 1 ? "" : "s").",
                    style: .informational
                )
            }
        } catch {
            await MainActor.run {
                showCustomAlert(
                    title: "Prune Failed",
                    message: "Failed to prune translations: \(error.localizedDescription)",
                    style: .critical
                )
            }
            printOS("Manual translation prune error: \(error)")
        }
    }
}
