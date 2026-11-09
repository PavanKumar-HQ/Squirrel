import SwiftUI
import SquirrelCore

public struct ProjectPurgeView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    private var filteredProjects: [ProjectCandidate] {
        if appState.projectPurgeSearchText.isEmpty {
            return appState.discoveredProjects
        } else {
            return appState.discoveredProjects.filter {
                $0.projectName.localizedCaseInsensitiveContains(appState.projectPurgeSearchText) ||
                $0.projectType.localizedCaseInsensitiveContains(appState.projectPurgeSearchText) ||
                $0.projectPath.localizedCaseInsensitiveContains(appState.projectPurgeSearchText)
            }
        }
    }

    private var totalReclaimableBytes: Int64 {
        appState.discoveredProjects.reduce(0) { $0 + $1.totalReclaimableBytes }
    }

    private var selectedReclaimableBytes: Int64 {
        appState.discoveredProjects
            .filter { appState.selectedProjectPaths.contains($0.projectPath) }
            .reduce(0) { $0 + $1.totalReclaimableBytes }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 20))
                            .foregroundColor(SquirrelTheme.color(for: .projectArtifacts))
                        Text("Project Purge")
                            .font(.system(size: 20, weight: .bold))
                    }
                    Text("Reclaim disk space by clearing heavy build dependencies (node_modules, target, .venv) from dormant projects.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()

                Button {
                    appState.scanProjects()
                } label: {
                    Label(appState.isScanningProjects ? "Scanning Repos..." : "Scan Repositories", systemImage: "arrow.clockwise")
                }
                .disabled(appState.isScanningProjects || appState.isPurgingProjects)

                if !appState.selectedProjectPaths.isEmpty {
                    Button(role: .destructive) {
                        appState.showConfirmPurge = true
                    } label: {
                        Text("Purge Selected (\(ByteCountFormatter.string(fromByteCount: selectedReclaimableBytes, countStyle: .file)))")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(appState.isPurgingProjects)
                }
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Metric Cards
            HStack(spacing: 12) {
                StatMetricCard(
                    title: "Projects Discovered",
                    value: "\(appState.discoveredProjects.count)",
                    subtitle: "Across dev folders",
                    iconName: "folder.fill.badge.gearshape",
                    tintColor: .accentColor
                )

                StatMetricCard(
                    title: "Purgeable Dependencies",
                    value: ByteCountFormatter.string(fromByteCount: totalReclaimableBytes, countStyle: .file),
                    subtitle: "Can be reinstalled anytime",
                    iconName: "cylinder.split.1x2.fill",
                    tintColor: SquirrelTheme.color(for: .projectArtifacts)
                )

                StatMetricCard(
                    title: "Selected for Purge",
                    value: "\(appState.selectedProjectPaths.count) projects",
                    subtitle: ByteCountFormatter.string(fromByteCount: selectedReclaimableBytes, countStyle: .file),
                    iconName: "checkmark.circle.fill",
                    tintColor: .orange
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Search & Selection Bar
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Filter projects by name or language...", text: Binding(
                        get: { appState.projectPurgeSearchText },
                        set: { appState.projectPurgeSearchText = $0 }
                    ))
                    .textFieldStyle(.plain)
                    if !appState.projectPurgeSearchText.isEmpty {
                        Button { appState.projectPurgeSearchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)

                Spacer()

                Button(appState.selectedProjectPaths.count == appState.discoveredProjects.count && !appState.discoveredProjects.isEmpty ? "Deselect All" : "Select All") {
                    if appState.selectedProjectPaths.count == appState.discoveredProjects.count {
                        appState.selectedProjectPaths.removeAll()
                    } else {
                        appState.selectedProjectPaths = Set(appState.discoveredProjects.map { $0.projectPath })
                    }
                }
                .font(.system(size: 12))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Content List
            if appState.isScanningProjects {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(appState.projectScanProgressText.isEmpty ? "Scanning development repositories..." : appState.projectScanProgressText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if filteredProjects.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "shippingbox")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(appState.discoveredProjects.isEmpty ? "No projects scanned yet" : "No matching projects found")
                        .font(.system(size: 15, weight: .semibold))
                    Text(appState.discoveredProjects.isEmpty ? "Click 'Scan Repositories' to discover projects in your Code, Projects, and Developer directories." : "Try adjusting your search filter.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    if appState.discoveredProjects.isEmpty {
                        Button("Scan Repositories Now") {
                            appState.scanProjects()
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                    Spacer()
                }
            } else {
                List {
                    ForEach(filteredProjects) { project in
                        ProjectRowView(
                            project: project,
                            isSelected: appState.selectedProjectPaths.contains(project.projectPath),
                            onToggleSelection: {
                                if appState.selectedProjectPaths.contains(project.projectPath) {
                                    appState.selectedProjectPaths.remove(project.projectPath)
                                } else {
                                    appState.selectedProjectPaths.insert(project.projectPath)
                                }
                            },
                            onPurgeProject: {
                                appState.purgeProject(candidate: project)
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .confirmationDialog(
            "Purge Selected Project Artifacts?",
            isPresented: Binding(
                get: { appState.showConfirmPurge },
                set: { appState.showConfirmPurge = $0 }
            ),
            titleVisibility: .visible
        ) {
            Button("Purge \(appState.selectedProjectPaths.count) Projects (\(ByteCountFormatter.string(fromByteCount: selectedReclaimableBytes, countStyle: .file)))", role: .destructive) {
                appState.isPurgingProjects = true
                Task {
                    await appState.purgeSelectedProjects(paths: appState.selectedProjectPaths)
                    appState.selectedProjectPaths.removeAll()
                    appState.isPurgingProjects = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Build artifacts (node_modules, target, .venv, etc.) will be moved to macOS Trash. Source code, git history, and config files are completely untouched. You can reinstall packages at any time with npm/cargo/pip.")
        }
    }
}

struct ProjectRowView: View {
    let project: ProjectCandidate
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onPurgeProject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    onToggleSelection()
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(project.projectName)
                            .font(.system(size: 14, weight: .semibold))

                        Text(project.projectType)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(.accentColor)
                            .cornerRadius(4)
                    }

                    Text(project.projectPath)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(ByteCountFormatter.string(fromByteCount: project.totalReclaimableBytes, countStyle: .file))
                        .font(.system(size: 14, weight: .bold).monospacedDigit())
                        .foregroundColor(SquirrelTheme.color(for: .projectArtifacts))

                    Text("\(project.artifacts.count) artifact\(project.artifacts.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Button {
                    onPurgeProject()
                } label: {
                    Text("Purge")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(spacing: 4) {
                ForEach(project.artifacts) { artifact in
                    HStack {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(artifact.name)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        if let modDate = artifact.modificationDate {
                            Text("Modified \(modDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Text(ByteCountFormatter.string(fromByteCount: artifact.sizeBytes, countStyle: .file))
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundColor(.primary)
                    }
                    .padding(.vertical, 1)
                    .padding(.leading, 28)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
