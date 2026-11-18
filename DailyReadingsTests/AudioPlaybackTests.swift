//
//  AudioPlaybackTests.swift
//  DailyReadingsTests
//
//  Drives the real speech synthesizer to confirm playback moves through every passage and reading.
//

import XCTest
import AVFoundation
@testable import DailyReadings

@MainActor
final class AudioPlaybackTests: XCTestCase {

    private func reading(_ type: ReadingType, _ book: String, _ text: String) -> Reading {
        Reading(type: type, citation: ReadingCitation(book: book, chapter: 1, verses: "1-2"), text: text, translation: "WEBC")
    }

    func testPausesSeparateThePartsOfAReading() {
        let long = String(repeating: "The people who walked in darkness have seen a great light. ", count: 12)
        let passages = AudioReadingPlayer.passages(forParts: ["A reading from Isaiah.", long, "The Word of the Lord."])
        XCTAssertEqual(passages.first?.pauseAfter, AudioReadingPlayer.SpeechPause.betweenParts, "pause after the announcement")
        XCTAssertEqual(passages.last?.pauseAfter, AudioReadingPlayer.SpeechPause.afterReading, "pause after the reading")
        XCTAssertEqual(passages.last?.text, "The Word of the Lord.")
        let body = passages.dropFirst().dropLast()
        XCTAssertGreaterThan(body.count, 1)
        XCTAssertEqual(body.last?.pauseAfter, AudioReadingPlayer.SpeechPause.betweenParts, "pause before the acclamation")
        XCTAssertTrue(body.dropLast().allSatisfy { $0.pauseAfter == AudioReadingPlayer.SpeechPause.withinPart })
    }

    func testSkippingMovesBetweenReadings() async throws {
        let player = AudioReadingPlayer.shared
        let readings = [
            reading(.firstReading, "Isaiah", "Comfort my people."),
            reading(.responsorialPsalm, "Psalms", "The Lord is my shepherd."),
            reading(.gospel, "Mark", "Prepare the way of the Lord.")
        ]
        player.start(readings: readings, liturgicalTitle: "Test", liturgicalColor: .green)
        defer { player.stop() }
        player.skipNext()
        XCTAssertEqual(player.currentReadingIndex, 1)
        XCTAssertTrue(player.isPlaying)
        player.skipNext()
        XCTAssertEqual(player.currentReading?.type, .gospel)
        player.skipPrevious()
        XCTAssertEqual(player.currentReadingIndex, 1)
        player.cycleSpeed()
        XCTAssertEqual(player.currentReadingIndex, 1)
        XCTAssertTrue(player.isPlaying)
        player.cycleSpeed(); player.cycleSpeed()   // back to the original speed
    }

    func testPlaybackAdvancesThroughEveryReadingAndThenStops() async throws {
        let player = AudioReadingPlayer.shared
        let readings = [
            reading(.firstReading, "Isaiah", "Comfort my people. Speak tenderly to Jerusalem."),
            reading(.responsorialPsalm, "Psalms", "The Lord is my shepherd."),
            reading(.gospel, "Mark", "The beginning of the Gospel. Prepare the way of the Lord.")
        ]
        player.start(readings: readings, liturgicalTitle: "Test", liturgicalColor: .green)
        defer { player.stop() }

        var seen: [Int] = []
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if player.currentReading != nil, seen.last != player.currentReadingIndex { seen.append(player.currentReadingIndex) }
            if !player.isPlaying && !player.isPaused && player.currentReading == nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(seen, [0, 1, 2], "Readings reached, in order")
        XCTAssertFalse(player.isPlaying, "Playback ends after the last reading")
    }

    func testLiturgicalSpeechAnnouncementsOmitVerses() {
        let firstReading = Reading(
            type: .firstReading,
            citation: ReadingCitation(book: "Philemon", chapter: 1, verses: "7-20"),
            text: "I have had great joy in your love.",
            translation: "WEBC"
        )
        let firstParts = AudioReadingPlayer.liturgicalSpeechParts(for: firstReading)
        XCTAssertEqual(firstParts.first, "First Reading. A reading from the Letter of Saint Paul to Philemon.")
        XCTAssertFalse(firstParts.first!.contains("1:7-20"))

        let psalm = Reading(
            type: .responsorialPsalm,
            citation: ReadingCitation(book: "Psalms", chapter: 146, verses: "7, 8-9a, 9bc-10"),
            text: "Stanza 1\n\nStanza 2",
            response: "Praise the Lord, my soul!",
            translation: "WEBC"
        )
        let psalmParts = AudioReadingPlayer.liturgicalSpeechParts(for: psalm)
        XCTAssertEqual(psalmParts.first, "Responsorial Psalm. Psalm 146.")
        XCTAssertFalse(psalmParts.first!.contains("7, 8-9a"))

        let gospel = Reading(
            type: .gospel,
            citation: ReadingCitation(book: "Mark", chapter: 1, verses: "1-8"),
            text: "The beginning of the Gospel of Jesus Christ.",
            translation: "WEBC"
        )
        let gospelParts = AudioReadingPlayer.liturgicalSpeechParts(for: gospel)
        XCTAssertEqual(gospelParts.first, "The Holy Gospel according to Mark.")
        XCTAssertFalse(gospelParts.first!.contains("1:1-8"))
    }

