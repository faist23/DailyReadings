//
//  SaintCalendarTests.swift
//  DailyReadingsTests
//
//  saints.json is rebuilt by Scripts/build_saints.py from the General Roman Calendar and the US
//  proper calendar. These check that saints sit on their current dates, that the day's saint is
//  that day's celebration, and that every description says where it comes from.
//

import XCTest
@testable import DailyReadings

final class SaintCalendarTests: XCTestCase {

    private let database = SaintsDatabase()

    private func date(_ month: Int, _ day: Int, _ year: Int = 2026) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private var allSaints: [Saint] {
        (1...12).flatMap { month in (1...31).flatMap { database.saints(forMonth: month, day: $0) } }
    }

    func testSaintsAreOnTheirCurrentCalendarDays() {
        let expected: [(Int, Int, String)] = [
            (1, 24, "Francis de Sales"), (1, 28, "Thomas Aquinas"), (2, 14, "Cyril"), (2, 23, "Polycarp"),
            (4, 29, "Catherine of Siena"), (7, 11, "Benedict"), (8, 4, "Vianney"), (8, 27, "Monica"),
            (10, 1, "Thérèse"), (10, 17, "Ignatius of Antioch"), (1, 4, "Elizabeth Ann Seton"), (7, 14, "Kateri"),
        ]
        for (month, day, name) in expected {
            let first = database.saints(forMonth: month, day: day).first?.name ?? "nothing"
            XCTAssertTrue(first.contains(name), "\(month)/\(day) shows \(first), expected \(name)")
        }
    }

    func testOldCalendarDatesAreGone() {
        let moved: [(Int, Int, String)] = [
            (3, 7, "Thomas Aquinas"), (1, 29, "Francis de Sales"), (2, 1, "Ignatius of Antioch"),
            (8, 9, "Vianney"), (12, 25, "Francis of Assisi"), (12, 21, "Thomas"),
        ]
        for (month, day, name) in moved {
            let names = database.saints(forMonth: month, day: day).map(\.name)
            XCTAssertFalse(names.contains { $0.contains(name) }, "\(name) is still on \(month)/\(day): \(names)")
        }
    }

    func testTheDaySaintIsThatDaysCelebration() {
        // A name search across the whole year used to pick another day's saint (a "Peter" for
        // Saint Peter Claver).
        let claver = database.saint(for: date(9, 9), liturgicalDay: LiturgicalCalendar.day(for: date(9, 9)))
        XCTAssertEqual(claver?.name, "Saint Peter Claver")

        var start = date(1, 1)
        let end = date(12, 31)
        var wrong: [String] = []
        while start <= end {
            let day = LiturgicalCalendar.day(for: start)
            if let saint = database.saint(for: start, liturgicalDay: day), saint.rank != nil {
                let today = database.saints(for: start).map(\.id)
                if !today.contains(saint.id) { wrong.append("\(SaintsDatabase.feastDateKey(from: start)) \(saint.name)") }
            }
            start = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        }
        XCTAssertEqual(wrong, [])
    }

    func testEveryDescriptionSaysWhereItComesFrom() {
        let saints = allSaints
        XCTAssertGreaterThan(saints.count, 300)
        for saint in saints {
            XCTAssertFalse(saint.biography.isEmpty, saint.name)
            XCTAssertFalse(saint.sources.isEmpty, "\(saint.name) has no source")
            XCTAssertTrue(saint.sources.allSatisfy { $0.url.hasPrefix("https://en.wikipedia.org/wiki/") }, saint.name)
        }
    }

    func testSaintsStayOnTheirCelebratedDayAndShowTheMartyrologyDay() throws {
        // The app shows the day a saint is celebrated; the 2004 Roman Martyrology's day, when
        // different, is shown on the card and never moves the saint.
        let cases: [(Int, Int, String, String)] = [
            (11, 13, "Kostka", "15 August"), (6, 20, "Silverius", "2 December"),
            (5, 16, "Nepomucene", "20 March"), (10, 13, "Edward the Confessor", "5 January"),
        ]
        for (month, day, name, martyrologyDay) in cases {
            let saint = try XCTUnwrap(database.saints(forMonth: month, day: day).first { $0.name.contains(name) },
                                      "\(name) is not on \(month)/\(day)")
            XCTAssertEqual(saint.martyrologyDay, martyrologyDay, name)
        }
        // Where the Martyrology day is the day shown, nothing extra is shown.
        let aquinas = try XCTUnwrap(database.saints(forMonth: 1, day: 28).first)
        XCTAssertNil(aquinas.martyrologyDay)
    }

    func testDescriptionsHaveBalancedParentheses() throws {
        // Some Wikipedia leads open or close a parenthesis they never match ("Vincenzo Strambi,
        // religious name ...; 1 January 1745 — 1 January 1824) was"); the build mends them.
        var texts = allSaints.map { ($0.name, $0.biography) }
        for title in ["Pentecost Sunday", "Solemnity of All Saints", "The Nativity of the Lord (Christmas)"] {
            let feast = try XCTUnwrap(LiturgicalCelebrationBlurbs.feast(forTitle: title, date: date(6, 1)))
            texts.append((feast.name, feast.biography))
        }
        let unbalanced = texts.filter { _, text in
            var depth = 0
            for ch in text {
                if ch == "(" { depth += 1 }
                if ch == ")" { depth -= 1; if depth < 0 { return true } }
            }
            return depth != 0
        }
        XCTAssertEqual(unbalanced.map(\.0), [])
    }

    func testNoSuppressedCultIsShownAsASaint() {
        // Simon of Trent was in the old data; his cult (a blood libel) was abolished in 1965.
        let shown = allSaints.filter { $0.biography.localizedCaseInsensitiveContains("blood libel") }
        XCTAssertEqual(shown.map(\.name), [])
    }

    func testFeastDescriptionsComeFromWikipedia() throws {
        for title in ["Pentecost Sunday", "The Nativity of the Lord (Christmas)", "Solemnity of All Saints"] {
            let feast = try XCTUnwrap(LiturgicalCelebrationBlurbs.feast(forTitle: title, date: date(6, 1)))
            XCTAssertFalse(feast.sources.isEmpty, title)
            XCTAssertNil(feast.patronages, "\(title): feast patronages had no source")
        }
    }
}
