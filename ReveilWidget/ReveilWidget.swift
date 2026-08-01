//
//  ReveilWidget.swift
//  ReveilWidget
//
//  A home screen widget showing the three public addresses side by side: the one domestic sites
//  see, the one ordinary foreign sites see, and the one sites that need a proxy see. Whether they
//  agree tells you at a glance what your routing rules are actually doing.
//

import SwiftUI
import WidgetKit

struct NetworkAddressEntry: TimelineEntry {
    let date: Date
    let addresses: NetworkAddresses
}

struct NetworkAddressTimelineProvider: TimelineProvider {
    // How long before the widget asks for fresh addresses. Widgets are refreshed at the system's
    // discretion anyway; this is the earliest we would like it to happen.
    private static let refreshInterval: TimeInterval = 15 * 60

    func placeholder(in _: Context) -> NetworkAddressEntry {
        NetworkAddressEntry(date: Date(), addresses: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (NetworkAddressEntry) -> Void) {
        // The gallery preview must not wait on the network.
        if context.isPreview {
            completion(NetworkAddressEntry(date: Date(), addresses: .placeholder))
            return
        }
        Task {
            completion(NetworkAddressEntry(date: Date(), addresses: await NetworkAddressProvider.current()))
        }
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<NetworkAddressEntry>) -> Void) {
        Task {
            let entry = NetworkAddressEntry(date: Date(), addresses: await NetworkAddressProvider.current())
            let next = Date().addingTimeInterval(Self.refreshInterval)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

private struct AddressRow: View {
    let symbol: String
    let tint: Color
    let address: NetworkAddress?
    let compact: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 22 : 28, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: compact ? 26 : 34)

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 0) {
                Text(address?.address ?? "—")
                    .font(.system(size: compact ? 19 : 26, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    // IPv4 runs to fifteen characters; let it shrink rather than truncate.
                    .minimumScaleFactor(0.4)
                Text(address?.location ?? "无法访问")
                    .font(.system(size: compact ? 12 : 15))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }
}

struct NetworkAddressWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NetworkAddressEntry

    private var compact: Bool { family == .systemSmall }

    var body: some View {
        // Deliberately no .frame(maxHeight: .infinity) on the rows. That made each of them ask
        // for unbounded height, and the widget archiver rejected the result with
        // WidgetArchiver.ValidationError — the tile rendered blank. Larger type fills the tile
        // instead, which the archiver is happy with.
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            AddressRow(symbol: "house.fill", tint: .blue,
                       address: entry.addresses.domestic, compact: compact)
            AddressRow(symbol: "globe.americas.fill", tint: .green,
                       address: entry.addresses.foreign, compact: compact)
            AddressRow(symbol: "lock.shield.fill", tint: .orange,
                       address: entry.addresses.blocked, compact: compact)
        }
        .padding(.horizontal, compact ? 10 : 14)
        .padding(.vertical, compact ? 8 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .widgetContainerBackground()
    }
}

private extension View {
    // iOS 17 requires a declared container background or the widget renders without one; the API
    // does not exist before that, so both paths are kept.
    @ViewBuilder
    func widgetContainerBackground() -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(.fill.tertiary, for: .widget)
        } else {
            self
        }
    }
}

struct NetworkAddressWidget: Widget {
    private let kind = NetworkAddressProvider.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NetworkAddressTimelineProvider()) { entry in
            // The URL rides along with the rendered snapshot, so a tile still showing an older
            // render opens the app without one — outermost placement is the documented spot.
            NetworkAddressWidgetView(entry: entry)
                .widgetURL(URL(string: "reveil://dashboard"))
        }
        .configurationDisplayName("IP 地址")
        .description("显示国内、未墙与被墙线路各自使用的公网 IP。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct ReveilWidgetBundle: WidgetBundle {
    var body: some Widget {
        NetworkAddressWidget()
    }
}
