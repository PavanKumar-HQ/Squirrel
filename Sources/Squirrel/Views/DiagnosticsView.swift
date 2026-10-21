import SwiftUI
import SquirrelCore

/// Native macOS diagnostics and performance view providing transparent system telemetry,
/// scan throughput benchmarks, and live storage recovery verification.
public struct DiagnosticsView: View {
    @ObservedObject public var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Diagnostics & Efficiency")
                            .font(.system(size: 20, weight: .bold))
                        Text("Live Darwin kernel telemetry, filesystem throughput benchmarks, and APFS verification metrics.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()

                    Button {
                        appState.refreshTelemetry()
                        appState.refreshVolumeMetrics()
                    } label: {
                        Label("Refresh Telemetry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // Grid 1: Process Telemetry & Mach Kernel Resource Usage
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "cpu")
                            .foregroundColor(.accentColor)
                        Text("Process Efficiency & Memory Footprint")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text("Mach Kernel task_vm_info")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        telemetryCard(
                            title: "Physical Memory Footprint",
                            value: ByteCountFormatter.string(fromByteCount: appState.currentProcessTelemetry.physicalFootprint, countStyle: .memory),
                            subtitle: "phys_footprint (Instruments metric)",
                            systemImage: "memorychip"
                        )
                        telemetryCard(
                            title: "Resident Memory (RSS)",
                            value: ByteCountFormatter.string(fromByteCount: appState.currentProcessTelemetry.residentSize, countStyle: .memory),
                            subtitle: "resident_size in physical RAM",
                            systemImage: "internaldrive"
                        )
                        telemetryCard(
                            title: "Total CPU Time",
                            value: formatCPUTime(
                                userUs: appState.currentProcessTelemetry.userCPUTimeMicroseconds,
                                sysUs: appState.currentProcessTelemetry.systemCPUTimeMicroseconds
                            ),
                            subtitle: "User + System Mach thread time",
                            systemImage: "bolt.fill"
                        )
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)

                // Grid 2: Real Storage Volume Measurements & APFS Accounting
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "externaldrive.fill")
                            .foregroundColor(.accentColor)
                        Text("Active Volume Storage Metrics (\(appState.volumeSpace.volumeName))")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text(appState.volumeSpace.measurementSource)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        telemetryCard(
                            title: "System Settings Available",
                            value: ByteCountFormatter.string(fromByteCount: appState.volumeSpace.availableCapacity, countStyle: .file),
                            subtitle: "Includes APFS purgeable files",
                            systemImage: "checkmark.circle.fill"
                        )
                        telemetryCard(
                            title: "Raw Unallocated Space",
                            value: ByteCountFormatter.string(fromByteCount: appState.volumeSpace.rawAvailableCapacity, countStyle: .file),
                            subtitle: "Container unallocated blocks",
                            systemImage: "circle.grid.cross"
                        )
                        telemetryCard(
                            title: "Purgeable Space",
                            value: ByteCountFormatter.string(fromByteCount: appState.volumeSpace.purgeableSpace, countStyle: .file),
                            subtitle: "APFS purgeable caches/snapshots",
                            systemImage: "arrow.triangle.merge"
                        )
                        telemetryCard(
                            title: "Used Capacity",
                            value: ByteCountFormatter.string(fromByteCount: appState.volumeSpace.usedSpace, countStyle: .file),
                            subtitle: "Total − Available capacity",
                            systemImage: "chart.bar.fill"
                        )
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)

                // Section 3: Latest Scan Performance
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "gauge.with.needle")
                            .foregroundColor(.accentColor)
                        Text("Latest Filesystem Scan Throughput")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        if let date = appState.lastScanDate {
                            Text("Completed: \(date.formatted(date: .abbreviated, time: .standard))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    if let perf = appState.lastScanPerformance {
                        VStack(spacing: 12) {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                telemetryCard(
                                    title: "Scan Duration",
                                    value: String(format: "%.3f s", perf.durationSeconds),
                                    subtitle: "\(perf.itemCount) items scanned",
                                    systemImage: "clock"
                                )
                                telemetryCard(
                                    title: "Traversal Speed",
                                    value: String(format: "%.0f items/s", perf.throughputItemsPerSec),
                                    subtitle: "Items discovered per second",
                                    systemImage: "hare.fill"
                                )
                                telemetryCard(
                                    title: "Data Throughput",
                                    value: String(format: "%.1f MB/s", perf.throughputMBPerSec),
                                    subtitle: "Logical throughput rate",
                                    systemImage: "arrow.up.and.down.circle"
                                )
                                telemetryCard(
                                    title: "Scan Memory Peak",
                                    value: ByteCountFormatter.string(fromByteCount: perf.peakPhysicalFootprint, countStyle: .memory),
                                    subtitle: "Delta: +\(ByteCountFormatter.string(fromByteCount: max(0, perf.peakPhysicalFootprint - perf.startPhysicalFootprint), countStyle: .memory))",
                                    systemImage: "waveform.path.ecg"
                                )
                            }

                            HStack {
                                Text("Scan Target: ")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(perf.targetDescription)
                                    .font(.system(size: 12).monospaced())
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(perf.completedNormally ? "Normal Completion" : "Cancelled / Partial")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(perf.completedNormally ? .green : .orange)
                            }
                            .padding(.top, 4)
                        }
                    } else {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                            Text("No scan has been run yet in this session. Start a scan to capture live throughput and memory benchmarks.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)

                // Section 4: Latest Post-Cleanup Verification Report
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.accentColor)
                        Text("Latest Storage Recovery Verification")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        if let summary = appState.lastCleanupSummary {
                            confidenceBadge(confidence: summary.confidenceLevel)
                        }
                    }

                    if let summary = appState.lastCleanupSummary {
                        VStack(spacing: 12) {
                            // 5 Storage Recovery Metrics Table
                            VStack(spacing: 8) {
                                recoveryMetricRow(
                                    number: "1",
                                    title: "Logical Bytes Identified",
                                    value: ByteCountFormatter.string(fromByteCount: summary.logicalBytesIdentified, countStyle: .file),
                                    explanation: "Sum of file sizes eligible for cleanup, deduplicated by inode."
                                )
                                Divider()
                                recoveryMetricRow(
                                    number: "2",
                                    title: "Estimated Reclaimable Storage",
                                    value: ByteCountFormatter.string(fromByteCount: summary.estimatedReclaimableBytes, countStyle: .file),
                                    explanation: "Accounts for physical block allocation (st_blocks * 512) and hard links."
                                )
                                Divider()
                                recoveryMetricRow(
                                    number: "3",
                                    title: "Bytes Successfully Processed",
                                    value: ByteCountFormatter.string(fromByteCount: summary.bytesSuccessfullyProcessed, countStyle: .file),
                                    explanation: "Bytes associated with items safely moved to Trash, quarantined, or removed."
                                )
                                Divider()
                                recoveryMetricRow(
                                    number: "4",
                                    title: "Observed Filesystem Delta",
                                    value: formatDelta(summary.observedCapacityDelta),
                                    explanation: "Live APFS available capacity change (after.available − before.available)."
                                )
                                Divider()
                                recoveryMetricRow(
                                    number: "5",
                                    title: "Verified Reclaimed Storage",
                                    value: ByteCountFormatter.string(fromByteCount: summary.verifiedReclaimedBytes, countStyle: .file),
                                    explanation: "Storage recovery fully corroborated by immediate post-cleanup measurement."
                                )
                            }
                            .padding(12)
                            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                            .cornerRadius(8)

                            // Candidate Breakdown
                            HStack(spacing: 16) {
                                Label("\(summary.candidatesDiscoveredCount) discovered", systemImage: "magnifyingglass")
                                Label("\(summary.itemsEligibleCount) eligible", systemImage: "checkmark.circle")
                                Label("\(summary.itemsSkippedCount) skipped", systemImage: "forward.frame")
                                Label("\(summary.itemsSucceededCount) succeeded", systemImage: "trash.circle")
                                if summary.itemsFailedCount > 0 {
                                    Label("\(summary.itemsFailedCount) failed", systemImage: "exclamationmark.triangle")
                                        .foregroundColor(.red)
                                }
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                            // Known Limitations List
                            if !summary.knownLimitations.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Measurement Notes & APFS Behavior:")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.secondary)
                                    ForEach(summary.knownLimitations, id: \.self) { limitation in
                                        HStack(alignment: .top, spacing: 6) {
                                            Text("•")
                                                .foregroundColor(.secondary)
                                            Text(limitation)
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(10)
                                .background(Color.yellow.opacity(0.08))
                                .cornerRadius(6)
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                            Text("No cleanup operations executed yet in this session. When cleanup is performed, the 5-metric verification report will appear here.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)

                // Section 5: Controlled Diagnostic Benchmark (Cold vs Warm Traversal)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "timer")
                            .foregroundColor(.accentColor)
                        Text("Controlled Fixture Benchmark (Cold vs Warm Traversal)")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()

                        Button {
                            runBenchmark()
                        } label: {
                            if appState.isRunningBenchmark {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Run Efficiency Benchmark", systemImage: "play.fill")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(appState.isRunningBenchmark || appState.scanStatus == .scanning)
                    }

                    if appState.isRunningBenchmark {
                        Text(appState.benchmarkStatusText)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    if let bench = appState.lastControlledBenchmark {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            telemetryCard(
                                title: "Cold Traversal",
                                value: String(format: "%.3f s", bench.coldDurationSeconds),
                                subtitle: String(format: "%.0f items/s", bench.coldItemsPerSec),
                                systemImage: "snowflake"
                            )
                            telemetryCard(
                                title: "Warm Traversal",
                                value: String(format: "%.3f s", bench.warmDurationSeconds),
                                subtitle: String(format: "%.0f items/s", bench.warmItemsPerSec),
                                systemImage: "flame.fill"
                            )
                            telemetryCard(
                                title: "VFS Cache Speedup",
                                value: String(format: "%.1fx", bench.warmSpeedupFactor),
                                subtitle: "Warm speedup ratio",
                                systemImage: "arrow.up.right"
                            )
                            telemetryCard(
                                title: "Fixture Size",
                                value: "\(bench.itemCount) items",
                                subtitle: ByteCountFormatter.string(fromByteCount: bench.totalBytes, countStyle: .file),
                                systemImage: "folder"
                            )
                        }
                    } else if !appState.isRunningBenchmark {
                        Text("Click 'Run Efficiency Benchmark' to generate an isolated 500-file directory tree fixture and measure live cold vs warm scan throughput.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)

                // Section 6: Genuine Persisted Benchmark History
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                            .foregroundColor(.accentColor)
                        Text("Persisted Scan History")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text("\(appState.recentBenchmarkRecords.count) runs recorded")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    if appState.recentBenchmarkRecords.isEmpty {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.secondary)
                            Text("No historical scan runs recorded yet. Measurements are recorded automatically as scans complete.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(appState.recentBenchmarkRecords.prefix(10)) { record in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(record.targetDescription)
                                            .font(.system(size: 12, weight: .medium))
                                            .lineLimit(1)
                                        Text(record.timestamp.formatted(date: .abbreviated, time: .standard))
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(String(format: "%.0f items/s (%.3fs)", record.throughputItemsPerSec, record.durationSeconds))
                                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                        Text("\(record.itemCount) items • \(ByteCountFormatter.string(fromByteCount: record.totalLogicalBytes, countStyle: .file))")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(NSColor.textBackgroundColor).opacity(0.3))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }
            .padding(20)
        }
        .onAppear {
            appState.refreshTelemetry()
        }
    }

    private func telemetryCard(title: String, value: String, subtitle: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(size: 16, weight: .bold).monospacedDigit())
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    private func recoveryMetricRow(number: String, title: String, value: String, explanation: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(explanation)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundColor(title.contains("Verified") ? .green : .primary)
        }
    }

    private func confidenceBadge(confidence: CleanupConfidenceLevel) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(colorForConfidence(confidence))
                .frame(width: 6, height: 6)
            Text(confidence.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(colorForConfidence(confidence))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(colorForConfidence(confidence).opacity(0.12))
        .cornerRadius(6)
    }

    private func colorForConfidence(_ confidence: CleanupConfidenceLevel) -> Color {
        switch confidence {
        case .verifiedByFilesystem: return .green
        case .partiallyVerified: return .blue
        case .delayedOrSnapshotRetained: return .orange
        case .unverified: return .secondary
        }
    }

    private func formatDelta(_ delta: Int64) -> String {
        let prefix = delta > 0 ? "+" : ""
        return "\(prefix)\(ByteCountFormatter.string(fromByteCount: delta, countStyle: .file))"
    }

    private func formatCPUTime(userUs: UInt64, sysUs: UInt64) -> String {
        let totalSeconds = Double(userUs + sysUs) / 1_000_000.0
        return String(format: "%.2f s", totalSeconds)
    }

    private func runBenchmark() {
        appState.isRunningBenchmark = true
        appState.benchmarkStatusText = "Preparing isolated directory fixture with 500 files..."

        Task {
            _ = await appState.runControlledBenchmark()
            await MainActor.run {
                appState.isRunningBenchmark = false
                appState.benchmarkStatusText = ""
            }
        }
    }
}
