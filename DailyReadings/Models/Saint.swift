//
//  Saint.swift
//  DailyReadings
//
//  Created for DailyReadings Catholic Daily Readings App.
//  iOS 17+ | Swift 6+
//

import Foundation

/// Model representing a Catholic saint or blessed commemorated on the liturgical calendar.
public struct Saint: Codable, Identifiable, Hashable, Sendable {
    /// Unique identifier for the saint (e.g. "augustine_of_hippo").
    public let id: String
    /// The canonical or popular name (e.g. "St. Augustine of Hippo").
    public let name: String
    /// The liturgical feast date formatted as "MM-DD" (e.g. "08-28").
    public let feastDate: String
    /// Liturgical or ecclesiastical title (e.g. "Bishop and Doctor of the Church", "Virgin and Martyr").
    public let title: String?
    /// Historical era (e.g. "Early Church (354-430 AD)", "13th Century").
    public let era: String?
    /// Comprehensive biography and spiritual legacy.
    public let biography: String
    /// Array of patronage causes, groups, or places (e.g. ["Theologians", "Printers", "Brewers"]).
    public let patronages: [String]?
    /// Optional remote or asset URL for the saint's icon or portrait.
    public let imageURL: String?
    /// Life facts from Wikidata, each present only when known. Years are display strings
    /// ("1182", "c. 469", "35 BC").
    public var born: String? = nil
    public var died: String? = nil
    public var birthplace: String? = nil
    public var religiousOrder: String? = nil
    public var canonized: String? = nil
    /// A short quote of the saint's own words, with where it comes from.
    public var quote: SaintQuote? = nil
    /// The articles the description is taken from (Wikipedia, CC BY-SA 4.0), credited on the card.
    public var sources: [SaintSource] = []
    /// The celebration's rank in the calendar ("memorial", "optional memorial", ...), nil for a
    /// saint the calendar does not celebrate.
    public var rank: String? = nil
    /// The day the 2004 Roman Martyrology lists the saint ("15 August"), when it differs from
    /// the day the app shows them (the celebrated day).
    public var martyrologyDay: String? = nil
    
    /// Designated initializer.
    public init(
        id: String,
        name: String,
        feastDate: String,
        title: String? = nil,
        era: String? = nil,
        biography: String,
        patronages: [String]? = nil,
        imageURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.feastDate = feastDate
        self.title = title
        self.era = era
        self.biography = biography
        self.patronages = patronages
        self.imageURL = imageURL
    }

    /// Convenience initializer accepting UUID id and default feastDate.
    public init(
        id: UUID = UUID(),
        name: String,
        feastDate: String = "",
        title: String? = nil,
        era: String? = nil,
        biography: String,
        patronages: [String]? = nil,
        imageURL: String? = nil
    ) {
        self.id = id.uuidString
        self.name = name
        self.feastDate = feastDate
        self.title = title
        self.era = era
        self.biography = biography
        self.patronages = patronages
        self.imageURL = imageURL
    }
    
    // MARK: - Convenience Helpers
    
    /// Composed display subtitle combining title and era.
    public var displaySubtitle: String {
        switch (title, era) {
        case let (t?, e?):
            return "\(t) • \(e)"
        case let (t?, nil):
            return t
        case let (nil, e?):
            return e
        case (nil, nil):
            return ""
        }
    }
    
    /// "1182 – 1226", "Died 305", "Born 1878"; nil when neither year is known.
    public var lifeSpan: String? {
        switch (born, died) {
        case let (b?, d?): return "\(b) – \(d)"
        case let (nil, d?): return "Died \(d)"
        case let (b?, nil): return "Born \(b)"
        case (nil, nil): return nil
        }
    }

    /// When the saint lived: exact years when known, otherwise the era ("4th century").
    public var livedLine: String? {
        lifeSpan ?? era.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Comma-separated string of patronages (e.g. "Theologians, Printers").
    public var formattedPatronages: String? {
        guard let patronages, !patronages.isEmpty else { return nil }
        return patronages.joined(separator: ", ")
    }
}

/// An article a saint's description is drawn from.
public struct SaintSource: Codable, Hashable, Sendable {
    public let title: String
    public let url: String

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }
}

/// A short quote of a saint's own words and its source (a work, letter or occasion).
public struct SaintQuote: Codable, Hashable, Sendable {
    public let text: String
    public let source: String

    public init(text: String, source: String) {
        self.text = text
        self.source = source
    }
}
