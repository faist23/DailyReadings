//
//  TodayViewModel.swift
//  DailyReadings
//
//  Created for DailyReadings Catholic Daily Readings App.
//  iOS 17+ | Swift 6+
//

import SwiftUI
import SwiftData
import Observation

/// View model managing today's Catholic daily Mass readings, liturgical day context,
/// and Saint of the Day.
///
/// Implements the iOS 17 `@Observable` pattern and modern Swift concurrency.
/// Wired to the real LiturgicalCalendar engine, ReadingsRepository, and SaintsDatabase.
@Observable
@MainActor
public final class TodayViewModel {
    
    // MARK: - State Properties
    
    /// The Mass readings for the loaded day.
    public var dailyReadings: DailyReadings?
    
    /// The liturgical day information (season, rank, liturgical color, week).
    public var liturgicalDay: LiturgicalDay?
    
    /// The Saint of the Day commemorated on this date, if any.
    public var saint: Saint?
    
    /// Indicates whether readings are currently being loaded.
    public var isLoading: Bool = false
    
    /// An optional error message if loading fails.
    public var error: String?
    
    /// The date currently displayed.
    public var currentDate: Date = .now
    
    /// The reading currently selected for detail presentation.
    public var selectedReading: Reading?

    /// Set when the New American Bible was chosen but could not be downloaded or found in the
    /// offline cache, so the readings shown are the World English Bible.
    public var translationNotice: String?

    /// The settings that decide which readings a day gets. A screen that reappears with different
    /// settings (changed in the Settings tab) reloads; see `reloadIfSettingsChanged()`.
    struct ReadingSettings: Equatable {
        let translation: String
        let ascensionOnThursday: Bool

        static var current: ReadingSettings {
            let preference = UserDefaults.standard.string(forKey: "bibleTranslation") ?? "World English Bible (WEB-C)"
            let translation: String
            if preference.contains("NAB") {
                translation = "NAB"
            } else if preference.contains("Douay") || preference.contains("DRB") {
                translation = "DRB"
            } else {
                translation = "WEBC"
            }
            return ReadingSettings(
                translation: translation,
                ascensionOnThursday: UserDefaults.standard.bool(forKey: "ascensionOnThursday")
            )
        }
    }

    /// The settings the current readings were loaded with.
    @ObservationIgnored private var loadedSettings: ReadingSettings?

    static let nabUnavailableNotice = "The New American Bible could not be downloaded, so these are the World English Bible readings."
    
    // MARK: - Dependencies
    
    /// The readings repository providing multi-tier offline/online scripture fetching.
    private var readingsRepository: ReadingsRepository?
    
    /// The liturgical calendar engine for computing feast days, seasons, and ranks.
    private let liturgicalCalendar: LiturgicalCalendar
    
    /// The saints database for looking up commemorated saints by date.
    private let saintsDatabase: SaintsDatabase
    
    // MARK: - Initialization
    
    /// Designated initializer with dependency injection.
    ///
    /// - Parameters:
    ///   - readingsRepository: The repository for fetching readings. Can be set later via `configure(repository:)`.
    ///   - liturgicalCalendar: The liturgical computation engine (defaults to shared singleton).
    ///   - saintsDatabase: The saints lookup database (defaults to shared singleton).
    public init(
        readingsRepository: ReadingsRepository? = nil,
        liturgicalCalendar: LiturgicalCalendar = .shared,
        saintsDatabase: SaintsDatabase = .shared
    ) {
        self.readingsRepository = readingsRepository ?? .shared
        self.liturgicalCalendar = liturgicalCalendar
        self.saintsDatabase = saintsDatabase
    }
    
    /// Configures the readings repository after initialization (e.g., when modelContainer becomes available).
    public func configure(repository: ReadingsRepository) {
        self.readingsRepository = repository
    }
    
    // MARK: - Public Methods
    
    /// Loads the liturgical day, Mass readings, and saint for the given date.
    ///
    /// - Parameter date: The target date for which to fetch readings (defaults to now).
    public func loadReadings(for date: Date = .now, forceRefresh: Bool = false) async {
        isLoading = true
        error = nil
        currentDate = date
        
        defer {
            isLoading = false
        }
        
        if Task.isCancelled { return }

        // 1. Compute liturgical day from the real engine
        let day = liturgicalCalendar.liturgicalDay(for: date)
        self.liturgicalDay = day
        
        // 2. Fetch readings via ReadingsRepository (honoring user's preferred translation)
        let settings = ReadingSettings.current
        let targetTranslation = settings.translation
        let repository = readingsRepository ?? ReadingsRepository()
        let readings = await repository.getReadings(for: date, preferredTranslation: targetTranslation, forceRefresh: forceRefresh)
        if Task.isCancelled { return }
        self.dailyReadings = readings
        self.loadedSettings = settings
        // Say so when NAB was chosen but the readings are another translation (offline, no cached copy).
        self.translationNotice = targetTranslation == "NAB" && readings.translation != "NAB"
            ? Self.nabUnavailableNotice
            : nil
        if targetTranslation == "NAB", readingsRepository != nil {
            repository.triggerBackgroundPrefetchIfNeeded()
        }
        
        // 3. Look up the Saint of the Day or Solemnity/Feast blurb
        self.saint = saintsDatabase.saint(for: date, liturgicalDay: self.liturgicalDay)
    }
    
    /// Reloads the day, downloading NAB again instead of using the cached copy.
    /// Keeps the readings on screen while it works; a failed download keeps the cached NAB if there is one.
    public func refresh() async {
        await loadReadings(for: currentDate, forceRefresh: true)
    }

    /// Reloads the day if the translation or the Ascension setting changed since it was loaded.
    /// Called when a screen reappears, e.g. after a visit to the Settings tab.
    public func reloadIfSettingsChanged() async {
        guard let loadedSettings, loadedSettings != ReadingSettings.current else { return }
        await loadReadings(for: currentDate)
    }
    
    /// Clears any active error banner.
    public func clearError() {
        self.error = nil
    }
}
