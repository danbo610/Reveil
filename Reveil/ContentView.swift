//
//  ContentView.swift
//  Reveil
//
//  Created by Lessica on 2023/10/2.
//

import SwiftUI

/// Which tab is showing. Held outside the view so that a deep link handled by the app can switch
/// tabs — SwiftUI's TabView only restores its own state on a cold launch, and the widget usually
/// lands on an app that is already running.
final class AppNavigation: ObservableObject {
    static let shared = AppNavigation()

    enum Tab: Int {
        case dashboard, details, about
    }

    @Published var selectedTab: Tab = .dashboard

    private init() {}
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var useTabs: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        if useTabs {
            TabsView()
        } else {
            SidebarView()
        }
    }
}

struct TabsView: View {
    @ObservedObject private var navigation = AppNavigation.shared

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            NavigationView {
                DashboardView()
                    .navigationBarAttachBrand()
                    .background(ColorfulBackground())
            }
            .tabItem {
                Label(NSLocalizedString("DASHBOARD", comment: "Dashboard"), systemImage: "square.grid.2x2")
            }
            .tag(AppNavigation.Tab.dashboard)

            NavigationView {
                DetailsView()
                    .navigationBarAttachBrand()
            }
            .tabItem {
                Label(NSLocalizedString("DETAILS", comment: "Details"), systemImage: "doc.text")
            }
            .tag(AppNavigation.Tab.details)

            NavigationView {
                AboutView()
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label(NSLocalizedString("ABOUT", comment: "About"), systemImage: "info.circle")
            }
            .tag(AppNavigation.Tab.about)
        }
    }
}

struct SidebarView: View {
    var body: some View {
        NavigationView {
            List {
                Section(NSLocalizedString("DASHBOARD", comment: "Dashboard")) {
                    NavigationLink {
                        DashboardView()
                            .navigationTitle(NSLocalizedString("DASHBOARD", comment: "Dashboard"))
                            .background(ColorfulBackground())
                    } label: {
                        Label(NSLocalizedString("DASHBOARD", comment: "Dashboard"), systemImage: "square.grid.2x2")
                    }
                }

                Section(NSLocalizedString("DETAILS", comment: "Details")) {
                    DetailsView.createDetailsList()
                }

                Section(NSLocalizedString("ABOUT", comment: "About")) {
                    NavigationLink {
                        AboutView()
                            .background(ColorfulBackground())
                    } label: {
                        Label(NSLocalizedString("ABOUT", comment: "About"), systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Reveil", comment: "Reveil"))

            DashboardView()
                .navigationTitle(NSLocalizedString("DASHBOARD", comment: "Dashboard"))
                .background(ColorfulBackground())
        }
        .listStyle(SidebarListStyle())
    }
}

// MARK: - Previews

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
