import SwiftUI
import SquirrelCore

public struct SnapshotsView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.metering.matrix")
                            .font(.system(size: 20))
                            .foregroundColor(.purple)
                        Text("APFS Local Snapshots")
                            .font(.system(size: 20, weight: .bold))
                    }
                    Text("Time Machine and backup software create local APFS snapshots that retain deleted files on disk until purged.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()

                Button {
                    appState.refreshSnapshots()
                } label: {
                    Label(appState.isRefreshingSnapshots ? "Checking..." : "Refresh Snapshots", systemImage: "arrow.clockwise")
                }
                .disabled(appState.isRefreshingSnapshots || appState.deletingSnapshotName != nil)

                if !appState.localSnapshots.isEmpty {
                    Button(role: .destructive) {
                        appState.showConfirmDeleteAllSnapshots = true
                    } label: {
                        Text("Delete All Snapshots")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(appState.deletingSnapshotName != nil)
                }
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Info Alert Banner
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Why can deleted storage remain occupied?")
                        .font(.system(size: 12, weight: .semibold))
                    Text("When an APFS snapshot exists, trashing large files does not physically free APFS volume blocks because the snapshot continues to reference them. Deleting outdated snapshots frees this space immediately.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color.blue.opacity(0.08))
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)

            Divider()

            // Snapshot List
            if appState.isRefreshingSnapshots && appState.localSnapshots.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                    Text("Checking tmutil for local snapshots...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if appState.localSnapshots.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.green.opacity(0.8))
                    Text("No Local APFS Snapshots Retaining Storage")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Your disk is not retaining deleted files in local Time Machine or backup snapshots.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(appState.localSnapshots) { snapshot in
                        HStack(spacing: 12) {
                            Image(systemName: snapshot.isTimeMachine ? "clock.arrow.circlepath" : "externaldrive.badge.timemachine")
                                .font(.system(size: 18))
                                .foregroundColor(snapshot.isTimeMachine ? .purple : .orange)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(snapshot.isTimeMachine ? "Time Machine Local Snapshot" : "Third-Party Snapshot")
                                        .font(.system(size: 13, weight: .semibold))

                                    Text(snapshot.dateString)
                                        .font(.system(size: 11, design: .monospaced))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.12))
                                        .cornerRadius(4)
                                }

                                Text(snapshot.name)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button {
                                appState.deletingSnapshotName = snapshot.name
                                Task {
                                    await appState.deleteSnapshot(snapshot: snapshot)
                                    appState.deletingSnapshotName = nil
                                }
                            } label: {
                                if appState.deletingSnapshotName == snapshot.name {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 50)
                                } else {
                                    Text("Delete")
                                        .font(.system(size: 11, weight: .medium))
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(appState.deletingSnapshotName != nil)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }
        }
        .confirmationDialog(
            "Delete All Local APFS Snapshots?",
            isPresented: Binding(
                get: { appState.showConfirmDeleteAllSnapshots },
                set: { appState.showConfirmDeleteAllSnapshots = $0 }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete \(appState.localSnapshots.count) Snapshots", role: .destructive) {
                Task {
                    await appState.deleteAllSnapshots()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will invoke tmutil deletelocalsnapshots to free APFS blocks locked by local snapshots. Your external Time Machine drive backups are completely untouched.")
        }
        .onAppear {
            if appState.localSnapshots.isEmpty {
                appState.refreshSnapshots()
            }
        }
    }
}
