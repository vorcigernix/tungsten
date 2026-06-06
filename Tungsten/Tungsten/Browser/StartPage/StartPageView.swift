import SwiftUI

/// Native Tungsten start page. Adaptive (light/dark) background, monogram
/// Favorites tiles, and Frequently Visited derived from real history. No
/// brand-colored clones, no hardcoded scenery — everything uses semantic
/// system colors so it follows the system appearance and accent.
struct StartPageView: View {
    let isPrivate: Bool
    let historyStore: HistoryStore
    /// Top inset so content clears the floating glass chrome.
    var topInset: CGFloat = ChromeMetrics.barHeight
    let onOpen: (String) -> Void

    var body: some View {
        ZStack {
            StartPageBackground(isPrivate: isPrivate)

            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    if isPrivate {
                        PrivateBrowsingCard()
                    } else {
                        if defaultFavorites.isEmpty == false {
                            StartSection(title: "Favorites") {
                                StartTileGrid(links: defaultFavorites, onOpen: onOpen)
                            }
                        }

                        let frequent = frequentlyVisited(limit: 8)
                        if frequent.isEmpty == false {
                            StartSection(title: "Frequently Visited") {
                                StartTileGrid(links: frequent, onOpen: onOpen)
                            }
                        }
                    }
                }
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 32)
                .padding(.top, topInset + 32)
                .padding(.bottom, 64)
            }
        }
    }

    private var defaultFavorites: [StartLink] {
        [
            StartLink(title: "Apple", urlString: "https://www.apple.com"),
            StartLink(title: "DuckDuckGo", urlString: "https://duckduckgo.com"),
            StartLink(title: "Wikipedia", urlString: "https://www.wikipedia.org"),
            StartLink(title: "GitHub", urlString: "https://github.com"),
            StartLink(title: "Hacker News", urlString: "https://news.ycombinator.com"),
            StartLink(title: "Developer", urlString: "https://developer.apple.com")
        ]
    }

    /// Most-visited sites grouped by host. `historyStore.entries` is
    /// most-recent-first, so the first entry seen per host is its newest.
    private func frequentlyVisited(limit: Int) -> [StartLink] {
        var counts: [String: Int] = [:]
        var newest: [String: HistoryEntry] = [:]

        for entry in historyStore.entries {
            guard let host = URLComponents(string: entry.urlString)?.host else {
                continue
            }
            counts[host, default: 0] += 1
            if newest[host] == nil {
                newest[host] = entry
            }
        }

        return counts
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .compactMap { host, _ -> StartLink? in
                guard let entry = newest[host] else { return nil }
                let title = entry.title.isEmpty ? host : entry.title
                return StartLink(title: title, urlString: entry.urlString)
            }
    }
}

struct StartLink: Identifiable {
    let id = UUID()
    let title: String
    let urlString: String

    var monogram: String {
        let source: String
        if let host = URLComponents(string: urlString)?.host {
            source = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        } else {
            source = title
        }
        return String(source.first ?? "?").uppercased()
    }
}

private struct StartSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            content
        }
    }
}

private struct StartTileGrid: View {
    let links: [StartLink]
    let onOpen: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 84, maximum: 112), spacing: 22)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
            ForEach(links) { link in
                StartTile(link: link) { onOpen(link.urlString) }
            }
        }
    }
}

private struct StartTile: View {
    let link: StartLink
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.quaternary)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                        }

                    Text(link.monogram)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 72, height: 72)
                .overlay {
                    if isHovering {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.accentColor.opacity(0.14))
                    }
                }

                Text(link.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 96)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(link.urlString)
        .onHover { isHovering = $0 }
    }
}

private struct PrivateBrowsingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Private Browsing")
                .font(.title.weight(.bold))
                .foregroundStyle(.primary)

            Text("Tungsten won't remember the pages you visit, your search history, or your AutoFill information in this window.")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460, alignment: .leading)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .padding(.top, 40)
    }
}

/// Adaptive backdrop with a restrained, system-accent glow. Opaque so the
/// glass chrome samples it (rather than the desktop) over the start page.
private struct StartPageBackground: View {
    let isPrivate: Bool

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            RadialGradient(
                colors: [tintColor.opacity(0.12), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 720
            )
        }
        .ignoresSafeArea()
    }

    private var tintColor: Color {
        isPrivate ? .indigo : .accentColor
    }
}
