//
//  ReadingsRepository.swift
//  DailyReadings
//
//  Created for DailyReadings Catholic Daily Readings App.
//  iOS 17+ | Swift 6+ | SwiftData | Modern Concurrency
//

import Foundation
import SwiftData
import Observation

/// Primary coordinator between offline and online Catholic scripture reading sources.
/// Implements a multi-tier fallback architecture:
/// 1. Primary: Cached NAB readings from SwiftData (`CachedReading`)
/// 2. Secondary: Online Evangelizo API client (`EvangelizioService`)
/// 3. Guaranteed Fallback: Local Douay-Rheims Bible (`BibleDatabase` + `PericoreIndex` + `LiturgicalCalendar`)
@Observable
@MainActor
public final class ReadingsRepository {
    /// Shared singleton instance accessible across the app.
    public static let shared = ReadingsRepository()

    /// Currently loaded readings for UI observation.
    public var currentReadings: DailyReadings?
    /// Whether a fetch operation is actively underway.
    public var isLoading: Bool = false
    /// Last error description encountered (if any, before successful fallback).
    public var lastError: String?
    /// The translation of the currently active readings ("NAB" or "DRB").
    public var activeTranslation: String = "NAB"
    
    // MARK: - Pre-fetching & Offline Cache State
    
    /// Whether NAB offline pre-fetching is currently running.
    public var isPrefetching: Bool = false
    /// Progress of pre-fetching from 0.0 to 1.0.
    public var prefetchProgress: Double = 0.0
    /// Total days targeted for pre-fetching.
    public var prefetchTotal: Int = 30
    /// Current day index being processed during pre-fetching.
    public var prefetchCurrent: Int = 0
    /// User-facing status string describing the current pre-fetch action.
    public var prefetchStatus: String = ""
    /// Total count of days in the next 30 days cached locally for NAB.
    public var cachedNABDaysCount: Int = 0

    // Dependencies
    private var modelContainer: ModelContainer?
    private let bibleDatabase: BibleDatabase
    /// Injected lectionary index for tests. In the app this stays nil and `PericoreIndex.shared`
    /// is used, so the bundled lectionary is not parsed while the app is launching.
    private let injectedPericoreIndex: PericoreIndex?
    private let evangelizioService: EvangelizioService
    private let liturgicalCalendar: LiturgicalCalendar

    /// Designated initializer.
    public init(
        modelContainer: ModelContainer? = nil,
        bibleDatabase: BibleDatabase = .shared,
        pericoreIndex: PericoreIndex? = nil,
        evangelizioService: EvangelizioService = .shared,
        liturgicalCalendar: LiturgicalCalendar = .shared
    ) {
        self.modelContainer = modelContainer
        self.bibleDatabase = bibleDatabase
        self.injectedPericoreIndex = pericoreIndex
        self.evangelizioService = evangelizioService
        self.liturgicalCalendar = liturgicalCalendar
    }

