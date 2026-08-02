//
//  ReveilApp.swift
//  Reveil
//
//  Created by Lessica on 2023/10/2.
//

import SwiftUI

@main
struct ReveilApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() { _ = PinStorage.shared }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onChange(of: scenePhase) { phase in
                    guard phase == .active else { return }
                    NetworkAddressModel.shared.refresh()
                }
                .onOpenURL { url in
                    // The home screen widget opens reveil://dashboard.
                    guard url.scheme == "reveil", url.host == "dashboard" else { return }
                    AppNavigation.shared.selectedTab = .dashboard
                    NetworkAddressModel.shared.refresh(force: true)
                }
        }
    }
}
