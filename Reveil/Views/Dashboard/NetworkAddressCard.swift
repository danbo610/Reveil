//
//  NetworkAddressCard.swift
//  Reveil
//
//  The dashboard's own version of the home screen widget: the local address plus the three public
//  ones. Sharing NetworkAddressProvider with the widget keeps a single definition of what each
//  row means and how it is parsed.
//

import SwiftUI

struct NetworkAddressCard: View {
    @ObservedObject private var model = NetworkAddressModel.shared

    private struct Row: View {
        let symbol: String
        let tint: Color
        let label: String
        let address: String?
        let location: String?
        let isRefreshing: Bool

        var body: some View {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 24)

                Text(label)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(address ?? (isRefreshing ? "…" : "—"))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let location, !location.isEmpty {
                        Text(location)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(NSLocalizedString("NETWORK_ADDRESSES", comment: "IP Addresses").uppercased())
                    .font(Font.system(.body))
                    .fontWeight(.bold)
                    .foregroundColor(Color(PlatformColor.labelAlias))
                    .lineLimit(1)
                Spacer()
                if model.isRefreshing {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                Image(systemName: "chevron.right")
                    .font(Font.system(.body).weight(.regular))
                    .foregroundColor(Color(PlatformColor.tertiaryLabelAlias))
            }

            Row(symbol: "wifi", tint: .teal,
                label: NSLocalizedString("LAN_ADDRESS", comment: "Intranet"),
                address: model.addresses.local, location: nil,
                isRefreshing: model.isRefreshing)
            Row(symbol: "house.fill", tint: .blue,
                label: NSLocalizedString("DOMESTIC_ADDRESS", comment: "Domestic"),
                address: model.addresses.domestic?.address,
                location: model.addresses.domestic?.location,
                isRefreshing: model.isRefreshing)
            Row(symbol: "globe.americas.fill", tint: .green,
                label: NSLocalizedString("FOREIGN_ADDRESS", comment: "Unblocked"),
                address: model.addresses.foreign?.address,
                location: model.addresses.foreign?.location,
                isRefreshing: model.isRefreshing)
            Row(symbol: "lock.shield.fill", tint: .orange,
                label: NSLocalizedString("BLOCKED_ADDRESS", comment: "Blocked"),
                address: model.addresses.blocked?.address,
                location: model.addresses.blocked?.location,
                isRefreshing: model.isRefreshing)
        }
        .onAppear { model.refresh() }
    }
}

// MARK: - Previews

struct NetworkAddressCard_Previews: PreviewProvider {
    static var previews: some View {
        NetworkAddressCard()
    }
}