    func testGospelAcclamationIsFramedByAlleluiaOutsideLent() {
        let acclamation = reading(.gospelAcclamation, "John", "I am the light of the world, says the Lord.")
        let ordinary = AudioReadingPlayer.liturgicalSpeechParts(for: acclamation, season: .ordinaryTime)
        XCTAssertEqual(ordinary, ["Gospel Acclamation.", "Alleluia, alleluia.", "I am the light of the world, says the Lord.", "Alleluia, alleluia."])
        for season: LiturgicalSeason? in [.lent, .paschalTriduum, nil] {
            let parts = AudioReadingPlayer.liturgicalSpeechParts(for: acclamation, season: season)
            XCTAssertFalse(parts.contains { $0.contains("Alleluia") }, "No Alleluia in \(String(describing: season))")
        }
    }

    func testSpeedSetInSettingsAppliesWhilePlayingAndAfterAPause() async throws {
        let player = AudioReadingPlayer.shared
        let original = player.speed
        defer { player.stop(); player.speed = original }
        let readings = [
            reading(.firstReading, "Isaiah", "Comfort my people. Speak tenderly to Jerusalem."),
            reading(.gospel, "Mark", "Prepare the way of the Lord.")
        ]
        let (first, second) = (PlaybackSpeed.allCases[0], PlaybackSpeed.allCases[1])
        player.speed = first
        player.start(readings: readings, liturgicalTitle: "Test", liturgicalColor: .green)

        // Settings sets the property directly, not through the mini player's button.
        player.speed = second
        XCTAssertEqual(player.queuedSpeechRates, [second.rawValue], "Applies at once while playing")

        player.pause()
        player.speed = first
        player.resume()
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(player.queuedSpeechRates, [first.rawValue], "A change made while paused applies on resume")
    }

    // MARK: - Interruptions

    private let massReadings: [Reading] = [
        Reading(type: .firstReading, citation: ReadingCitation(book: "Isaiah", chapter: 40, verses: "1-2"), text: "Comfort my people. Speak tenderly to Jerusalem.", translation: "WEBC"),
        Reading(type: .gospel, citation: ReadingCitation(book: "Mark", chapter: 1, verses: "1-3"), text: "Prepare the way of the Lord.", translation: "WEBC")
    ]

    func testACallDoesNotResumeAReadingTheListenerPaused() {
        let player = AudioReadingPlayer.shared
        defer { player.stop() }
        player.start(readings: massReadings, liturgicalTitle: "Test", liturgicalColor: .green)
        player.pause()

        player.handleInterruption(.began, shouldResume: false)
        player.handleInterruption(.ended, shouldResume: true)

        XCTAssertTrue(player.isPaused, "The listener paused before the call; it stays paused")
        XCTAssertFalse(player.isPlaying)
    }

    func testACallResumesTheReadingItPaused() {
        let player = AudioReadingPlayer.shared
        defer { player.stop() }
        player.start(readings: massReadings, liturgicalTitle: "Test", liturgicalColor: .green)

        player.handleInterruption(.began, shouldResume: false)
        XCTAssertTrue(player.isPaused)
        player.handleInterruption(.ended, shouldResume: true)

        XCTAssertTrue(player.isPlaying)
    }

    // MARK: - Speech callbacks off the main thread

    func testSpeechCallbacksFromAnotherThreadReachThePlayer() async throws {
        let player = AudioReadingPlayer.shared
        defer { player.stop() }
        player.start(readings: massReadings, liturgicalTitle: "Test", liturgicalColor: .green)
        player.pause()
        let utterance = try XCTUnwrap(player.queuedUtterances.first)

        // Apple does not promise the main thread. A callback from elsewhere must not crash and must
        // still update the play state.
        nonisolated(unsafe) let sent = (player, utterance)
        await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            sent.0.speechSynthesizer(AVSpeechSynthesizer(), didContinue: sent.1)
        }.value

        for _ in 0..<100 where !player.isPlaying {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(player.isPlaying)
    }
}
