import SwiftUI
import AppKit
import SquirrelCore

/// Native SwiftUI modal presenting Squirrel's Pro features and monetization tier.
/// Allows users to upgrade to Pro ($19.99 one-time lifetime license) or enter a purchased license key.
public struct UpgradeToProView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Hero Banner
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    gradient: Gradient(colors: [
                        SquirrelTheme.brandWarm.opacity(0.18),
                        Color.accentColor.opacity(0.08),
                        Color(NSColor.windowBackgroundColor)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                        .padding(16)
                }
                .buttonStyle(.plain)

                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [SquirrelTheme.brandWarm, Color.orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 54, height: 54)
                            .shadow(color: SquirrelTheme.brandWarm.opacity(0.35), radius: 8, y: 4)

                        Image(systemName: "sparkles")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 24)

                    Text("Unlock Squirrel Pro")
                        .font(.system(size: 24, weight: .bold))

                    Text("The ultra-fast, fanless-safe storage optimizer for Apple Silicon.\nOne-time purchase • No subscription traps • Zero background battery drain.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
            }
            .frame(height: 180)

            Divider()

            // Pro Features Comparison Grid
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Everything you get with Pro:")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.secondary)

                        featureRow(
                            icon: "infinity",
                            title: "Unlimited Cleaning (Beyond 5 GB Free Limit)",
                            desc: "Clean tens or hundreds of gigabytes across system caches, logs, and downloads with zero restrictions."
                        )

                        featureRow(
                            icon: "shippingbox.fill",
                            title: "Full Developer Workspace Purge",
                            desc: "1-click reclaim for heavy Xcode DerivedData, simulator runtime caches, Rust target folders, and node_modules."
                        )

                        featureRow(
                            icon: "trash.circle.fill",
                            title: "Uninstalled App Leftover Eliminator",
                            desc: "Deep-scans ~/Library to wipe residual data left behind by uninstalled applications without dragging your Mac down."
                        )

                        featureRow(
                            icon: "wrench.and.screwdriver.fill",
                            title: "Full 9-Task System Maintenance Suite",
                            desc: "Run SQLite VACUUM for Mail/Safari, routing table flushes, and repair system preview caches."
                        )

                        featureRow(
                            icon: "speedometer",
                            title: "Apple Silicon Hardware Thermal Sentinel",
                            desc: "Live chassis temperature, kernel memory pressure, and zero-fan throttling alerts."
                        )
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 16)

                    Divider()
                        .padding(.horizontal, 24)

                    // Pricing / Purchase Option
                    VStack(spacing: 12) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("Lifetime License")
                                        .font(.system(size: 15, weight: .bold))
                                    Text("BEST VALUE")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(SquirrelTheme.brandWarm))
                                }
                                Text("Pay once, keep forever. Free updates for macOS Sequoia & beyond.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("$19.99")
                                    .font(.system(size: 22, weight: .heavy))
                                    .foregroundColor(.primary)
                                Text("one-time payment")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(14)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(SquirrelTheme.brandWarm.opacity(0.4), lineWidth: 1.5)
                        )

                        Button {
                            // Direct checkout URL (LemonSqueezy / Paddle)
                            if let url = URL(string: "https://squirrelapp.lemonsqueezy.com/buy") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "cart.fill")
                                Text("Buy Squirrel Pro License — $19.99")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(SquirrelTheme.brandWarm)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 28)

                    Divider()
                        .padding(.horizontal, 24)

                    // License Key Activation Field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Already purchased a license? Enter your key:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            TextField("e.g. SQR-XXXX-XXXX-XXXX", text: $appState.licenseKeyInput)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                )

                            Button {
                                activateEnteredKey()
                            } label: {
                                Text(appState.isActivatingLicense ? "Verifying..." : "Activate")
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.accentColor)
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .disabled(appState.licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.isActivatingLicense)
                        }

                        if let msg = appState.licenseActivationMessage {
                            HStack(spacing: 6) {
                                Image(systemName: appState.isLicenseSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .foregroundColor(appState.isLicenseSuccess ? .green : .red)
                                    .font(.system(size: 11))
                                Text(msg)
                                    .font(.system(size: 11))
                                    .foregroundColor(appState.isLicenseSuccess ? .green : .red)
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(width: 520, height: 600)
    }

    private func featureRow(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(SquirrelTheme.brandWarm)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
    }

    private func activateEnteredKey() {
        appState.isActivatingLicense = true
        appState.licenseActivationMessage = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let res = LicenseManager.shared.activate(key: appState.licenseKeyInput)
            appState.isLicenseSuccess = res.success
            appState.licenseActivationMessage = res.message
            appState.isActivatingLicense = false

            if res.success {
                appState.isPro = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    dismiss()
                }
            }
        }
    }
}
