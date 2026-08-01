//
//  ReveilApp.swift
//  Reveil
//
//  Created by Lessica on 2023/10/2.
//

import SwiftUI

@main
struct ReveilApp: App {
    init() { _ = PinStorage.shared }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // The home screen widget opens reveil://dashboard.
                    guard url.scheme == "reveil" else { return }
                    if url.host == "dashboard" {
                        AppNavigation.shared.selectedTab = .dashboard
                    }
                }
        }
    }
}
