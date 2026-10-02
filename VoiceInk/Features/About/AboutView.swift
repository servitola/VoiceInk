import SwiftUI

// Fork-owned replacement for the vendor's LicenseManagementView: the fork is free, so the
// About tab keeps only the version and the useful links. A separate file instead of edits to
// LicenseManagementView, which upstream rewrites often enough to conflict on every rebase.
struct AboutView: View {
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    private let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                resources
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 600, minHeight: 500)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text("VoiceInk")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("Version \(appVersion) (\(appBuild)) · free fork of Beingpax/VoiceInk")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppMaterialCardBackground(cornerRadius: 14))
    }

    private var resources: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Resources")
                .font(.system(size: 20, weight: .semibold, design: .rounded))

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                AboutLinkRow(
                    title: "Recommended Models",
                    subtitle: "Find the best transcription setup",
                    systemImage: "sparkles",
                    url: "https://tryvoiceink.com/recommended-models"
                )
                AboutLinkRow(
                    title: "Documentation",
                    subtitle: "Setup, features, and settings",
                    systemImage: "book.fill",
                    url: "https://tryvoiceink.com/docs"
                )
                AboutLinkRow(
                    title: "Videos & Guides",
                    subtitle: "Walkthroughs and product updates",
                    systemImage: "video.fill",
                    url: "https://www.youtube.com/@tryvoiceink/videos"
                )
                AboutLinkRow(
                    title: "Changelog",
                    subtitle: "Upstream fixes and releases",
                    systemImage: "list.bullet.clipboard.fill",
                    url: "https://github.com/Beingpax/VoiceInk/releases"
                )
                AboutLinkRow(
                    title: "Fork Releases",
                    subtitle: "Builds of this fork",
                    systemImage: "shippingbox.fill",
                    url: "https://github.com/servitola/VoiceInk/releases"
                )
                AboutLinkRow(
                    title: "Report or Feedback",
                    subtitle: "Open an issue on the fork",
                    systemImage: "exclamationmark.bubble.fill",
                    url: "https://github.com/servitola/VoiceInk/issues"
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppMaterialCardBackground(cornerRadius: 14))
    }
}

private struct AboutLinkRow: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let url: String

    var body: some View {
        Button {
            if let target = URL(string: url) {
                NSWorkspace.shared.open(target)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.Text.secondary)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 56)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Surface.subtle)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppTheme.Border.subtle, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
