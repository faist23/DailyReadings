//
//  SaintLifeFactsTests.swift
//  DailyReadingsTests
//
//  The life facts and quote added to saints.json by Scripts/enrich_saints.py reach the Saint model,
//  and the "Lived" line falls back to the era when the years are unknown.
//

import XCTest
@testable import DailyReadings

final class SaintLifeFactsTests: XCTestCase {

    private let database = SaintsDatabase()

    func testFrancisOfAssisiHasHisYearsPlaceOrderAndQuote() throws {
        let francis = try XCTUnwrap(database.saints(forMonth: 10, day: 4).first { $0.name.contains("Francis of Assisi") })
        XCTAssertEqual(francis.lifeSpan, "1182 – 1226")
        XCTAssertEqual(francis.birthplace, "Assisi")
        XCTAssertEqual(francis.religiousOrder, "Franciscans")
        XCTAssertEqual(francis.quote?.source, "Admonitions, 27")
    }

    func testMostSaintsHaveTheirYears() {
        let saints = (1...12).flatMap { month in (1...31).flatMap { database.saints(forMonth: month, day: $0) } }
        let withYears = saints.filter { $0.lifeSpan != nil }.count
        XCTAssertGreaterThan(Double(withYears) / Double(saints.count), 0.6, "\(withYears) of \(saints.count)")
        XCTAssertTrue(saints.allSatisfy { $0.livedLine != nil || $0.era == nil || $0.era!.isEmpty })
    }

    func testQuotesAreShortAndClean() {
        let quotes = (1...12).flatMap { month in (1...31).flatMap { database.saints(forMonth: month, day: $0) } }.compactMap(\.quote)
        XCTAssertFalse(quotes.isEmpty)
        for quote in quotes {
            XCTAssertLessThanOrEqual(quote.text.count, 240, quote.text)
            XCTAssertFalse(quote.text.contains("[[") || quote.text.contains("{{") || quote.text.contains("<"), quote.text)
            XCTAssertFalse(quote.source.contains("[[") || quote.source.contains("{{"), quote.source)
        }
    }

    func testLivedLineUsesTheYearsThenTheEra() {
        var saint = Saint(id: "x", name: "X", feastDate: "01-01", era: "4th century", biography: "")
        XCTAssertEqual(saint.livedLine, "4th century")
        saint.died = "305"
        XCTAssertEqual(saint.livedLine, "Died 305")
        saint.born = "c. 250"
        XCTAssertEqual(saint.livedLine, "c. 250 – 305")
    }
}
