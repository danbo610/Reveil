//
//  NetworkAddressDetailsView.swift
//  Reveil
//

import SwiftUI

struct NetworkAddressDetailsView: View {
    @ObservedObject private var addressModel = NetworkAddressModel.shared
    @StateObject private var detailsModel = NetworkAddressDetailsModel()
    @StateObject private var highlightedEntryKey = HighlightedEntryKey()

    var body: some View {
        ZStack {
            DetailsListView(basicEntries: detailsModel.entries)
                .environmentObject(highlightedEntryKey)

            if detailsModel.entries.isEmpty {
                if detailsModel.isLoading || addressModel.isRefreshing {
                    ProgressView()
                } else {
                    Text(NSLocalizedString(
                        "NO_PUBLIC_IP_ADDRESSES",
                        comment: "No public IP addresses available"
                    ))
                    .font(.system(.body))
                    .foregroundColor(Color(PlatformColor.secondaryLabelAlias))
                    .multilineTextAlignment(.center)
                    .padding()
                }
            }
        }
        .navigationTitle(NSLocalizedString("IP_ADDRESS_DETAILS", comment: "IP Address Details"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if detailsModel.isLoading, !detailsModel.entries.isEmpty {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
        .onAppear {
            detailsModel.load(addresses: addressModel.addresses.publicAddresses)
        }
        .onReceive(addressModel.$addresses) { addresses in
            detailsModel.load(addresses: addresses.publicAddresses)
        }
        .onDisappear {
            detailsModel.cancel()
        }
    }
}

// MARK: - Previews

struct NetworkAddressDetailsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            NetworkAddressDetailsView()
        }
    }
}
