//
//  SaintsDatabase.swift
//  DailyReadings
//
//  Created for DailyReadings Catholic Daily Readings App.
//  iOS 17+ | Swift 6+
//

import Foundation

/// A celebration's description and the articles it comes from.
public struct CelebrationText: Sendable {
    public let summary: String
    public let sources: [SaintSource]
}

/// Service for loading, indexing, and querying Catholic saints from the bundled `saints.json` database.
/// Provides fast, synchronous, thread-safe lookups by date, feast day, ID, and keyword.
public final class SaintsDatabase: Sendable {
    /// Shared singleton instance loaded from the main bundle.
    public static let shared = SaintsDatabase()

    /// All loaded saints in alphabetical or source order.
    public let allSaints: [Saint]
    /// Saints indexed by "MM-DD" feast day string (e.g. "11-02").
    private let saintsByFeastDate: [String: [Saint]]
    /// Saints indexed by unique identifier.
    private let saintsById: [String: Saint]
    /// Descriptions of the celebrations in `LiturgicalCelebrationBlurbs`, by id.
    private let celebrations: [String: CelebrationText]

    /// Designated initializer. Loads saints from the specified bundle URL or bundled `saints.json`.
    /// Falls back to embedded prominent saints if the bundled file is missing.
    public init(customURL: URL? = nil) {
        var loadedSaints: [Saint] = []
        var loadedCelebrations: [String: CelebrationText] = [:]

        let url = customURL ?? Bundle.main.url(forResource: "saints", withExtension: "json")
        if let url, let data = try? Data(contentsOf: url) {
            loadedSaints = Self.parseSaintsJSON(from: data)
            loadedCelebrations = Self.parseCelebrations(from: data)
        }
        
        if loadedSaints.isEmpty {
            // Built-in foundational saints fallback
            loadedSaints = Self.seedSaints
        }

        self.allSaints = loadedSaints
        
        // Build indices
        var byDate: [String: [Saint]] = [:]
        var byId: [String: Saint] = [:]

        for saint in loadedSaints {
            let normalizedDate = Self.normalizeFeastDate(saint.feastDate)
            byDate[normalizedDate, default: []].append(saint)
            byId[saint.id] = saint
        }

        self.saintsByFeastDate = byDate
        self.saintsById = byId
        self.celebrations = loadedCelebrations
    }

    // MARK: - Query APIs

    /// Returns the primary Saint or Liturgical Celebration commemorated on a specific calendar Date.
    ///
    /// If `liturgicalDay` is provided and represents a major Solemnity, Feast of the Lord,
    /// or movable solemnity (e.g. Easter, Pentecost, Lateran Basilica, Christ the King),
    /// the celebration blurb takes precedence to explain the sacred mystery celebrated on that day.
    public func saint(for date: Date, liturgicalDay: LiturgicalDay? = nil) -> Saint? {
        // 1. A solemnity, feast of the Lord or movable celebration named by the liturgical day.
        if let liturgicalDay, let feast = LiturgicalCelebrationBlurbs.feast(forTitle: liturgicalDay.title, date: date) {
            return feast
        }

        // 2. The day's saints, calendar celebrations first. When the liturgical day names one of
        //    them (an optional memorial chosen over the first), prefer it. Only this date's
        //    saints are searched: a name match across the whole year found the wrong Peter or
        //    John on another saint's day.
        let key = Self.feastDateKey(from: date)
        let daySaints = saintsByFeastDate[key] ?? []
        if let liturgicalDay {
            let title = Self.matchKey(liturgicalDay.title)
            if let named = daySaints.first(where: { saint in
                let name = Self.matchKey(saint.name)
                return name.count > 3 && title.contains(name)
            }) {
                return named
            }
        }
        if let primary = daySaints.first {
            return primary
        }

        // 3. Guaranteed fallback to seed saints if date matches
        return Self.seedSaints.first { Self.normalizeFeastDate($0.feastDate) == key }
    }

    /// Lowercased letters only, without a leading "saint"/"saints"/"the", for matching a calendar
    /// title against a saint's name.
    static func matchKey(_ text: String) -> String {
        var t = text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        if let comma = t.firstIndex(of: ",") { t = String(t[..<comma]) }
        for prefix in ["saints ", "saint ", "blessed ", "the "] where t.hasPrefix(prefix) {
            t.removeFirst(prefix.count)
        }
        return t.filter(\.isLetter)
    }

