//
//  LiturgicalCalendarTests.swift
//  DailyReadingsTests
//
//  Created for DailyReadings Tests.
//  iOS 17+ | Swift 6+
//

import XCTest
import SwiftData
@testable import DailyReadings

final class LiturgicalCalendarTests: XCTestCase {
    
    private var calendar: Calendar!
    
    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = cal
    }
    
    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)!
    }
    
    // MARK: - 1. Advent in November Tests
    
    func testFirstSundayOfAdvent2026InNovember() {
        // November 29, 2026 is the First Sunday of Advent for the 2027 Liturgical Year
        let date = makeDate(year: 2026, month: 11, day: 29)
        let day = LiturgicalCalendar.day(for: date, calendar: calendar)
        
        XCTAssertEqual(day.season, .advent, "Nov 29, 2026 must be in the Advent season")
        XCTAssertEqual(day.seasonWeek, 1, "Nov 29, 2026 must be the 1st week of Advent")
        XCTAssertEqual(day.color, .violet, "First Sunday of Advent must be violet")
        XCTAssertEqual(day.title, "First Sunday of Advent")
        XCTAssertEqual(day.rank, .primarySolemnity)
        XCTAssertEqual(day.sundayCycle, .B, "2026 Advent begins Year B (Liturgical Year 2027)")
    }
    
    func testAdventWeekdayInLateNovember2026() {
        // Monday, November 30, 2026 (St. Andrew Feast or Advent Weekday)
        let date = makeDate(year: 2026, month: 11, day: 30)
        let day = LiturgicalCalendar.day(for: date, calendar: calendar)
        
        XCTAssertEqual(day.season, .advent, "Nov 30, 2026 must be in Advent")
        XCTAssertEqual(day.seasonWeek, 1)
    }
    
    func testFirstSundayOfAdvent2027InNovember() {
        // November 28, 2027 is the First Sunday of Advent for the 2028 Liturgical Year
        let date = makeDate(year: 2027, month: 11, day: 28)
        let day = LiturgicalCalendar.day(for: date, calendar: calendar)
        
        XCTAssertEqual(day.season, .advent, "Nov 28, 2027 must be in Advent")
        XCTAssertEqual(day.seasonWeek, 1)
        XCTAssertEqual(day.color, .violet)
        XCTAssertEqual(day.title, "First Sunday of Advent")
        XCTAssertEqual(day.sundayCycle, .C, "2027 Advent begins Year C (Liturgical Year 2028)")
    }
    
    // MARK: - 2. Epiphany in the US Calendar (No duplicate on Jan 6)
    
    func testEpiphanyCelebratedOnSundayInUS() {
        // In 2027, the Sunday between Jan 2 and Jan 8 is January 3
        let sundayDate = makeDate(year: 2027, month: 1, day: 3)
        let epiphanyDay = LiturgicalCalendar.day(for: sundayDate, calendar: calendar)
        
        XCTAssertEqual(epiphanyDay.title, "The Epiphany of the Lord")
        XCTAssertEqual(epiphanyDay.color, .white)
        XCTAssertTrue(epiphanyDay.isSolemnity)
    }
    
    func testJanuary6IsNotDuplicateEpiphanyInUS() {
        // In 2027, Epiphany was celebrated on Jan 3. January 6 should NOT be Epiphany again.
        let jan6 = makeDate(year: 2027, month: 1, day: 6)
        let day = LiturgicalCalendar.day(for: jan6, calendar: calendar)
        
        XCTAssertNotEqual(day.title, "The Epiphany of the Lord", "Jan 6 must not repeat Epiphany when celebrated on Sunday in the US")
        XCTAssertEqual(day.season, .christmas)
    }
    
    // MARK: - 3. Lenten Friday Solemnity Abstinence Exemption (Canon 1251)
    
    func testStJosephSolemnityOnLentenFridayWaivesAbstinence() {
        // In 2027, March 19 (Solemnity of St. Joseph) falls on a Friday during Lent.
        // Canon 1251: Abstinence is to be observed on all Fridays, UNLESS a solemnity should fall on a Friday.
        let stJosephDate = makeDate(year: 2027, month: 3, day: 19)
        let day = LiturgicalCalendar.day(for: stJosephDate, calendar: calendar)
        
        XCTAssertTrue(day.title.contains("Saint Joseph"), "March 19 must be Saint Joseph")
        XCTAssertTrue(day.rank.isSolemnity, "Saint Joseph is a solemnity")
        XCTAssertFalse(day.isAbstinence, "Canon 1251: Friday abstinence is waived on a solemnity!")
    }
    
    func testOrdinaryLentenFridayRequiresAbstinence() {
        // Friday, March 12, 2027 is a regular Friday of Lent (no solemnity).
        let normalLentenFriday = makeDate(year: 2027, month: 3, day: 12)
        let day = LiturgicalCalendar.day(for: normalLentenFriday, calendar: calendar)
        
        XCTAssertEqual(day.season, .lent)
        XCTAssertTrue(day.isAbstinence, "Ordinary Friday of Lent requires abstinence from meat")
    }
    
    // MARK: - 4. Post-Pentecost Ordinary Time Week Continuity
    
    func testMaryMotherOfChurchMatchesResumedOrdinaryTimeWeek() {
        // In 2026, Pentecost is May 24.
        // Monday, May 25 is Memorial of the Blessed Virgin Mary, Mother of the Church.
        // Tuesday, May 26 is Weekday of the 8th Week in Ordinary Time.
        let mondayDate = makeDate(year: 2026, month: 5, day: 25)
        let tuesdayDate = makeDate(year: 2026, month: 5, day: 26)
        
        let mondayDay = LiturgicalCalendar.day(for: mondayDate, calendar: calendar)
        let tuesdayDay = LiturgicalCalendar.day(for: tuesdayDate, calendar: calendar)
        
        XCTAssertTrue(mondayDay.title.contains("Mother of the Church"))
        XCTAssertEqual(mondayDay.seasonWeek, tuesdayDay.seasonWeek, "Monday and Tuesday must have the same Ordinary Time week number for psalter continuity!")
        XCTAssertEqual(mondayDay.seasonWeek, 8, "In 2026, Ordinary Time resumes at Week 8")
    }
    
    // MARK: - 5. Solemnity Collision (Sacred Heart vs St. John the Baptist in 2033)
    
    func testSacredHeartAndStJohnTheBaptistCollision2033() {
        // In 2033, Easter is April 17, and Pentecost is June 5.
        // Sacred Heart falls on Friday, June 24, colliding with the Nativity of St. John the Baptist.
        // UNLY §59 / Roman Congregation norm: Sacred Heart (Solemnity of the Lord) stays on Friday June 24.
        // Nativity of St. John the Baptist transfers to Thursday, June 23.
        let june23 = makeDate(year: 2033, month: 6, day: 23)
        let june24 = makeDate(year: 2033, month: 6, day: 24)
        
        let day23 = LiturgicalCalendar.day(for: june23, calendar: calendar)
        let day24 = LiturgicalCalendar.day(for: june24, calendar: calendar)
        
        XCTAssertTrue(day24.title.contains("Sacred Heart"), "June 24, 2033 must celebrate the Sacred Heart of Jesus")
        XCTAssertTrue(day23.title.contains("John the Baptist"), "Nativity of St. John the Baptist must be transferred to June 23, 2033")
    }

    // MARK: - 6. Ascension Celebration Modes (Thursday vs Sunday)

    func testAscensionCelebratedOnSundayByDefaultInUS() {
        // In 2027, Easter is March 28.
        // Thursday of 6th Week of Easter is May 6, 2027 (Easter + 39 days).
        // 7th Sunday of Easter is May 9, 2027 (Easter + 42 days).
        let may6 = makeDate(year: 2027, month: 5, day: 6)
        let may9 = makeDate(year: 2027, month: 5, day: 9)

        let thursdayDay = LiturgicalCalendar.day(for: may6, calendar: calendar, ascensionOnThursday: false)
        let sundayDay = LiturgicalCalendar.day(for: may9, calendar: calendar, ascensionOnThursday: false)

        XCTAssertEqual(thursdayDay.title, "Thursday of the Sixth Week of Easter")
        XCTAssertEqual(thursdayDay.rank, .weekday)
        XCTAssertFalse(thursdayDay.isHolyDayOfObligation, "Thursday of 6th Week of Easter is not an obligation when Ascension is on Sunday")

        XCTAssertEqual(sundayDay.title, "The Ascension of the Lord")
        XCTAssertEqual(sundayDay.rank, .primarySolemnity)
        XCTAssertTrue(sundayDay.isHolyDayOfObligation, "Ascension on Sunday is a Holy Day of Obligation")
    }

    func testAscensionCelebratedOnThursdayWhenProvincialToggleActive() {
        // In 2027, Easter is March 28.
        // Thursday of 6th Week of Easter is May 6, 2027.
        // 7th Sunday of Easter is May 9, 2027.
        let may6 = makeDate(year: 2027, month: 5, day: 6)
        let may9 = makeDate(year: 2027, month: 5, day: 9)

        let thursdayDay = LiturgicalCalendar.day(for: may6, calendar: calendar, ascensionOnThursday: true)
        let sundayDay = LiturgicalCalendar.day(for: may9, calendar: calendar, ascensionOnThursday: true)

        XCTAssertEqual(thursdayDay.title, "The Ascension of the Lord")
        XCTAssertEqual(thursdayDay.rank, .primarySolemnity)
        XCTAssertEqual(thursdayDay.color, .white)
        XCTAssertTrue(thursdayDay.isHolyDayOfObligation, "Ascension on Thursday is a Holy Day of Obligation in designated provinces")

        XCTAssertEqual(sundayDay.title, "Seventh Sunday of Easter")
        XCTAssertEqual(sundayDay.rank, .primarySolemnity)
        XCTAssertEqual(sundayDay.color, .white)
        XCTAssertTrue(sundayDay.isHolyDayOfObligation, "Sunday is always an obligation")
    }

    func testSeventhSundayOfEasterResolvesAllReadingsInYearC() {
        // May 9, 2027 is 7th Sunday of Easter (Year C).
        let may9 = makeDate(year: 2027, month: 5, day: 9)
        let day = LiturgicalCalendar.day(for: may9, calendar: calendar, ascensionOnThursday: true)
        let entries = PericoreIndex.shared.cycleEntries(for: day)

        XCTAssertFalse(entries.isEmpty, "Seventh Sunday of Easter must resolve readings")
        let types = Set(entries.map(\.type))
        XCTAssertTrue(types.contains(.firstReading), "Must contain First Reading (Acts 7:55-60)")
        XCTAssertTrue(types.contains(.responsorialPsalm), "Must contain Responsorial Psalm (Psalm 97)")
        XCTAssertTrue(types.contains(.secondReading), "Must contain Second Reading (Rev 22:12-14)")
        XCTAssertTrue(types.contains(.gospelAcclamation), "Must contain Gospel Acclamation")
        XCTAssertTrue(types.contains(.gospel), "Must contain Gospel (John 17:20-26)")
    }

    // MARK: - 7. Newly Added Memorials in FixedSolemnities

    func testEveryObligatoryMemorialAndFeastOfTheYearIsInTheCalendar() {
        // The General Roman Calendar and the US proper: each date must carry a celebration of at
        // least obligatory-memorial rank.
        let expected: [(Int, Int, String)] = [
            (1, 2, "Basil"), (1, 4, "Seton"), (1, 5, "Neumann"), (1, 17, "Anthony"), (1, 21, "Agnes"),
            (1, 24, "Francis de Sales"), (1, 25, "Conversion"), (1, 26, "Timothy"), (1, 28, "Thomas Aquinas"), (1, 31, "John Bosco"),
            (2, 2, "Presentation"), (2, 5, "Agatha"), (2, 6, "Paul Miki"), (2, 10, "Scholastica"), (2, 14, "Cyril"),
            (2, 22, "Chair"), (2, 23, "Polycarp"), (3, 7, "Perpetua"), (4, 7, "de la Salle"), (4, 11, "Stanislaus"),
            (4, 29, "Catherine of Siena"), (5, 2, "Athanasius"), (5, 3, "Philip"), (5, 14, "Matthias"), (5, 26, "Philip Neri"),
            (5, 31, "Visitation"), (6, 1, "Justin"), (6, 3, "Lwanga"), (6, 5, "Boniface"), (6, 11, "Barnabas"),
            (6, 13, "Anthony of Padua"), (6, 21, "Aloysius"), (6, 28, "Irenaeus"), (7, 3, "Thomas"), (7, 11, "Benedict"),
            (7, 14, "Kateri"), (7, 15, "Bonaventure"), (7, 22, "Mary Magdalene"), (7, 25, "James"), (7, 26, "Joachim"),
            (7, 29, "Martha"), (7, 31, "Ignatius"), (8, 1, "Alphonsus"), (8, 4, "Vianney"), (8, 6, "Transfiguration"),
            (8, 8, "Dominic"), (8, 10, "Lawrence"), (8, 11, "Clare"), (8, 14, "Kolbe"), (8, 20, "Bernard"),
            (8, 21, "Pius X"), (8, 22, "Queenship"), (8, 24, "Bartholomew"), (8, 27, "Monica"), (8, 28, "Augustine"),
            (8, 29, "Passion"), (9, 3, "Gregory"), (9, 8, "Nativity"), (9, 9, "Peter Claver"), (9, 13, "Chrysostom"),
            (9, 14, "Exaltation"), (9, 15, "Sorrows"), (9, 16, "Cornelius"), (9, 20, "Andrew Kim"), (9, 21, "Matthew"),
            (9, 23, "Pio"), (9, 27, "Vincent"), (9, 29, "Michael"), (9, 30, "Jerome"), (10, 1, "Thérèse"),
            (10, 2, "Guardian Angels"), (10, 4, "Francis of Assisi"), (10, 7, "Rosary"), (10, 15, "Teresa"), (10, 17, "Ignatius of Antioch"),
            (10, 18, "Luke"), (10, 19, "Brébeuf"), (10, 28, "Simon"), (11, 4, "Borromeo"), (11, 9, "Lateran"),
            (11, 10, "Leo"), (11, 11, "Martin"), (11, 12, "Josaphat"), (11, 13, "Cabrini"), (11, 17, "Elizabeth"),
            (11, 21, "Presentation"), (11, 22, "Cecilia"), (11, 24, "Andrew Dũng-Lạc"), (11, 30, "Andrew"), (12, 3, "Francis Xavier"),
            (12, 7, "Ambrose"), (12, 13, "Lucy"), (12, 14, "John of the Cross"), (12, 26, "Stephen"), (12, 27, "John"), (12, 28, "Innocents")
        ]
        var missing: [String] = []
        for (month, day, name) in expected {
            let celebrations = FixedSolemnities.celebrationsByMonthAndDay[FixedSolemnities.CelebrationKey(month: month, day: day)] ?? []
            let found = celebrations.contains {
                $0.title.contains(name) && $0.rank.rawValue <= LiturgicalRank.obligatoryMemorial.rawValue
            }
            if !found { missing.append("\(month)/\(day) \(name)") }
        }
        XCTAssertEqual(missing, [])
    }

    func testObligatoryMemorialsInFixedSolemnities() {
        // St. Pio of Pietrelcina on September 23
        let pio = FixedSolemnities.celebrationsByMonthAndDay[FixedSolemnities.CelebrationKey(month: 9, day: 23)]?.first
        XCTAssertNotNil(pio)
        XCTAssertTrue(pio?.title.contains("Padre Pio") == true)
        XCTAssertEqual(pio?.rank, .obligatoryMemorial)

        // Saints Timothy and Titus on January 26
        let timothy = FixedSolemnities.celebrationsByMonthAndDay[FixedSolemnities.CelebrationKey(month: 1, day: 26)]?.first
        XCTAssertNotNil(timothy)
        XCTAssertTrue(timothy?.title.contains("Timothy and Titus") == true)
        XCTAssertEqual(timothy?.rank, .obligatoryMemorial)

        // Saint John Bosco on January 31
        let bosco = FixedSolemnities.celebrationsByMonthAndDay[FixedSolemnities.CelebrationKey(month: 1, day: 31)]?.first
        XCTAssertNotNil(bosco)
        XCTAssertTrue(bosco?.title.contains("John Bosco") == true)
        XCTAssertEqual(bosco?.rank, .obligatoryMemorial)

        // Saints Perpetua and Felicity on March 7
        let perpetua = FixedSolemnities.celebrationsByMonthAndDay[FixedSolemnities.CelebrationKey(month: 3, day: 7)]?.first
        XCTAssertNotNil(perpetua)
        XCTAssertTrue(perpetua?.title.contains("Perpetua and Felicity") == true)
        XCTAssertEqual(perpetua?.rank, .obligatoryMemorial)

        // Saints Jean de Brébeuf and Isaac Jogues (North American Martyrs) on October 19
        let martyrs = FixedSolemnities.celebrationsByMonthAndDay[FixedSolemnities.CelebrationKey(month: 10, day: 19)]?.first
        XCTAssertNotNil(martyrs)
        XCTAssertTrue(martyrs?.title.contains("Isaac Jogues") == true)
        XCTAssertEqual(martyrs?.rank, .obligatoryMemorial)
        XCTAssertTrue(martyrs?.isUSProper == true)
    }

    // MARK: - 8. Daily Reminder Notification Content

    func testDailyReminderNotificationContentFormatsVerseAndSaint() {
        let weekday = LiturgicalDay(
            date: Date(),
            season: .ordinaryTime,
            seasonWeek: 32,
            title: "Saint Frances Xavier Cabrini, Virgin",
            rank: .obligatoryMemorial,
            color: .white,
            sundayCycle: .yearB,
            weekdayCycle: .yearII,
            isSunday: false,
            isHolyDayOfObligation: false,
            dayOfWeekInSeason: 5
        )

        let verse = VerseOfTheDay(
            text: "Blessed are they who follow the law of the Lord!",
            citation: "Psalm 119:1",
            theme: "Responsorial Refrain",
            sourceNote: "Today's Psalm"
        )

        let content = NotificationManager.makeDailyReminderContent(for: weekday, verse: verse)

        XCTAssertEqual(content.title, "DailyReadings 📖")
        XCTAssertEqual(content.subtitle, "Saint Frances Xavier Cabrini, Virgin")
        XCTAssertEqual(content.body, "“Blessed are they who follow the law of the Lord!” — Psalm 119:1")
    }

    func testDailyReminderNotificationContentHolyDayOfObligation() {
        let holyDay = LiturgicalDay(
            date: Date(),
            season: .advent,
            seasonWeek: 2,
            title: "Solemnity of the Immaculate Conception of the Blessed Virgin Mary",
            rank: .generalSolemnity,
            color: .white,
            sundayCycle: .yearC,
            weekdayCycle: .yearI,
            isSunday: false,
            isHolyDayOfObligation: true,
            dayOfWeekInSeason: 1
        )

        let verse = VerseOfTheDay(
            text: "Hail, full of grace! The Lord is with you.",
            citation: "Luke 1:28",
            theme: "Gospel Acclamation",
            sourceNote: "Today's Liturgy"
        )

        let content = NotificationManager.makeDailyReminderContent(for: holyDay, verse: verse)

        XCTAssertEqual(content.title, "Holy Day of Obligation 🔔")
        XCTAssertEqual(content.subtitle, "Solemnity of the Immaculate Conception of the Blessed Virgin Mary")
        XCTAssertEqual(content.body, "“Hail, full of grace! The Lord is with you.” — Luke 1:28")
    }

    // MARK: - 9. Gospel Acclamation Backfill & Verse of the Day Alignment

    @MainActor
    func testBackfillMissingGospelAcclamationForNAB() async {
        let sampleDate = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 14))!
        let day = LiturgicalCalendar.shared.liturgicalDay(for: sampleDate)

        let incompleteReadings: [Reading] = [
            Reading(
                type: .firstReading,
                citation: ReadingCitation(book: "3 John", chapter: 1, verses: "5-8"),
                text: "Beloved, you are faithful in all you do...",
                translation: "NAB"
            ),
            Reading(
                type: .responsorialPsalm,
                citation: ReadingCitation(book: "Psalms", chapter: 112, verses: "1-6"),
                text: "Blessed the man who fears the Lord...",
                response: "Blessed the man who fears the Lord.",
                translation: "NAB"
            ),
            Reading(
                type: .gospel,
                citation: ReadingCitation(book: "Luke", chapter: 18, verses: "1-8"),
                text: "Jesus told his disciples a parable about the necessity for them to pray always...",
                translation: "NAB"
            )
        ]

        let repository = ReadingsRepository()
        let completeReadings = await repository.backfillGospelAcclamation(incompleteReadings, for: day)

        let acclamation = completeReadings.first(where: { $0.type == .gospelAcclamation })
        XCTAssertNotNil(acclamation, "Gospel Acclamation must be backfilled when remote service omits it")
        XCTAssertFalse(acclamation?.text.isEmpty ?? true)
        XCTAssertEqual(acclamation?.translation, "WEBC", "The added text is World English Bible, not NAB")
        XCTAssertEqual(completeReadings.filter { $0.translation == "NAB" }.count, 3, "The feed's readings are untouched")
        XCTAssertEqual(acclamation?.citation.book, "2 Thessalonians")
        XCTAssertEqual(acclamation?.citation.chapter, 2)
        XCTAssertEqual(acclamation?.citation.verses, "14")

        let order = completeReadings.map(\.type)
        XCTAssertEqual(order, [.firstReading, .responsorialPsalm, .gospelAcclamation, .gospel])

        let daily = DailyReadings(
            date: sampleDate,
            liturgicalTitle: day.title,
            readings: completeReadings,
            translation: "NAB"
        )
        let verse = VerseOfTheDayProvider.verse(from: daily, date: sampleDate)
        XCTAssertEqual(verse.theme, "Gospel Acclamation")
        XCTAssertTrue(verse.citation.contains("2 Thessalonians 2:14"))
    }

    func testNoAcclamationIsAddedWhenTheFeedCarriesADifferentMass() async {
        // The feed's Gospel is not the Lectionary's for this day (e.g. the feed has the weekday while
        // the app keeps a solemnity), so the day's acclamation would not belong to it.
        let sampleDate = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 14))!
        let day = LiturgicalCalendar.shared.liturgicalDay(for: sampleDate)
        let otherMass: [Reading] = [
            Reading(type: .firstReading, citation: ReadingCitation(book: "Isaiah", chapter: 40, verses: "1-5"), text: "Comfort, give comfort to my people...", translation: "NAB"),
            Reading(type: .gospel, citation: ReadingCitation(book: "Mark", chapter: 1, verses: "1-8"), text: "The beginning of the gospel...", translation: "NAB")
        ]

        let result = await ReadingsRepository().backfillGospelAcclamation(otherMass, for: day)
        XCTAssertEqual(result, otherMass)
    }

    func testOnlyTheAcclamationIsAddedEvenWhenTheFeedLacksOtherReadings() async {
        // A Sunday: the Lectionary has a Second Reading. A feed without one must not get one from the index.
        let sunday = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 15))!
        let day = LiturgicalCalendar.shared.liturgicalDay(for: sunday)
        let entries = PericoreIndex.shared.entries(for: day)
        XCTAssertTrue(entries.contains { $0.type == .secondReading }, "Fixture: the index has a Second Reading for this Sunday")
        let feed = [ReadingType.firstReading, .responsorialPsalm, .gospel]
            .compactMap { type in entries.first { $0.type == type } }
            .map { Reading(type: $0.type, citation: $0.citation, text: "NAB text", translation: "NAB") }

        let result = await ReadingsRepository().backfillGospelAcclamation(feed, for: day)
        XCTAssertEqual(result.map(\.type), [.firstReading, .responsorialPsalm, .gospelAcclamation, .gospel])
    }

    func testReadingIsLabelledWithItsOwnTranslation() {
        let citation = ReadingCitation(book: "John", chapter: 1, verses: "14")
        XCTAssertEqual(Reading(type: .gospelAcclamation, citation: citation, text: "x", translation: "WEBC").translationDisplayName, "World English Bible (WEB-C)")
        XCTAssertEqual(Reading(type: .gospel, citation: citation, text: "x", translation: "DRB").translationDisplayName, "Douay-Rheims")
        XCTAssertEqual(Reading(type: .gospel, citation: citation, text: "x", translation: "NAB").translationDisplayName, "New American Bible (NAB)")
    }

    @MainActor
    func testNABDaysCachedByBuild19AreClearedOnceAndOtherRowsKept() throws {
        let key = ReadingsRepository.nabCacheClearedKey
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let container = try ModelContainer(for: CachedReading.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        context.insert(CachedReading(dateKey: "2026-11-14", translation: "NAB", readingsJSON: Data()))
        context.insert(CachedReading(dateKey: "2026-11-15", translation: "NAB", readingsJSON: Data()))
        context.insert(CachedReading(dateKey: "2026-11-16", translation: "DRB", readingsJSON: Data()))
        try context.save()

        ReadingsRepository().configure(modelContainer: container)
        let remaining = try ModelContext(container).fetch(FetchDescriptor<CachedReading>())
        XCTAssertEqual(remaining.map(\.translation), ["DRB"])
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))

        // Once only: a day cached after the clean-up stays.
        let later = ModelContext(container)
        later.insert(CachedReading(dateKey: "2026-11-17", translation: "NAB", readingsJSON: Data()))
        try later.save()
        ReadingsRepository().configure(modelContainer: container)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<CachedReading>()), 2)
    }
}
