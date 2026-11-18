//
//  MainTabView.swift
//  DailyReadings
//
//  Created for DailyReadings Catholic Daily Readings App.
//  iOS 17+ | Swift 6+
//

import SwiftUI

/// Main container view providing 3-tab navigation across DailyReadings:
/// Today's readings, Liturgical Calendar, and Settings.
///
/// Dynamically updates the tab bar tint to reflect the active liturgical color.
public struct MainTabView: View {
    
    // MARK: - State & View Models
    
    @State private var selectedTab: Tab = .today
    /// Read so the tab content is rebuilt when the user changes their text size; `Font.scaled`
    /// computes its size when a view body runs.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var todayViewModel: TodayViewModel
    @State private var calendarViewModel = CalendarViewModel()
    
    /// The shared readings repository injected from the app level.
    private let readingsRepository: ReadingsRepository
    
    // MARK: - Tab Item Enum
    
    public enum Tab: Int, Hashable {
        case today = 0
        case calendar = 1
        case prayers = 2
        case settings = 3
    }
    
    // MARK: - Initialization
    
    /// Creates the main tab view with an injected readings repository.
    ///
    /// - Parameter readingsRepository: The repository for fetching scripture readings,
    ///   wired to SwiftData caching, Evangelizo API, and offline Douay-Rheims fallback.
    public init(readingsRepository: ReadingsRepository) {
        self.readingsRepository = readingsRepository
        self._todayViewModel = State(initialValue: TodayViewModel(readingsRepository: readingsRepository))
    }
    
    // MARK: - Body
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Today
            NavigationStack {
                TodayView(viewModel: todayViewModel)
            }
            .tabItem {
                Label("Today", systemImage: selectedTab == .today ? "house.fill" : "house")
            }
            .tag(Tab.today)
            
            // Tab 2: Calendar
            NavigationStack {
                CalendarView(viewModel: calendarViewModel)
            }
            .tabItem {
                Label("Calendar", systemImage: "calendar")
            }
            .tag(Tab.calendar)
            
            // Tab 3: Prayers
            NavigationStack {
                PrayersView(liturgicalColor: todayViewModel.liturgicalDay?.color ?? .green)
            }
            .tabItem {
                Label("Prayers", systemImage: selectedTab == .prayers ? "cross.fill" : "cross")
            }
            .tag(Tab.prayers)
            
            // Tab 4: Settings
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: selectedTab == .settings ? "gearshape.fill" : "gearshape")
            }
            .tag(Tab.settings)
        }
        .id(dynamicTypeSize)
        .tint(tabBarTintColor)
        .task {
            // Today's readings are loaded by TodayView itself, the first tab shown.
            // Reminders and vigil alerts are scheduled 30 days ahead; extend them on every launch.
            await NotificationManager.shared.refreshScheduledNotifications().value
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Permission may have been granted or withdrawn in iOS Settings while the app was away,
            // and on a new day the 30 days of reminders move forward.
            Task {
                let manager = NotificationManager.shared
                let wasAuthorized = manager.isAuthorized
                await manager.checkAuthorization()
                if manager.isAuthorized != wasAuthorized {
                    manager.refreshScheduledNotifications()
                } else {
                    manager.refreshIfStale()
                }
            }
        }
    }
    
    // MARK: - Dynamic Liturgical Tint
    
    /// The accent color for active tab items, reflecting today's liturgical season/day.
    private var tabBarTintColor: Color {
        todayViewModel.liturgicalDay?.color.uiAccentColor ?? LiturgicalColors.green
    }
}

#Preview {
    MainTabView(readingsRepository: ReadingsRepository())
}
