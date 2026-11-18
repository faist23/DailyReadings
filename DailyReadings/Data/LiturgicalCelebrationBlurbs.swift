//
//  LiturgicalCelebrationBlurbs.swift
//  DailyReadings
//
//  Created for DailyReadings Catholic Daily Readings App.
//  iOS 17+ | Swift 6+
//

import Foundation

/// Repository of comprehensive liturgical blurbs for Solemnities, Feasts of the Lord,
/// and movable celebrations of the Catholic Church.
public enum LiturgicalCelebrationBlurbs {
    
    /// Returns a `Saint` representation of a liturgical feast if one matches the given title or date.
    public static func feast(forTitle title: String, date: Date) -> Saint? {
        let cleanTitle = title.lowercased()
        
        for celebration in allCelebrations {
            for matchKey in celebration.matchKeywords {
                if cleanTitle.contains(matchKey) {
                    return celebration.toSaint(feastDate: SaintsDatabase.feastDateKey(from: date))
                }
            }
        }
        return nil
    }
    
    public struct FeastCelebration: Sendable {
        public let id: String
        public let name: String
        public let title: String
        public let biography: String
        public let matchKeywords: [String]
        
        /// The description comes from the feast's Wikipedia article (bundled in saints.json);
        /// `biography` is only a fallback if that is missing.
        public func toSaint(feastDate: String) -> Saint {
            let text = SaintsDatabase.shared.celebration(id: id)
            var saint = Saint(
                id: id,
                name: name,
                feastDate: feastDate,
                title: title,
                biography: text?.summary ?? biography
            )
            saint.sources = text?.sources ?? []
            return saint
        }
    }
    