    /// The Wikipedia description and sources for a celebration in `LiturgicalCelebrationBlurbs`.
    public func celebration(id: String) -> CelebrationText? {
        celebrations[id]
    }

    /// Legacy convenience query without liturgical day metadata.
    public func saint(for date: Date) -> Saint? {
        saint(for: date, liturgicalDay: nil)
    }

    /// Returns all saints commemorated on a specific calendar Date.
    public func saints(for date: Date) -> [Saint] {
        let key = Self.feastDateKey(from: date)
        return saintsByFeastDate[key] ?? []
    }

    /// Returns the primary saint for a specific month (1-12) and day (1-31).
    public func saint(forMonth month: Int, day: Int) -> Saint? {
        let key = String(format: "%02d-%02d", month, day)
        return saintsByFeastDate[key]?.first
    }

    /// Returns all saints for a specific month and day.
    public func saints(forMonth month: Int, day: Int) -> [Saint] {
        let key = String(format: "%02d-%02d", month, day)
        return saintsByFeastDate[key] ?? []
    }

    /// Looks up a saint by unique ID.
    public func saint(id: String) -> Saint? {
        saintsById[id]
    }

    /// Searches saints by name, title, or patronage.
    public func search(query: String) -> [Saint] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return allSaints }

        return allSaints.filter { saint in
            if saint.name.lowercased().contains(clean) { return true }
            if let title = saint.title, title.lowercased().contains(clean) { return true }
            if let patronages = saint.patronages, patronages.contains(where: { $0.lowercased().contains(clean) }) {
                return true
            }
            if saint.biography.lowercased().contains(clean) { return true }
            return false
        }
    }

    // MARK: - Helpers

    /// Parses the bundled `saints.json` structure (a dictionary keyed by "MM-DD", containing saint arrays).
    private static func parseSaintsJSON(from data: Data) -> [Saint] {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var results: [Saint] = []
        for (dateKey, val) in jsonObject {
            guard dateKey.count == 5, dateKey.dropFirst(2).first == "-", let dayDict = val as? [String: Any] else { continue }
            guard let saintsArray = dayDict["saints"] as? [[String: Any]] else { continue }

            for (idx, saintDict) in saintsArray.enumerated() {
                guard let name = saintDict["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                let era = saintDict["era"] as? String
                let patronage = saintDict["patronage"] as? [String]
                let legacy = saintDict["legacy"] as? String
                let summary = (saintDict["summary"] as? String) ?? ""
                let image = saintDict["image"] as? String
                let slug = name.lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { !$0.isEmpty }
                    .joined(separator: "_")
                let id = "\(dateKey)_\(slug)_\(idx)"

                var saint = Saint(
                    id: id,
                    name: name,
                    feastDate: dateKey,
                    title: legacy,
                    era: era,
                    biography: summary,
                    patronages: patronage,
                    imageURL: image
                )
                saint.born = saintDict["born"] as? String
                saint.died = saintDict["died"] as? String
                saint.birthplace = saintDict["birthplace"] as? String
                saint.religiousOrder = saintDict["order"] as? String
                saint.canonized = saintDict["canonized"] as? String
                if let quote = saintDict["quote"] as? [String: Any],
                   let text = quote["text"] as? String, let source = quote["source"] as? String {
                    saint.quote = SaintQuote(text: text, source: source)
                }
                saint.sources = Self.parseSources(saintDict["sources"])
                saint.rank = saintDict["rank"] as? String
                saint.martyrologyDay = (saintDict["martyrology"] as? [String: Any])?["label"] as? String
                results.append(saint)
            }
        }
        return results
    }

    private static func parseSources(_ value: Any?) -> [SaintSource] {
        (value as? [[String: Any]] ?? []).compactMap { source in
            guard let title = source["title"] as? String, let url = source["url"] as? String else { return nil }
            return SaintSource(title: title, url: url)
        }
    }

    /// Parses the `celebrations` section: Wikipedia descriptions for the feasts in
    /// `LiturgicalCelebrationBlurbs`.
    private static func parseCelebrations(from data: Data) -> [String: CelebrationText] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let section = root["celebrations"] as? [String: [String: Any]] else { return [:] }
        var result: [String: CelebrationText] = [:]
        for (id, entry) in section {
            guard let summary = entry["summary"] as? String, !summary.isEmpty else { continue }
            result[id] = CelebrationText(summary: summary, sources: parseSources(entry["sources"]))
        }
        return result
    }

    /// Converts a Gregorian Date into "MM-DD" format.
    public static func feastDateKey(from date: Date) -> String {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return String(format: "%02d-%02d", month, day)
    }

    /// Normalizes a feast date string to two-digit "MM-DD".
    private static func normalizeFeastDate(_ dateString: String) -> String {
        let parts = dateString.split(separator: "-")
        if parts.count == 2, let m = Int(parts[0]), let d = Int(parts[1]) {
            return String(format: "%02d-%02d", m, d)
        }
        return dateString
    }

    // MARK: - Embedded Seed Saints (Guaranteed Fallback)

    private static let seedSaints: [Saint] = [
        Saint(
            id: "all_souls",
            name: "The Commemoration of All the Faithful Departed (All Souls)",
            feastDate: "11-02",
            title: "Commemoration of the Universal Church",
            era: "11th Century (Abbey of Cluny)",
            biography: "The Church commemorates all who have died in the peace of Christ, offering prayers, alms, and the Holy Sacrifice of the Mass for the purification of souls in Purgatory so they may enter into the joy of the Heavenly Kingdom.",
            patronages: ["Holy Souls in Purgatory"],
            imageURL: nil
        ),
        Saint(
            id: "all_saints",
            name: "Solemnity of All Saints",
            feastDate: "11-01",
            title: "Solemnity",
            era: "Early Church",
            biography: "A solemn feast celebrating the communion of saints, honoring all holy men and women who have entered Heaven, recognized and unrecognized, who stand before the throne of God in eternal adoration.",
            patronages: ["The Church Triumphant"],
            imageURL: nil
        ),
        Saint(
            id: "augustine_hippo",
            name: "St. Augustine of Hippo",
            feastDate: "08-28",
            title: "Bishop and Doctor of the Church",
            era: "Early Church (354-430 AD)",
            biography: "Converted through the relentless prayers of his mother St. Monica, Augustine became Bishop of Hippo and one of the greatest theologians of the Latin Church, authoring the Confessions and The City of God.",
            patronages: ["Theologians", "Printers", "Brewers"],
            imageURL: nil
        ),
        Saint(
            id: "thomas_aquinas",
            name: "St. Thomas Aquinas",
            feastDate: "01-28",
            title: "Priest and Doctor of the Church (Doctor Angelicus)",
            era: "13th Century (1225-1274)",
            biography: "Dominican friar and master of scholastic philosophy, Thomas Aquinas harmonized faith and reason. His masterpiece, the Summa Theologiae, remains the bedrock of Catholic theology.",
            patronages: ["Academics", "Theologians", "Students", "Catholic Schools"],
            imageURL: nil
        ),
        Saint(
            id: "francis_assisi",
            name: "St. Francis of Assisi",
            feastDate: "10-04",
            title: "Religious Founder",
            era: "13th Century (1181-1226)",
            biography: "Renouncing his family's wealth, Francis embraced radical evangelical poverty, founded the Franciscan Order, received the sacred stigmata, and radiated Christ's peace to all of creation.",
            patronages: ["Ecology", "Animals", "Italy", "Peace"],
            imageURL: nil
        ),
        Saint(
            id: "joseph_spouse",
            name: "St. Joseph, Spouse of the Blessed Virgin Mary",
            feastDate: "03-19",
            title: "Patron of the Universal Church",
            era: "1st Century",
            biography: "The chaste spouse of Mary and foster father of Jesus Christ, St. Joseph was a righteous carpenter of Nazareth who quietly and faithfully protected the Holy Family.",
            patronages: ["Universal Church", "Fathers", "Workers", "A Happy Death"],
            imageURL: nil
        ),
        Saint(
            id: "therese_lisieux",
            name: "St. Thérèse of Lisieux",
            feastDate: "10-01",
            title: "Virgin and Doctor of the Church",
            era: "19th Century (1873-1897)",
            biography: "Carmelite nun known as the 'Little Flower,' she taught the 'Little Way' of spiritual childhood—seeking holiness through doing small, ordinary actions with extraordinary love for Jesus.",
            patronages: ["Missions", "Florists", "Pilots", "Tuberculosis patients"],
            imageURL: nil
        )
    ]
}