    /// Configures the SwiftData ModelContainer for persistent caching.
    public func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        purgeExpiredCache()
        clearNABCacheFromBuild19Backfill()
        Task { @MainActor in
            self.cachedNABDaysCount = self.countCachedNABDays(daysAhead: 30)
        }
    }

    // MARK: - Main Coordination API

    /// Fetches daily Mass readings for a given date with automatic caching and offline fallback.
    ///
    /// - Parameters:
    ///   - date: The target calendar date.
    ///   - preferredTranslation: "NAB" (online preferred) or "DRB" (offline Douay-Rheims).
    ///   - forceRefresh: NAB only: download again even if the day is cached. If the download fails,
    ///     the cached copy is still used before falling back to WEB-C.
    /// - Returns: A complete `DailyReadings` instance, guaranteed to return readings even if offline.
    @MainActor
    public func getReadings(
        for date: Date,
        preferredTranslation: String = "NAB",
        forceRefresh: Bool = false
    ) async -> DailyReadings {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let dateKey = CachedReading.makeDateKey(from: date)

        // 1. If user prefers NAB: cache, then online, then the cache again (a forced refresh that
        //    failed), then offline WEB-C.
        if preferredTranslation.uppercased() == "NAB" {
            if !forceRefresh, let cached = await cachedNABReadings(for: date, dateKey: dateKey) {
                self.currentReadings = cached
                self.activeTranslation = "NAB"
                return cached
            }

            do {
                let onlineReadings = try await fetchAndVerifyOnlineReadings(for: date)
                self.currentReadings = onlineReadings
                self.activeTranslation = "NAB"
                self.cachedNABDaysCount = countCachedNABDays(daysAhead: 30)
                return onlineReadings
            } catch {
                self.lastError = "Online fetch unavailable: \(error.localizedDescription). Using World English Bible."
            }

            // A refresh that could not reach the server keeps the NAB copy already stored.
            if forceRefresh, let cached = await cachedNABReadings(for: date, dateKey: dateKey) {
                self.currentReadings = cached
                self.activeTranslation = "NAB"
                return cached
            }

            let fallbackReadings = await generateOfflineReadings(for: date, translation: "WEBC")
            self.currentReadings = fallbackReadings
            self.activeTranslation = "WEBC"
            return fallbackReadings
        }

        // 2. Offline Public Domain Translations: WEB-C (Modern Default) or Douay-Rheims (Traditional)
        let offlineTranslation = preferredTranslation.uppercased() == "DRB" ? "DRB" : "WEBC"
        let offlineReadings = await generateOfflineReadings(for: date, translation: offlineTranslation)
        self.currentReadings = offlineReadings
        self.activeTranslation = offlineTranslation
        return offlineReadings
    }

    /// The cached NAB readings for a day, with the Gospel Acclamation added if it is missing, or nil
    /// when nothing usable is cached.
    private func cachedNABReadings(for date: Date, dateKey: String) async -> DailyReadings? {
        guard let cached = fetchFromCache(dateKey: dateKey, translation: "NAB"),
              !cached.readings.contains(where: { $0.citation.book.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return nil
        }
        let liturgicalDay = liturgicalCalendar.liturgicalDay(for: date)
        let completeReadings = await backfillGospelAcclamation(cached.readings, for: liturgicalDay)
        let complete = DailyReadings(
            id: cached.id,
            date: cached.date,
            liturgicalTitle: cached.liturgicalTitle,
            readings: completeReadings,
            translation: "NAB",
            copyright: cached.copyright
        )
        if completeReadings.count != cached.readings.count {
            saveToCache(readings: complete, translation: "NAB")
        }
        return complete
    }

    /// Fetches NAB readings from the Evangelizo API, fills in a missing citation or psalm response from
    /// the lectionary index, adds the Gospel Acclamation (see `backfillGospelAcclamation`), and caches the day.
    @discardableResult
    public func fetchAndVerifyOnlineReadings(for date: Date) async throws -> DailyReadings {
        let onlineReadings = try await evangelizioService.fetchReadings(for: date)
        
        let liturgicalDay = liturgicalCalendar.liturgicalDay(for: date)
        let lectionaryEntries = await lectionaryEntries(for: liturgicalDay)
        
        let verifiedReadings = onlineReadings.readings.map { reading -> Reading in
            let match = lectionaryEntries.first(where: { $0.type == reading.type })
            let citation = reading.citation.book.trimmingCharacters(in: .whitespaces).isEmpty && match != nil
                ? match!.citation
                : reading.citation
            let response = (reading.response?.isEmpty == false ? reading.response : nil)
                ?? match?.response
                ?? (reading.type == .responsorialPsalm ? PsalmResponseProvider.response(for: citation, text: reading.text) : nil)
            
            return Reading(
                id: reading.id,
                type: reading.type,
                citation: citation,
                text: reading.text,
                response: response,
                translation: "NAB"
            )
        }
        
        let completeReadings = await backfillGospelAcclamation(verifiedReadings, for: liturgicalDay)
        
        let finalDailyReadings = DailyReadings(
            id: onlineReadings.id,
            date: onlineReadings.date,
            liturgicalTitle: onlineReadings.liturgicalTitle,
            readings: completeReadings,
            translation: "NAB"
        )

        // Cache successful verified response in SwiftData
        saveToCache(readings: finalDailyReadings, translation: "NAB")
        return finalDailyReadings
    }

    // MARK: - Offline Pre-fetching Engine

    /// Calculates how many days within the next `daysAhead` window currently have unexpired NAB readings stored locally.
    @MainActor
    public func countCachedNABDays(daysAhead: Int = 30) -> Int {
        guard let container = modelContainer else { return 0 }
        let context = ModelContext(container)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let endDate = calendar.date(byAdding: .day, value: daysAhead, to: today) else { return 0 }

        let startKey = CachedReading.makeDateKey(from: today)
        let endKey = CachedReading.makeDateKey(from: endDate)
        let cutoff = Date().addingTimeInterval(-90 * 86400)

        let descriptor = FetchDescriptor<CachedReading>(
            predicate: #Predicate { $0.translation == "NAB" && $0.dateKey >= startKey && $0.dateKey < endKey && $0.fetchedAt >= cutoff }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Pre-fetches and caches the next `daysAhead` days of NAB Mass readings into local SwiftData storage.
    ///
    /// Respects server etiquette with gentle 120ms pauses between days and reports live progress.
    /// Skips any days that are already cached and valid.
    ///
    /// - Parameter daysAhead: The number of days ahead to ensure are cached (default: 30).
    /// - Returns: The number of newly downloaded and saved days.
    @MainActor
    @discardableResult
    public func prefetchNABReadings(daysAhead: Int = 30) async -> Int {
        guard !isPrefetching else { return 0 }

        isPrefetching = true
        prefetchProgress = 0.0
        prefetchTotal = daysAhead
        prefetchCurrent = 0
        prefetchStatus = "Checking offline cache..."

        defer {
            isPrefetching = false
            self.cachedNABDaysCount = countCachedNABDays(daysAhead: daysAhead)
            prefetchProgress = 1.0
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var newlyFetched = 0
        var failedCount = 0

        for offset in 0..<daysAhead {
            if Task.isCancelled { break }
            guard let targetDate = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let key = CachedReading.makeDateKey(from: targetDate)

            prefetchCurrent = offset + 1
            prefetchProgress = Double(offset + 1) / Double(daysAhead)

            // If already cached and valid, add the Gospel Acclamation if it is missing and skip the network fetch
            if let cachedReadings = fetchFromCache(dateKey: key, translation: "NAB") {
                let hasMissing = cachedReadings.readings.contains { $0.citation.book.trimmingCharacters(in: .whitespaces).isEmpty }
                let liturgicalDay = liturgicalCalendar.liturgicalDay(for: targetDate)
                let completeReadings = await backfillGospelAcclamation(cachedReadings.readings, for: liturgicalDay)
                if completeReadings.count != cachedReadings.readings.count {
                    let updated = DailyReadings(
                        id: cachedReadings.id,
                        date: cachedReadings.date,
                        liturgicalTitle: cachedReadings.liturgicalTitle,
                        readings: completeReadings,
                        translation: "NAB",
                        copyright: cachedReadings.copyright
                    )
                    saveToCache(readings: updated, translation: "NAB")
                }
                if !hasMissing {
                    continue
                }
            }

            let dateLabel = targetDate.formatted(.dateTime.month(.abbreviated).day())
            prefetchStatus = "Downloading readings for \(dateLabel)..."

            do {
                _ = try await fetchAndVerifyOnlineReadings(for: targetDate)
                newlyFetched += 1
                self.cachedNABDaysCount = countCachedNABDays(daysAhead: daysAhead)
                // Polite delay between API calls to avoid server rate limits
                try? await Task.sleep(nanoseconds: 120_000_000)
            } catch {
                failedCount += 1
                continue
            }
        }

        if Task.isCancelled {
            prefetchStatus = "Download cancelled."
        } else if newlyFetched > 0 {
            prefetchStatus = "Downloaded \(newlyFetched) days of readings."
        } else if failedCount > 0 {
            prefetchStatus = "Network unavailable. Could not download readings."
        } else {
            prefetchStatus = "All \(daysAhead) days are up to date."
        }
        return newlyFetched
    }

    /// Automatically triggers a background pre-fetch if fewer than 14 days of NAB readings are cached locally.
    @MainActor
    public func triggerBackgroundPrefetchIfNeeded() {
        guard !isPrefetching else { return }
        let cached = countCachedNABDays(daysAhead: 30)
        self.cachedNABDaysCount = cached

        if cached < 14 {
            Task(priority: .utility) { [weak self] in
                await self?.prefetchNABReadings(daysAhead: 30)
            }
        }
    }

    /// The Verse of the Day for a reminder, the same verse the Today screen shows for that day.
    ///
    /// `VerseOfTheDayProvider` takes the Gospel Acclamation whenever it has one of a usable length, so
    /// only that reading is read here; the whole Mass is built only when the verse comes from elsewhere
    /// (no acclamation, or one too short or long). NAB readers get the cached NAB day when there is one,
    /// and the World English Bible otherwise.
    public func verseOfTheDay(for date: Date, preferredTranslation: String) async -> VerseOfTheDay {
        let normalized = preferredTranslation.uppercased()
        if normalized.contains("NAB"),
           let cached = await cachedNABReadings(for: date, dateKey: CachedReading.makeDateKey(from: date)) {
            return VerseOfTheDayProvider.verse(from: cached, date: date)
        }
        let translation = normalized.contains("DOUAY") || normalized.contains("DRB") ? "DRB" : "WEBC"
        let liturgicalDay = liturgicalCalendar.liturgicalDay(for: date)

        if let acclamation = await lectionaryEntries(for: liturgicalDay).first(where: { $0.type == .gospelAcclamation }) {
            let db = translation == "DRB" ? BibleDatabase.drb : BibleDatabase.webc
            let text = await db.formattedText(for: await db.queryVerses(citation: acclamation.citation))
            let reading = Reading(type: .gospelAcclamation, citation: acclamation.citation, text: text, response: acclamation.response, translation: translation)
            let partial = DailyReadings(date: date, liturgicalTitle: liturgicalDay.title, readings: [reading], translation: translation)
            let verse = VerseOfTheDayProvider.verse(from: partial, date: date)
            if verse.theme == VerseOfTheDayProvider.acclamationTheme {
                return verse
            }
        }
        return VerseOfTheDayProvider.verse(from: await generateOfflineReadings(for: date, translation: translation), date: date)
    }

    /// Directly generates offline Catholic Mass readings without performing any network requests.
    public func getOfflineReadings(for date: Date, translation: String = "WEBC") async -> DailyReadings {
        return await generateOfflineReadings(for: date, translation: translation)
    }

    // MARK: - Offline Generation Pipeline

    /// Adds the day's Gospel Acclamation to NAB readings from the online feed, which never carries one.
    ///
    /// Only the acclamation is added, and only when the feed's Gospel is the Lectionary's Gospel for
    /// this day. When they differ the feed carries a different Mass (a weekday where the app keeps a
    /// solemnity, a vigil), and anything taken from the index would not belong to it. The acclamation
    /// is read from the bundled World English Bible and labelled WEB-C, because it is not NAB text.
    public func backfillGospelAcclamation(_ readings: [Reading], for liturgicalDay: LiturgicalDay) async -> [Reading] {
        guard !readings.contains(where: { $0.type == .gospelAcclamation }),
              let gospelIndex = readings.firstIndex(where: { $0.type == .gospel }) else { return readings }

        let entries = await lectionaryEntries(for: liturgicalDay)
        let feedGospel = readings[gospelIndex].citation
        guard entries.contains(where: { $0.type == .gospel && Self.citesSameReading($0.citation, feedGospel) }),
              let acclamation = entries.first(where: { $0.type == .gospelAcclamation }) else { return readings }

        let verses = await BibleDatabase.webc.queryVerses(citation: acclamation.citation)
        let text = await BibleDatabase.webc.formattedText(for: verses)
        guard !text.isEmpty else { return readings }

        var result = readings
        result.insert(
            Reading(
                type: .gospelAcclamation,
                citation: acclamation.citation,
                text: text,
                response: acclamation.response,
                translation: "WEBC"
            ),
            at: gospelIndex
        )
        return result
    }

    /// Whether two citations are the same reading: same book, chapter and first verse. Looser than the
    /// citation text on purpose, because sources spell the same reading differently ("Lk 18:1-8",
    /// "Luke 18:1-8", a long form "4:12-23 or 4:12-17").
    nonisolated static func citesSameReading(_ a: ReadingCitation, _ b: ReadingCitation) -> Bool {
        func identity(_ citation: ReadingCitation) -> String {
            let book = BibleBook.find(named: citation.book).map { "\($0.rawValue)" } ?? citation.book.lowercased()
            let firstVerse = citation.verses.drop { !$0.isNumber }.prefix { $0.isNumber }
            return "\(book):\(citation.chapter ?? 0):\(firstVerse)"
        }
        return identity(a) == identity(b)
    }

    /// Looks up the day's lectionary entries off the main actor. The first call parses the
    /// bundled lectionary files, which is too slow to do on the main thread.
    private func lectionaryEntries(for day: LiturgicalDay) async -> [LectionaryEntry] {
        let injected = injectedPericoreIndex
        return await Task.detached(priority: .userInitiated) {
            (injected ?? PericoreIndex.shared).entries(for: day)
        }.value
    }

    private func generateOfflineReadings(for date: Date, translation: String = "WEBC") async -> DailyReadings {
        let liturgicalDay = liturgicalCalendar.liturgicalDay(for: date)
        let entries = await lectionaryEntries(for: liturgicalDay)
        let isDRB = translation.uppercased() == "DRB"
        let db = isDRB ? BibleDatabase.drb : BibleDatabase.webc
        let translationCode = isDRB ? "DRB" : "WEBC"
        let translationName = isDRB ? "Douay-Rheims" : "World English Bible (Catholic Edition)"
        let copyrightNotice = isDRB
            ? "Douay-Rheims Bible (Challoner Revision, 1752), public domain. Translated from the Latin Vulgate."
            : "World English Bible (Catholic edition), public domain. Private devotional reading; not the liturgical text read at Mass."

        var readings: [Reading] = []

        for entry in entries {
            let formattedText: String
            if entry.type == .responsorialPsalm {
                formattedText = await db.formattedPsalmText(citation: entry.citation)
            } else {
                let verses = await db.queryVerses(citation: entry.citation)
                formattedText = await db.formattedText(for: verses)
            }

            let text = formattedText.isEmpty
                ? "[\(entry.citation.displayReference) — \(translationName) offline text.]"
                : formattedText

            let reading = Reading(
                type: entry.type,
                citation: entry.citation,
                text: text,
                response: entry.response,
                translation: translationCode
            )
            readings.append(reading)
        }

        return DailyReadings(
            date: date,
            liturgicalTitle: liturgicalDay.title,
            readings: readings,
            translation: translationCode,
            copyright: copyrightNotice
        )
    }

    // MARK: - SwiftData Persistence Helpers

    private func fetchFromCache(dateKey: String, translation: String) -> DailyReadings? {
        guard let container = modelContainer else { return nil }
        let context = ModelContext(container)

        var descriptor = FetchDescriptor<CachedReading>(
            predicate: #Predicate { $0.dateKey == dateKey && $0.translation == translation }
        )
        descriptor.fetchLimit = 1

        do {
            let results = try context.fetch(descriptor)
            guard let cached = results.first, !cached.isExpired else { return nil }
            return try cached.decodeReadings()
        } catch {
            return nil
        }
    }

    private func saveToCache(readings: DailyReadings, translation: String) {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)

        do {
            let key = CachedReading.makeDateKey(from: readings.date)
            var descriptor = FetchDescriptor<CachedReading>(
                predicate: #Predicate { $0.dateKey == key }
            )
            descriptor.fetchLimit = 1

            if let existing = try context.fetch(descriptor).first {
                existing.translation = translation
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                existing.readingsJSON = try encoder.encode(readings)
                existing.fetchedAt = .now
            } else {
                let cached = try CachedReading.create(from: readings, translation: translation)
                context.insert(cached)
            }
            try context.save()
        } catch {
            // Non-critical caching error: ignore and proceed
        }
    }

    /// Build 19 filled in any reading type the NAB feed lacked, from WEB-C text labelled NAB, even when
    /// the feed carried a different Mass. Those days are cached; drop them once so they download again.
    static let nabCacheClearedKey = "nabCacheClearedAfterBuild19Backfill"

    private func clearNABCacheFromBuild19Backfill() {
        let key = Self.nabCacheClearedKey
        guard let container = modelContainer, !UserDefaults.standard.bool(forKey: key) else { return }
        let context = ModelContext(container)
        do {
            try context.delete(model: CachedReading.self, where: #Predicate { $0.translation == "NAB" })
            try context.save()
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            // Try again at the next launch.
        }
    }

    /// Removes expired readings (older than 90 days) from SwiftData cache.
    public func purgeExpiredCache() {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        let cutoff = Date().addingTimeInterval(-90 * 86400)

        let descriptor = FetchDescriptor<CachedReading>(
            predicate: #Predicate { $0.fetchedAt < cutoff }
        )
        if let expired = try? context.fetch(descriptor) {
            for item in expired {
                context.delete(item)
            }
            try? context.save()
        }
    }
}

// MARK: - Devotional Scripture Bookmarks

/// Represents a saved/bookmarked scripture passage for personal meditation and devotional reflection.
public struct SavedBookmark: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let readingId: UUID
    public let date: Date
    public let liturgicalTitle: String
    public let readingType: ReadingType
    public let citation: ReadingCitation
    public let text: String
    public let response: String?
    public let translation: String
    public let savedAt: Date

    public init(
        id: UUID = UUID(),
        reading: Reading,
        date: Date = .now,
        liturgicalTitle: String,
        savedAt: Date = .now
    ) {
        self.id = id
        self.readingId = reading.id
        self.date = date
        self.liturgicalTitle = liturgicalTitle
        self.readingType = reading.type
        self.citation = reading.citation
        self.text = reading.text
        self.response = reading.response
        self.translation = reading.translation
        self.savedAt = savedAt
    }

    /// Converts this saved bookmark back into a Reading model for reader presentation or audio playback.
    public var asReading: Reading {
        Reading(
            id: readingId,
            type: readingType,
            citation: citation,
            text: text,
            response: response,
            translation: translation
        )
    }
}

/// Service managing devotional bookmarks of beloved Catholic Mass readings and Psalms.
@Observable
@MainActor
public final class BookmarkManager {
    public static let shared = BookmarkManager()

    private static let storageKey = "savedScriptureBookmarks"

    public private(set) var bookmarks: [SavedBookmark] = []

    public init() {
        loadBookmarks()
    }

    public func isBookmarked(reading: Reading) -> Bool {
        bookmarks.contains { $0.readingId == reading.id || ($0.citation == reading.citation && $0.readingType == reading.type) }
    }

    public func toggleBookmark(reading: Reading, date: Date = .now, liturgicalTitle: String = "") {
        if let index = bookmarks.firstIndex(where: { $0.readingId == reading.id || ($0.citation == reading.citation && $0.readingType == reading.type) }) {
            bookmarks.remove(at: index)
        } else {
            let newBookmark = SavedBookmark(
                reading: reading,
                date: date,
                liturgicalTitle: liturgicalTitle.isEmpty ? reading.type.displayTitle : liturgicalTitle
            )
            bookmarks.insert(newBookmark, at: 0)
        }
        saveBookmarks()
    }

    public func removeBookmark(at offsets: IndexSet) {
        bookmarks.remove(atOffsets: offsets)
        saveBookmarks()
    }

    public func removeBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        saveBookmarks()
    }

    private func loadBookmarks() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            self.bookmarks = try decoder.decode([SavedBookmark].self, from: data)
        } catch {
            print("Failed to load bookmarks: \(error)")
        }
    }

    private func saveBookmarks() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(bookmarks)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            print("Failed to save bookmarks: \(error)")
        }
    }
}
