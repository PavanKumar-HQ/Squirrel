import SwiftUI
import AppKit
import SquirrelCore

/// Interactive view allowing developers to audit and kill orphaned dev servers (Next.js, Vite, Node, Python)
/// that hold open TCP ports, consume memory, and generate unwanted background heat.
public struct ActivePortsView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Active Ports & Servers")
                            .font(.system(size: 20, weight: .bold))

                        if appState.isLoadingPorts {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }

                    Text("Detect running web servers, dev processes (Node, Vite, Python, Go) and release occupied ports.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    appState.refreshListeningPorts()
                } label: {
                    Label("Refresh Ports", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.isLoadingPorts)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // List of Listening Ports
            if appState.listeningPorts.isEmpty && !appState.isLoadingPorts {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "network.badge.shield.half.filled")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("No active user listening ports discovered")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Click 'Refresh Ports' to inspect the live socket table.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(appState.listeningPorts) { port in
                            portRow(port)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if appState.listeningPorts.isEmpty {
                appState.refreshListeningPorts()
            }
        }
    }

    private func portRow(_ port: ListeningPortRecord) -> some View {
        HStack(spacing: 14) {
            // Port badge
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(port.isDevServer ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.1))
                    .frame(width: 64, height: 42)

                VStack(spacing: 1) {
                    Text(":\(port.port)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(port.isDevServer ? .accentColor : .primary)
                    Text(port.protocolType)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }

            // Process info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(port.command)
                        .font(.system(size: 13, weight: .bold))

                    Text("PID \(port.pid)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)

                    if port.isDevServer {
                        Text("DEV SERVER")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(SquirrelTheme.brandWarm))
                    } else if port.isSystemProtected {
                        Text("SYSTEM")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }

                Text("Address: \(port.address) • User: \(port.user)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Kill Process Button
            if !port.isSystemProtected {
                Button {
                    appState.terminateListeningPort(port)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                        Text("Kill Server")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Terminate process \(port.command) (PID \(port.pid)) to free port :\(port.port)")
            } else {
                Text("Protected")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.trailing, 8)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(port.isDevServer ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