    public static let allCelebrations: [FeastCelebration] = [
        FeastCelebration(
            id: "lateran_basilica",
            name: "The Dedication of the Lateran Basilica",
            title: "Feast",
            biography: "Known as the Mother and Head of all churches in Rome and the world (Omnium Urbis et Orbis Ecclesiarum Mater et Caput), the Archbasilica of Saint John Lateran is the cathedral seat of the Bishop of Rome. Dedicated in 324 AD by Pope Sylvester I on land donated by Emperor Constantine, this feast celebrates not merely a building of stone, but the living Church of Jesus Christ, the holy temple of God built of living stones.",
            matchKeywords: ["lateran", "dedication of the lateran"]
        ),
        FeastCelebration(
            id: "all_saints",
            name: "Solemnity of All Saints",
            title: "Solemnity",
            biography: "A solemn feast celebrating the communion of saints, honoring all holy men and women who have entered Heaven, recognized and unrecognized, who stand before the throne of God in eternal adoration and intercede for the Pilgrim Church on earth.",
            matchKeywords: ["all saints"]
        ),
        FeastCelebration(
            id: "all_souls",
            name: "The Commemoration of All the Faithful Departed (All Souls)",
            title: "Commemoration",
            biography: "The Church commemorates all who have died in the peace of Christ, offering prayers, alms, and the Holy Sacrifice of the Mass for the purification of souls in Purgatory so they may enter into the fullness of heavenly glory.",
            matchKeywords: ["all souls", "faithful departed"]
        ),
        FeastCelebration(
            id: "christmas",
            name: "The Nativity of the Lord (Christmas)",
            title: "Solemnity",
            biography: "The Word became flesh and dwelt among us. Christmas commemorates the birth of Jesus Christ in Bethlehem of Judea, fulfilling the ancient prophecies and inaugurating the mystery of our redemption through the divine Incarnation.",
            matchKeywords: ["nativity of the lord", "christmas"]
        ),
        FeastCelebration(
            id: "mary_mother_of_god",
            name: "Solemnity of Mary, The Holy Mother of God",
            title: "Solemnity · Octave Day of Christmas",
            biography: "On the octave of Christmas, the Church honors the Blessed Virgin Mary under her supreme dogma as Theotokos—the God-bearer or Mother of God—proclaimed at the Council of Ephesus in 431 AD. She who brought forth the Prince of Peace remains our perpetual intercessor.",
            matchKeywords: ["mother of god"]
        ),
        FeastCelebration(
            id: "epiphany",
            name: "The Epiphany of the Lord",
            title: "Solemnity",
            biography: "Epiphany commemorates the manifestation of Jesus Christ to the Gentiles, represented by the Magi from the East who followed the star to Bethlehem to offer gifts of gold, frankincense, and myrrh to the newborn King of kings.",
            matchKeywords: ["epiphany"]
        ),
        FeastCelebration(
            id: "baptism_of_the_lord",
            name: "The Baptism of the Lord",
            title: "Feast of the Lord",
            biography: "Commemorating Jesus' baptism by John the Baptist in the Jordan River. As Jesus emerged from the water, the heavens opened, the Holy Spirit descended as a dove, and the Father proclaimed: 'This is my beloved Son, with whom I am well pleased.'",
            matchKeywords: ["baptism of the lord"]
        ),
        FeastCelebration(
            id: "presentation_of_the_lord",
            name: "The Presentation of the Lord (Candlemas)",
            title: "Feast of the Lord",
            biography: "Commemorating the presentation of the infant Jesus in the Temple forty days after His birth in obedience to the Mosaic Law. The aged prophet Simeon acclaimed Him as 'a light for revelation to the Gentiles, and the glory of your people Israel.'",
            matchKeywords: ["presentation of the lord", "candlemas"]
        ),
        FeastCelebration(
            id: "ash_wednesday",
            name: "Ash Wednesday",
            title: "Day of fasting and abstinence",
            biography: "Ash Wednesday inaugurates the forty days of Lent. The faithful receive blessed ashes upon their foreheads with the solemn reminder: 'Remember that you are dust, and to dust you shall return,' entering into a season of prayer, fasting, and almsgiving.",
            matchKeywords: ["ash wednesday"]
        ),
        FeastCelebration(
            id: "annunciation",
            name: "The Annunciation of the Lord",
            title: "Solemnity",
            biography: "Commemorates the Archangel Gabriel's announcement to the Virgin Mary in Nazareth that she would conceive the Son of the Most High by the Holy Spirit, and Mary's fiat: 'Behold, I am the handmaid of the Lord; let it be to me according to your word.'",
            matchKeywords: ["annunciation"]
        ),
        FeastCelebration(
            id: "palm_sunday",
            name: "Palm Sunday of the Passion of the Lord",
            title: "Beginning of Holy Week",
            biography: "Opening Holy Week, Palm Sunday commemorates Christ's triumphal entry into Jerusalem greeted with palm branches and cries of 'Hosanna,' followed immediately by the proclamation of the Passion narrative uniting His royal entry with His cross.",
            matchKeywords: ["palm sunday"]
        ),
        FeastCelebration(
            id: "holy_thursday",
            name: "Thursday of the Lord's Supper (Holy Thursday)",
            title: "Paschal Triduum",
            biography: "Inaugurating the Paschal Triduum, the Mass of the Lord's Supper commemorates the Last Supper where Christ instituted the Holy Eucharist and the Ministerial Priesthood, washing the disciples' feet in the supreme example of humble love.",
            matchKeywords: ["holy thursday", "lord's supper"]
        ),
        FeastCelebration(
            id: "good_friday",
            name: "Friday of the Passion of the Lord (Good Friday)",
            title: "Paschal Triduum",
            biography: "The solemn commemoration of the Passion, Crucifixion, and Death of Our Lord Jesus Christ on Mount Calvary. In prayerful silence and fasting, the Church venerates the Wood of the Cross on which hung the Salvation of the world.",
            matchKeywords: ["good friday", "passion of the lord"]
        ),
        FeastCelebration(
            id: "holy_saturday",
            name: "Holy Saturday",
            title: "Paschal Triduum",
            biography: "The day of the Great Silence; Christ lies in the tomb having descended to the realm of the dead to announce deliverance to the righteous souls awaiting salvation. The Church watches in quiet expectation for the Easter Vigil.",
            matchKeywords: ["holy saturday"]
        ),
        FeastCelebration(
            id: "easter_sunday",
            name: "Easter Sunday of the Resurrection of the Lord",
            title: "Easter Sunday",
            biography: "The greatest feast of the Christian year, celebrating Jesus Christ's triumphant resurrection from the dead. Christ has trampled down death by death, bestowing new and everlasting life upon all believers. Alleluia!",
            matchKeywords: ["easter sunday", "resurrection of the lord"]
        ),
        FeastCelebration(
            id: "divine_mercy",
            name: "Divine Mercy Sunday (Second Sunday of Easter)",
            title: "Second Sunday of Easter",
            biography: "Concluding the Octave of Easter, Divine Mercy Sunday celebrates the infinite mercy of God revealed in the pierced heart of Christ, as communicated through the revelations of Jesus to Saint Maria Faustina Kowalska.",
            matchKeywords: ["divine mercy", "second sunday of easter"]
        ),
        FeastCelebration(
            id: "ascension",
            name: "Solemnity of the Ascension of the Lord",
            title: "Solemnity",
            biography: "Commemorates Jesus ascending bodily into heaven forty days after His resurrection, commissioning the Apostles to 'go into all the world and proclaim the Gospel to every creature,' promising His abiding presence until the end of time.",
            matchKeywords: ["ascension"]
        ),
        FeastCelebration(
            id: "pentecost",
            name: "Pentecost Sunday",
            title: "Solemnity",
            biography: "Fifty days after the Resurrection, the Holy Spirit descended upon Mary and the Apostles in tongues of fire and the sound of a rushing wind, empowering them with heavenly gifts and marking the public birthday of the Church.",
            matchKeywords: ["pentecost"]
        ),
        FeastCelebration(
            id: "holy_trinity",
            name: "Solemnity of the Most Holy Trinity",
            title: "Solemnity",
            biography: "Celebrating the central mystery of the Christian faith: one God in three distinct, divine Persons—the Father, the Son, and the Holy Spirit—united in an eternal communion of divine knowledge and boundless love.",
            matchKeywords: ["most holy trinity", "holy trinity"]
        ),
        FeastCelebration(
            id: "corpus_christi",
            name: "The Most Holy Body and Blood of Christ (Corpus Christi)",
            title: "Solemnity",
            biography: "Solemn feast honoring the true, real, and substantial presence of Jesus Christ—Body, Blood, Soul, and Divinity—in the sacrament of the Most Holy Eucharist, traditionally celebrated with solemn adoration and public Eucharistic processions.",
            matchKeywords: ["body and blood of christ", "corpus christi"]
        ),
        FeastCelebration(
            id: "sacred_heart",
            name: "Solemnity of the Most Sacred Heart of Jesus",
            title: "Solemnity",
            biography: "Honoring the physical heart of Jesus as the radiant symbol of His infinite and compassionate love for humanity. The devotion was renewed through the apparitions of Christ to Saint Margaret Mary Alacoque at Paray-le-Monial.",
            matchKeywords: ["sacred heart of jesus", "sacred heart"]
        ),
        FeastCelebration(
            id: "transfiguration",
            name: "The Transfiguration of the Lord",
            title: "Feast of the Lord",
            biography: "Commemorating Jesus revealing His divine majesty in blinding, uncreated light on Mount Tabor before Peter, James, and John. Flanked by Moses and Elijah, the Father's voice boomed: 'This is my beloved Son; listen to Him.'",
            matchKeywords: ["transfiguration"]
        ),
        FeastCelebration(
            id: "assumption",
            name: "The Assumption of the Blessed Virgin Mary",
            title: "Solemnity",
            biography: "Commemorating Mary, having completed the course of her earthly life, being assumed body and soul into heavenly glory, where she reigns beside her Son as Queen of Heaven and an earnest pledge of the resurrection of the just.",
            matchKeywords: ["assumption of the blessed virgin", "assumption of mary"]
        ),
        FeastCelebration(
            id: "exaltation_of_the_cross",
            name: "The Exaltation of the Holy Cross",
            title: "Feast",
            biography: "Celebrating the True Cross discovered in Jerusalem by Saint Helena and consecrated at the Basilica of the Holy Sepulchre in 335 AD. The Cross, once an instrument of shame and torment, has become the glorious sign of salvation and victory.",
            matchKeywords: ["exaltation of the holy cross", "holy cross"]
        ),
        FeastCelebration(
            id: "christ_the_king",
            name: "Solemnity of Our Lord Jesus Christ, King of the Universe",
            title: "Solemnity",
            biography: "The triumphant climax of the liturgical year, celebrating Jesus Christ as the universal Lord of history, ruler of nations, and sovereign of hearts, anticipating the final restoration of all things in His kingdom of truth, justice, and peace.",
            matchKeywords: ["king of the universe", "christ the king"]
        ),
        FeastCelebration(
            id: "immaculate_conception",
            name: "The Immaculate Conception of the Blessed Virgin Mary",
            title: "Solemnity · Patronal feast of the United States",
            biography: "Honoring the singular grace by which the Virgin Mary was preserved immune from all stain of original sin from the first instant of her conception, in view of the foreseen merits of Jesus Christ, Savior of the human race.",
            matchKeywords: ["immaculate conception"]
        )
    ]
}
