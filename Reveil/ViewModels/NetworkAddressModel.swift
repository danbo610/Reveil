//
//  NetworkAddressModel.swift
//  Reveil
//
//  Backs the dashboard's address card. The lookups go out over the network, so they are throttled
//  and never repeated while one is already running — the dashboard rebuilds its views on every
//  tick of the global timer.
//

import Foundation

@MainActor
final class NetworkAddressModel: ObservableObject {
    static let shared = NetworkAddressModel()

    @Published private(set) var addresses = NetworkAddresses(local: NetworkAddressProvider.localAddress)
    @Published private(set) var isRefreshing = false

    private var lastRefresh: Date?
    private static let refreshInterval: TimeInterval = 300

    private init() {}

    func refreshIfStale() {
        guard !isRefreshing else { return }
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < Self.refreshInterval {
            // The local address costs nothing and can change without a lookup, so keep it current.
            addresses.local = NetworkAddressProvider.localAddress
            return
        }

        isRefreshing = true
        Task {
            let fetched = await NetworkAddressProvider.current()
            addresses = fetched
            lastRefresh = Date()
            isRefreshing = false
        }
    }
}
