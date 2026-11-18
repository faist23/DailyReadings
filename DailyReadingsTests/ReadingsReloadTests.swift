//
//  ReadingsReloadTests.swift
//  DailyReadingsTests
//
//  Screens reload when the translation or Ascension setting changed while they were away, a pull to
//  refresh that cannot reach the server keeps the cached NAB, and an NAB reader is told when the
//  readings shown are another translation.
//

import XCTest
import SwiftData
@testable import DailyReadings

@MainActor
final class ReadingsReloadTests: XCTestCase {

    /// Saturday 14 November 2026.
    private let date = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 12))!
    private var savedDefaults: [String: Any?] = [:]
    private let keys = ["bibleTranslation", "ascensionOnThursday", ReadingsRepository.nabCacheClearedKey]

    override func setUp() async throws {
        for key in keys { savedDefaults[key] = UserDefaults.standard.object(forKey: key) }
        // The cache tests insert NAB rows; keep the one-time Build 19 clean-up from deleting them.
        UserDefaults.standard.set(true, forKey: ReadingsRepository.nabCacheClearedKey)
    }

    override func tearDown() async throws {
        for (key, value) in savedDefaults {
            if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }

    /// A repository whose NAB server cannot be reached.
    private func offlineRepository(container: ModelContainer? = nil) -> ReadingsRepository {
        let repository = ReadingsRepository(evangelizioService: EvangelizioService(baseURLString: "http://127.0.0.1:9/"))
        if let container { repository.configure(modelContainer: container) }
        return repository
    }

    // MARK: - #7 Pull to refresh and the NAB fallback

    func testRefreshThatCannotReachTheServerKeepsTheCachedNAB() async throws {
        let container = try ModelContainer(for: CachedReading.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let cached = DailyReadings(
            date: date,
            liturgicalTitle: "Saturday of the Thirty-second Week in Ordinary Time",
            readings: [
                Reading(type: .firstReading, citation: ReadingCitation(book: "3 John", chapter: 1, verses: "5-8"), text: "Cached NAB first reading", translation: "NAB"),
                Reading(type: .gospel, citation: ReadingCitation(book: "Luke", chapter: 18, verses: "1-8"), text: "Cached NAB Gospel", translation: "NAB")
            ],
            translation: "NAB"
        )
        let context = ModelContext(container)
        context.insert(try CachedReading.create(from: cached, translation: "NAB"))
        try context.save()

        let readings = await offlineRepository(container: container).getReadings(for: date, preferredTranslation: "NAB", forceRefresh: true)

        XCTAssertEqual(readings.translation, "NAB", "A failed refresh must not replace the cached NAB with WEB-C")
        XCTAssertEqual(readings.readings.first?.text, "Cached NAB first reading")
    }

    func testNABReaderIsToldWhenTheReadingsAreAnotherTranslation() async {
        UserDefaults.standard.set("New American Bible (NAB)", forKey: "bibleTranslation")
        let viewModel = TodayViewModel(readingsRepository: offlineRepository())

        await viewModel.loadReadings(for: date)

        XCTAssertEqual(viewModel.dailyReadings?.translation, "WEBC")
        XCTAssertEqual(viewModel.translationNotice, TodayViewModel.nabUnavailableNotice)
    }

    func testNoNoticeWhenTheChosenTranslationIsShown() async {
        UserDefaults.standard.set("Douay-Rheims", forKey: "bibleTranslation")
        let viewModel = TodayViewModel(readingsRepository: offlineRepository())

        await viewModel.loadReadings(for: date)

        XCTAssertEqual(viewModel.dailyReadings?.translation, "DRB")
        XCTAssertNil(viewModel.translationNotice)
    }

    // MARK: - #5 Reload after a settings change

    func testScreenReloadsWhenTheTranslationChangedWhileItWasAway() async {
        UserDefaults.standard.set("World English Bible (WEB-C)", forKey: "bibleTranslation")
        let viewModel = TodayViewModel(readingsRepository: offlineRepository())
        await viewModel.loadReadings(for: date)
        XCTAssertEqual(viewModel.dailyReadings?.translation, "WEBC")

        UserDefaults.standard.set("Douay-Rheims", forKey: "bibleTranslation")
        await viewModel.reloadIfSettingsChanged()
        XCTAssertEqual(viewModel.dailyReadings?.translation, "DRB")
    }

    func testScreenDoesNotReloadWhenNothingChanged() async {
        UserDefaults.standard.set("World English Bible (WEB-C)", forKey: "bibleTranslation")
        let viewModel = TodayViewModel(readingsRepository: offlineRepository())
        await viewModel.loadReadings(for: date)
        let loadedID = viewModel.dailyReadings?.id

        await viewModel.reloadIfSettingsChanged()
        XCTAssertEqual(viewModel.dailyReadings?.id, loadedID)
    }

    func testScreenReloadsWhenTheAscensionSettingChanged() async {
        // Thursday 6 May 2027: a weekday of Easter, or the Ascension where it is kept on Thursday.
        let ascensionThursday = Calendar.current.date(from: DateComponents(year: 2027, month: 5, day: 6, hour: 12))!
        UserDefaults.standard.set(false, forKey: "ascensionOnThursday")
        let viewModel = TodayViewModel(readingsRepository: offlineRepository())
        await viewModel.loadReadings(for: ascensionThursday)
        XCTAssertFalse(viewModel.liturgicalDay?.title.contains("Ascension") ?? true)

        UserDefaults.standard.set(true, forKey: "ascensionOnThursday")
        await viewModel.reloadIfSettingsChanged()
        XCTAssertTrue(viewModel.liturgicalDay?.title.contains("Ascension") ?? false)
    }

    func testCalendarRecomputesItsDaysWhenTheAscensionSettingChanged() {
        UserDefaults.standard.set(false, forKey: "ascensionOnThursday")
        let viewModel = CalendarViewModel()
        viewModel.currentMonth = Calendar.current.date(from: DateComponents(year: 2027, month: 5, day: 1))!
        viewModel.loadMonth()
        let ascensionThursday = Calendar.current.date(from: DateComponents(year: 2027, month: 5, day: 6))!
        XCTAssertFalse(viewModel.liturgicalDay(for: ascensionThursday)?.title.contains("Ascension") ?? true)

        UserDefaults.standard.set(true, forKey: "ascensionOnThursday")
        viewModel.reloadIfCalendarSettingChanged()
        XCTAssertTrue(viewModel.liturgicalDay(for: ascensionThursday)?.title.contains("Ascension") ?? false)
    }

    // MARK: - A load that finishes late

    func testALoadThatFinishesLateDoesNotReplaceTheLatest() async throws {
        // NAB, with a server that takes a second to fail for 14 November and fails at once for the 15th:
        // a pull to refresh still waiting on yesterday when the app opens on the new day.
        UserDefaults.standard.set("New American Bible (NAB)", forKey: "bibleTranslation")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SlowFeedProtocol.self]
        let service = EvangelizioService(baseURLString: "https://feed.test/AM/days/", urlSession: URLSession(configuration: configuration))
        let viewModel = TodayViewModel(readingsRepository: ReadingsRepository(evangelizioService: service))
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: date)!

        let slow = Task { await viewModel.loadReadings(for: date, forceRefresh: true) }
        while !Calendar.current.isDate(viewModel.currentDate, inSameDayAs: date) { await Task.yield() }
        await viewModel.loadReadings(for: nextDay)
        await slow.value

        let shown = try XCTUnwrap(viewModel.dailyReadings)
        XCTAssertTrue(Calendar.current.isDate(shown.date, inSameDayAs: nextDay), "The earlier day's readings replaced the latest")
        XCTAssertTrue(Calendar.current.isDate(viewModel.currentDate, inSameDayAs: nextDay))
        XCTAssertFalse(viewModel.isLoading)
    }
}

/// Fails every request, after a second for the feed's 14 November 2026 and at once otherwise.
final class SlowFeedProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let delay: TimeInterval = request.url?.absoluteString.hasSuffix("2026-11-14") == true ? 1.0 : 0
        nonisolated(unsafe) let loader = self
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            loader.client?.urlProtocol(loader, didFailWithError: URLError(.notConnectedToInternet))
        }
    }

    override func stopLoading() {}
}
