import SwiftUI
import SquirrelCore

public struct NativeToolsView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    private var totalToolCacheBytes: Int64 {
        appState.supportedTools.reduce(0) { $0 + $1.estimatedCacheBytes }
    }

    private var installedToolsCount: Int {
        appState.supportedTools.filter { $0.isInstalled }.count
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 20))
                            .foregroundColor(SquirrelTheme.color(for: .developerCaches))
                        Text("Developer CLI Tools")
                            .font(.system(size: 20, weight: .bold))
                    }
                    Text("Execute native package manager and toolchain pruning commands (brew, docker, pnpm, pip, go, cargo).")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()

                Button {
                    appState.refreshTools()
                } label: {
                    Label(appState.isRefreshingTools ? "Checking..." : "Refresh Tools", systemImage: "arrow.clockwise")
                }
                .disabled(appState.isRefreshingTools || appState.pruningToolName != nil)

                Button {
                    Task {
                        await appState.pruneAllInstalledTools()
                    }
                } label: {
                    Label("Prune All Installed", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .tint(SquirrelTheme.color(for: .developerCaches))
                .disabled(installedToolsCount == 0 || appState.pruningToolName != nil)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Metric Cards
            HStack(spacing: 12) {
                StatMetricCard(
                    title: "Tools Detected",
                    value: "\(installedToolsCount) / \(appState.supportedTools.count)",
                    subtitle: "Installed in PATH",
                    iconName: "terminal.fill",
                    tintColor: .accentColor
                )

                StatMetricCard(
                    title: "Total Tool Caches",
                    value: ByteCountFormatter.string(fromByteCount: totalToolCacheBytes, countStyle: .file),
                    subtitle: "Downloads & build caches",
                    iconName: "cylinder.split.1x2.fill",
                    tintColor: SquirrelTheme.color(for: .developerCaches)
                )

                StatMetricCard(
                    title: "Execution Method",
                    value: "Native CLI",
                    subtitle: "Uses official tool commands",
                    iconName: "bolt.badge.checkmark.fill",
                    tintColor: .green
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            // Tools List
            if appState.isRefreshingTools && appState.supportedTools.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                    Text("Detecting developer CLI tools...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(appState.supportedTools) { tool in
                        ToolRowView(
                            tool: tool,
                            isPruning: appState.pruningToolName == tool.name,
                            onPrune: {
                                appState.pruningToolName = tool.name
                                Task {
                                    let result = await appState.pruneTool(tool: tool)
                                    appState.pruningToolName = nil
                                    appState.toolConsoleTitle = tool.name
                                    appState.toolConsoleOutput = result.output.isEmpty ? "Cleaned successfully. Reclaimed \(ByteCountFormatter.string(fromByteCount: result.bytesReclaimed, countStyle: .file))." : result.output
                                    appState.showToolConsoleSheet = true
                                }
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.showToolConsoleSheet },
            set: { appState.showToolConsoleSheet = $0 }
        )) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "terminal")
                        .foregroundColor(.accentColor)
                    Text("\(appState.toolConsoleTitle) Cleanup Output")
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                    Button("Done") {
                        appState.showToolConsoleSheet = false
                    }
                }

                ScrollView {
                    Text(appState.toolConsoleOutput)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.black.opacity(0.85))
                        .foregroundColor(.green)
                        .cornerRadius(6)
                }
            }
            .padding(16)
            .frame(width: 550, height: 350)
        }
        .onAppear {
            if appState.supportedTools.isEmpty {
                appState.refreshTools()
            }
        }
    }
}

struct ToolRowView: View {
    let tool: SupportedTool
    let isPruning: Bool
    let onPrune: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tool.isInstalled ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                    .frame(width: 40, height: 40)
                Image(systemName: toolIconName(for: tool.name))
                    .font(.system(size: 18))
                    .foregroundColor(tool.isInstalled ? .accentColor : .secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(tool.name)
                        .font(.system(size: 14, weight: .semibold))

                    if tool.isInstalled {
                        Text("Installed")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    } else {
                        Text("Not Found")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .foregroundColor(.secondary)
                            .cornerRadius(4)
                    }
                }

                Text(tool.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                if let exec = tool.executablePath {
                    Text(exec)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(ByteCountFormatter.string(fromByteCount: tool.estimatedCacheBytes, countStyle: .file))
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundColor(tool.estimatedCacheBytes > 0 ? SquirrelTheme.color(for: .developerCaches) : .secondary)

                if tool.isInstalled {
                    Button {
                        onPrune()
                    } label: {
                        if isPruning {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 50)
                        } else {
                            Text("Prune")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isPruning || tool.estimatedCacheBytes == 0)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func toolIconName(for name: String) -> String {
        switch name {
        case "Homebrew": return "cup.and.saucer.fill"
        case "Docker": return "shippingbox.fill"
        case "pnpm", "npm": return "cube.box.fill"
        case "pip (Python)", "uv (Python)": return "snake"
        case "Go": return "hare.fill"
        case "Rust / Cargo": return "gearshape.2.fill"
        default: return "terminal.fill"
        }
    }
}
