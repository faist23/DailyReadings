# DailyReadings — Architecture, Engineering & Codebase Guide

This document provides a comprehensive technical overview of **DailyReadings**, designed to brief code reviewers, auditing tools, and AI assistants (such as Claude AI) on the application's architecture, design invariants, data flow, concurrency model, and intentional engineering decisions.

---

## 1. Executive Summary & Product Vision

**DailyReadings** is a native iOS Catholic devotional application built for iOS 17+ using Swift 6, SwiftUI, and SwiftData. Its mission is to provide a calm, sacred, and distraction-free environment for daily prayer and scripture reading centered on the Catholic Mass.

### Key Tenets
1. **Contemplative Missal Aesthetic**: Typographical hierarchy inspired by classic liturgical missals (New York serif, subtle gold accents, rubric red `℟.` antiphons, and warm scripture paper surfaces).
2. **100% Offline Resilience**: Users must be able to read Mass readings in church basements, airplanes, or rural retreats without internet connectivity.
3. **Canonical Liturgical Accuracy**: Computes feast days, liturgical seasons, vestment colors, and Sunday/weekday cycles entirely on-device using official Catholic liturgical algorithms (General Instruction of the Roman Missal & USCCB norms).
4. **Reverent Audio Experience**: Hands-free, sequential spoken-word recitation of the Mass readings and prayers with lock screen controls, background playback, and seasonal illuminated artwork.

---

## 2. Technical Stack & Environment

| Component | Specification |
| :--- | :--- |
| **Platform** | iOS 17.0+ (iPhone & iPad universal) |
| **Language** | Swift 6.0 (`SWIFT_STRICT_CONCURRENCY = complete`) |
| **UI Framework** | SwiftUI (declarative, `@Observable` state pattern) |
| **Persistence** | SwiftData (`@Model CachedReading`) + SQLite (`bible_webc.sqlite` default modern + `bible_drb.sqlite` traditional) + `UserDefaults` |
| **Audio** | `AVFoundation` (`AVSpeechSynthesizer`, `AVAudioSession`), `MediaPlayer` (`MPNowPlayingInfoCenter`) |
| **Project Spec** | [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`) generating `DailyReadings.xcodeproj` |
| **Test Suite** | `DailyReadingsTests` (104 unit tests: `LiturgicalCalendarTests`, `ScriptureEngineTests`, `LectionaryCoverageTests`, `AudioPlaybackTests`, `NotificationSchedulingTests`, `ReadingsReloadTests`, `SaintLifeFactsTests`, `SaintCalendarTests`) |
| **Bundle ID** | `com.ridepro.DailyReadings` |
| **Team ID** | `DT58WA8N32` |
| **Privacy** | Apple Privacy Manifest compliant (`DailyReadings/PrivacyInfo.xcprivacy`) |

---

## 3. High-Level Architecture

DailyReadings follows a decoupled, unidirectional architecture structured into four distinct layers:

```
┌────────────────────────────────────────────────────────────────────────┐
│                          PRESENTATION LAYER                            │
│  SwiftUI Views: TodayView, CalendarView, PrayersView, SettingsView     │
│  @Observable ViewModels: TodayViewModel, CalendarViewModel             │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│                       DOMAIN & LITURGICAL ENGINE                       │
│  LiturgicalCalendar, Computus, LiturgicalRank, LiturgicalSeason        │
│  Models: LiturgicalDay, Reading, DailyReadings, Prayer, RosaryMystery  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│                       DATA & REPOSITORY LAYER                          │
│  ReadingsRepository (Multi-tier translation & cache coordinator)       │
│  ├── BibleDatabase.webc (Bundled WEB-C SQLite Actor — Modern Default)  │
│  ├── BibleDatabase.drb (Bundled Douay-Rheims SQLite Actor — Tradition) │
│  ├── EvangelizioService (Online NAB Lectionary API + 30-Day Prefetch)  │
│  └── SwiftData Cache (CachedReading)                                  │
│  Auxiliary Providers: PsalmResponseProvider, VerseOfTheDayProvider,    │
│                       PrayersRepository, SaintsDatabase, PericoreIndex │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│                    SERVICES & HARDWARE INTEGRATION                     │
│  AudioReadingPlayer (Background audio, speech, lock screen artwork)    │
│  NotificationManager (Holy Days of Obligation vigil push alerts)       │
│  BookmarkManager (Scripture passage bookmark persistence)              │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Subsystem Deep-Dive

### 4.1. Canonical Liturgical Engine (`DailyReadings/Engine/`)
The liturgical engine operates entirely offline without third-party network dependencies.
* **`Computus.swift`**: Full implementation of the Meeus/Jones/Butcher algorithm to calculate Easter Sunday for any Gregorian year, from which all movable feasts are derived (Ash Wednesday, Palm Sunday, Holy Thursday, Good Friday, Ascension, Pentecost, Trinity Sunday, Corpus Christi, Sacred Heart, Christ the King).
* **`LiturgicalCalendar.swift`**: Evaluates season (Advent, Christmas, Ordinary Time, Lent, Triduum, Easter), cycle (Sunday Year A/B/C, Weekday Cycle I/II), rank precedence (Solemnity > Feast > Memorial > Optional Memorial > Ferial), and psalter week (Weeks I–IV).
* **`FixedSolemnities.swift`**: Calculates fixed universal and USCCB solemnities and feasts (e.g., Immaculate Conception, Assumption, All Saints). Evaluates USCCB abrogation rules (when Jan 1, Aug 15, or Nov 1 falls on a Saturday or Monday, the obligation to attend Mass is abrogated).
* **`LiturgicalColor.swift` & `LiturgicalColors.swift`**: Maps GIRM canonical colors (White, Red, Green, Violet, Rose, Black) with tailored tints for light/dark mode. Implements `primaryButtonBackground` using burnished gold (`#AF821E`) for White feasts to guarantee high WCAG contrast against white text.

### 4.2. Multi-Tier Bible & Lectionary Pipeline (`DailyReadings/Data/`)
A core design requirement is transparent scripture attribution and zero-compromise offline devotional reading:
1. **Tier 1: Bundled World English Bible (Catholic Edition, WEB-C) [Default]**:
   - Bundled in `bible_webc.sqlite` (35,379 verses, all 73 Catholic books including Greek Esther and Daniel).
   - Completely public domain; modern American English. It uses English verse numbering, which differs from the Lectionary's in places (psalm titles, Joel, Malachi, Zechariah 2, Isaiah 9 and 64, the Romans doxology). `versification.json` maps between them; see 4.2.1.
   - Transparently labeled in-app: *"World English Bible (Catholic edition), public domain. Private devotional reading; not the liturgical text read at Mass."*
2. **Tier 2: Bundled Douay-Rheims Bible (DRB) [Traditional]**:
   - The historic Douay-Rheims (1609/1752 Challoner revision) is public domain, bundled in `bible_drb.sqlite`.
   - Hand-written, test-pinned Hebrew ↔ Vulgate rules cover Psalms, Joel and Malachi (e.g. lectionary Psalm 23 maps to Vulgate Psalm 22 *"The Lord ruleth me"*). `versification.json` covers the other books. Sirach is not mapped; see section 8.
   - Transparently labeled: *"Douay-Rheims Bible (Challoner Revision, 1752), public domain. Translated from the Latin Vulgate."*
3. **Tier 3: Online NAB Testing Tier (`EvangelizioService`) & USCCB Links**:
   - The New American Bible (NAB/NABRE) is the liturgical translation for US dioceses. Digital permissions are administered by the Confraternity of Christian Doctrine (CCD) via the USCCB.
   - Supported for personal developer testing via Evangelizo feed with polite 30-day SwiftData pre-fetching (`CachedReading`), full CCD copyright attribution, and direct links to official daily readings at `bible.usccb.org`.
   - The feed has no Gospel Acclamation. `ReadingsRepository.backfillGospelAcclamation` adds the Lectionary's, read from WEB-C and labelled WEB-C, only when the feed's Gospel is the Lectionary's Gospel for the day; otherwise the feed carries a different Mass and nothing is added. No other reading type is ever filled in from the index.
   - When NAB is chosen but the readings shown are WEB-C (offline with nothing cached), `TodayViewModel.translationNotice` is set and the screen shows it with a Retry button. Pull-to-refresh and Retry pass `forceRefresh`; if the download fails, the cached NAB copy is used before WEB-C.
   - Each reading carries the translation its text is in. Labels use `Reading.translationDisplayName`, never the translation setting: the text can differ from the setting (WEB-C when NAB is offline, the WEB-C acclamation, an old bookmark).
   - **Catholic American Bible (CAB) Roadmap**: The USCCB permissions office has placed digital licensing on hold pending the 2027 release of the Catholic American Bible. DailyReadings is registered on the digital permissions waitlist (`nabperm@usccb.org`).
#### 4.2.1. Verse numbering (`VersificationMap`, `versification.json`)
The Lectionary cites Scripture in Hebrew verse numbering. Neither bundled Bible uses it throughout, so `BibleDatabase.queryVerses(citation:)` works in three steps:
1. List the cited verses in Lectionary numbering. Open-ended ranges ("7:25—8:6") use the Lectionary chapter lengths stored in `versification.json`.
2. Translate each verse to the Bible's own numbering through `VersificationMap` (plus the hand-written Vulgate rules for Psalms, Joel and Malachi, and a rule for "Esther C").
3. Read the verses from SQLite. For psalms, the title line WEB-C prints at the start of verse 1 is removed, because a responsorial psalm never includes it.

`versification.json` is generated by `Scripts/build_versification.py` from the Copenhagen Alliance standard mappings (`eng`, `org`, `vul`) and the WEB-C USFM source. The script only accepts a mapping row when the bundled SQLite file has the chapter length the standard table expects, and it leaves a whole book unmapped if any row points past the end of a chapter (this is why Douay-Rheims Jonah is unmapped).

Citation parsing rules worth knowing:
- "4:12-23 or 4:12-17" is a long and a short form. The long form is read.
- An open-ended range that starts past the end of a chapter cites nothing in that chapter. It never becomes "the whole chapter".
- "II Corinthians" and a book glued to its chapter ("Psalm103:1-2") are accepted.
- "and" lists verses like a comma ("6 and 8" is verses 6 and 8). Before Build 20 the verses after an "and" were dropped, which cut verses from the psalm on about one day in five.

#### 4.2.2. Lectionary index (`PericoreIndex`, `lectionary_dates.json`, `lectionary.json`)
`PericoreIndex.entries(for:)` answers "which readings belong to this liturgical day":
1. **Dated index** (`lectionary_dates.json`): readings by calendar date. It has usable data from 2023-01-01 to 2027-05-31; later entries are placeholders.
2. **Cycle index** (`lectionary.json`, 966 keys): the same readings keyed by what the day *is*, so any year resolves. Keys:
   - a fixed-date solemnity or feast: `fixed_08_15`
   - an obligatory memorial's own readings, laid over the weekday's: `proper_10_02`. Only days the calendar names as an obligatory memorial get this key, and a psalm counts as the memorial's own only together with its own First Reading; otherwise a reading that fell on the same date in two dated years would replace the weekday's in every year.
   - a place in the season: `ot_23_tuesday`, `lent_sun_3`, `advent_dec_18`, `christmas_after_epiphany_monday`, `triduum_friday`
   - a base key holds what every cycle shares; a suffixed key holds what is particular to one cycle (`ot_23_tuesday_I` holds Year I's First Reading and Psalm, `ot_23_tuesday` the shared Gospel; `lent_sun_3_A` is Year A).
3. **Nothing.** If neither index has the day, the result is empty and the UI shows its empty state. The app never invents readings.

For Ascension Sunday, Pentecost and Holy Thursday the cycle index is used even when a dated entry exists, because the dated data carries a different Mass for those days (the Seventh Sunday of Easter, the Pentecost Vigil, the Chrism Mass).

`lectionary.json` is generated by `Scripts/BuildLectionaryIndex` from the dated data plus `Scripts/lectionary_seeds.json`, a small set of hand-entered readings for days the dated data cannot supply. Where a seed and the dated data cite the same reading, the seed's verse letters and response win (the data's psalm responses are sometimes a guess by citation); where they cite different readings, the data wins. The build is deterministic: ties are broken by reading, not by dictionary order, so the same inputs always give the same file. Run it with `--holdout 2026-01-01` to build from earlier dates only and report how well the index predicts later ones.

4. **Responsorial Psalm Enhancements (`PsalmResponseProvider`, `BibleDatabase.formattedPsalmText`)**: Provides canonical lectionary responses for all 150 Psalms and Biblical Canticles (Exodus 15, Daniel 3, Luke 1, etc.), guaranteeing the red rubric **℟.** banner and stanza cues even if third-party APIs truncate them. Responsorial Psalms are formatted into distinct stanzas separated by `\n\n`, and shared verses across adjacent stanzas (e.g., Psalm 146: 8-9a and 9bc-10) are cleanly split along clause and sentence boundaries without duplicate text. Stanzas break at commas; the Lectionary joins the verses of one stanza with "and" ("Psalm 85:8 and 10, 11-12, 13-14" is three stanzas). Where the dated data spells a psalm both ways, `PericoreIndex` uses the spelling with "and" for every day (`stanzaSpellings`), so a day whose data dropped the "and" still gets the right stanzas. A citation that never carries the "and" in the data is still split at every comma.

### 4.3. Reverent Audio Recitation Engine (`AudioReadingPlayer.swift`)
* **Background Audio Capability**: Enabled via `UIBackgroundModes = ["audio"]` and `AVAudioSession(category: .playback, mode: .spokenAudio)`.
* **Lock Screen & Remote Command Center**: Full `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` integration (play, pause, skip forward/backward).
* **Thread Safety Architecture**: To avoid `_dispatch_assert_queue_fail` crashes (since `MPMediaItemArtwork` handlers run on background `Thread 8` outside Swift's main actor), artwork creation is isolated in `nonisolated public static func makeMediaItemArtwork(from:)`.
* **Dynamic Missal Artwork Generator**: Generates 600×600 illuminated missal book cover art on the fly, colored according to the day's liturgical season with double gold foil borders and Latin cross emblems.
* **Natural Voice Engine**: Automatically filters out legacy 1980s robotic voices and unentitled Siri identifiers. Prioritizes natural lectionary voices (e.g. Daniel UK, Samantha US, Ava, Moira) and Apple Studio/Enhanced neural voices.
* **Phonetic Pronunciation Dictionary**: Automatically cleanses difficult biblical names and places before speech synthesis (*Thessalonians, Colossians, Ecclesiastes, Gethsemane, Golgotha, Caiaphas, Barabbas*).
* **Liturgical Announcements**: At Mass, lectors proclaim books without reciting chapter and verse numbers aloud. The player uses `BibleBook.liturgicalAnnouncement` covering all 73 canonical Catholic books according to Roman Lectionary liturgical norms (e.g. *"A reading from the Letter of Saint Paul to Philemon"*, *"The Holy Gospel according to Mark"*, *"Responsorial Psalm. Psalm 146."*). Chapters and verses remain visible in the UI text while omitted from spoken audio.
* **Passage-by-passage speech, queued up front**: Each reading is split into its parts (announcement, text, acclamation) and long text into passages of a few sentences (`speechChunks`). Each passage is one utterance. When playback starts, every passage of every remaining reading is handed to the synthesizer's own queue (`enqueue(fromReading:passage:)`), so moving from one reading to the next does not depend on app code running in between. The delegate only tracks the current position and detects the end. A skip, or a change of speed or voice, clears the queue and re-queues from the current passage. A speed change applies wherever it is made (mini player or Settings); made while paused, it applies on resume.
* **Pacing**: the speaking rate is `PlaybackSpeed` (0.44, 0.49, 0.54). The default is 0.44 ("0.8x"), chosen for prayer; a pace picked in Settings is saved and wins. The silences are `SpeechPause`: 0.35 s between passages, 0.9 s between parts and psalm stanzas, 1.6 s after a reading.
* **Interruptions**: a call or another app's audio pauses the reading; when it ends, playback resumes only if the interruption was what paused it (`handleInterruption`). A reading the listener had paused stays paused. Unplugging headphones pauses.
* **Gospel Acclamation**: spoken between "Alleluia, alleluia." except in Lent and the Triduum. The screens pass the day's season to `start(...liturgicalSeason:)`; without it the verse is read alone.
* **One synthesizer for everything**: Prayers and Rosary beads recite through `speakStandalone(_:rate:voice:)`. Views hold the returned identifier and compare it with `standaloneSpeechID` to know whether they are the one speaking. The audio session is released when a prayer or a voice preview ends.
* **Audio session off the main thread**: `activateAudioSession()` and `deactivateAudioSession()` run on a serial queue, so they cannot stall the UI and keep their order (a stop's deactivation reaches the system before the next start's activation).
* **Listen buttons**: Today and a calendar date call `toggle(readings:...)`: it pauses or resumes the readings when they are the ones playing (`isActive(for:)`, compared by type, citation and text since a reloaded day has new IDs), and otherwise starts them.
* **Utterance identity**: Every delegate callback is matched against the utterance it belongs to (reading, preview or standalone). An utterance that was replaced cannot change the play state of its replacement.

### 4.4. Devotional Modules
* **Verse of the Day (`VerseOfTheDayProvider`, `VerseOfDayCard`)**: Dynamically derives the morning keynote focus scripture from the Gospel Acclamation, the Gospel, or the Responsorial Psalm refrain, anchored in the day's Mass.
* **Catholic Treasury of Prayers (`PrayersRepository`, `PrayersView`, `PrayerDetailView`)**: Comprehensive offline treasury across 5 categories (*Daily Rhythm, Foundational, Marian, Saints & Protection, Devotions*) with English and traditional Latin texts, speech synthesis in both languages, and quick search.
* **Interactive Holy Rosary (`HowToPrayRosaryView`, `GuidedRosaryView`, `GuidedRosaryBuilder`, `RosaryDetailView`)**:
  * Dual-mode view: "Mysteries" (today's mystery detection, fruits, scripture) and "How to Pray" (6-step tutorial, bead anatomy, beginner advice).
  * Follows the USCCB's "How to Pray the Rosary": mysteries by weekday, with Sundays by season (`RosaryMysteryType.forDate`: Joyful in Advent, Sorrowful in Lent, otherwise Glorious); each mystery's title, Scripture reference and fruit as USCCB gives them; the Fatima Prayer after each decade only, in the USCCB wording.
  * Interactive bead-by-bead prayer companion with visual 10-bead decade track, haptic taps (`UIImpactFeedbackGenerator`), scripture context, and completion blessing.
* **Saint of the Day (`SaintsDatabase`, `SaintOfDayCard`, `LiturgicalCelebrationBlurbs`)**:
  * `saints.json` is generated by `Scripts/build_saints.py`; every fact in it has a source. Dates: the General Roman Calendar and US proper calendar (`Scripts/saint_calendar.json`) for calendar celebrations; for other saints the celebrated day, confirmed by Wikidata's feast day or the Wikipedia infobox (Catholic dates only), or set by a review decision with quoted evidence (`Scripts/saint_date_review.json`). Each entry records what its date rests on (`date_source`).
  * Descriptions are the introduction of the saint's or feast's English Wikipedia article (pronunciations and foreign-language names stripped); the card credits them with links ("From Wikipedia: ... (CC BY-SA 4.0)"). Life facts (years, birthplace, order, canonization) come from Wikidata; patronages only where the infobox lists them; quotes (`Scripts/saint_quotes.json`) are checked word for word against their source when the data is built.
  * The 2004 Martyrologium Romanum day is shown on the card ("MARTYROLOGY 15 August") when it differs from the celebrated day; it never moves a saint (`Scripts/martyrology_2004.json`, checked against the book by `Scripts/check_martyrology.py`).
  * `saint(for:liturgicalDay:)` returns the feast description for solemnities and feasts of the Lord named by the liturgical day, otherwise one of that date's saints (preferring the one the day's title names, then the first, which is the calendar celebration). It never searches other dates.
* **Daily Prayer Reminders & Vigil Alerts (`NotificationManager`)**: Pre-schedules single daily morning prayer reminders featuring the Saint or Feast of the day and the Verse of the Day, as well as 7:00 PM vigil push notifications the evening before a Holy Day of Obligation.
  * Each reminder carries the Verse of the Day from `ReadingsRepository.verseOfTheDay(for:preferredTranslation:)`, which reads only the Gospel Acclamation and builds the whole Mass only when the verse would come from somewhere else. It gives the same verse as the Today screen (pinned over 120 days in three translations) in about half the time.
  * One entry point, `refreshScheduledNotifications()`, reads the saved settings and makes the pending notifications match: it schedules what is on and removes what is off. It runs at launch, when the app returns from the background with a changed permission, and after any change to the reminder toggles or time, the translation, or "Ascension on Thursday". It never asks for permission; only the Settings toggles do.
  * The two kinds are independent: turning off the daily reminder leaves the vigil alerts alone.
  * Vigil alerts are on by default. The setting is read as on when it has never been saved (`NotificationManager.Preference`), matching what Settings shows.
  * A Settings toggle shows on only when its alerts can arrive: turned on in the app and allowed in iOS Settings.
  * `ReminderRefreshTask` registers a `BGAppRefreshTask` at launch and asks for one whenever the app goes to the background (earliest 12 hours later; iOS picks the time); each run calls `refreshScheduledNotifications()`, so the 30 days of reminders keep moving forward for someone who does not open the app. Info.plist lists the task identifier and the `fetch` mode.
  * `NotificationCenterClient` wraps `UNUserNotificationCenter` so `NotificationSchedulingTests` can drive the manager with a fake center and a fixed date.

---

## 5. Codebase Directory Structure

```
DailyReadings/
├── project.yml                       # XcodeGen project specification
├── README.md                         # Product overview & features
├── TODOS.md                          # Build-by-build changelog & roadmap
├── ARCHITECTURE.md                   # Technical & architectural reference (this file)
└── DailyReadings/
    ├── DailyReadingsApp.swift        # App entry point, SwiftData schema configuration
    ├── Info.plist                    # App metadata & UIBackgroundModes configuration
    ├── PrivacyInfo.xcprivacy         # Apple Privacy Manifest
    │
    ├── Engine/                       # Pure Swift canonical liturgical engine
    │   ├── Computus.swift            # Easter & movable feast astronomical calculations
    │   ├── FixedSolemnities.swift    # Fixed calendar solemnities & USCCB abrogation rules
    │   ├── LiturgicalCalendar.swift  # Main calendar engine (seasons, ranks, cycles, psalter)
    │   ├── LiturgicalColor.swift     # GIRM liturgical color enum & metadata
    │   ├── LiturgicalCycle.swift     # Sunday (A/B/C) and Weekday (I/II) cycle evaluation
    │   ├── LiturgicalRank.swift      # Canonical feast precedence hierarchy
    │   └── LiturgicalSeason.swift    # Seasons (Advent, Christmas, Lent, Triduum, Easter, Ordinary)
    │
    ├── Data/                         # Data access, network, audio, and background services
    │   ├── AudioReadingPlayer.swift  # AVSpeechSynthesizer, background audio, lock screen art
    │   ├── BibleDatabase.swift       # SQLite actor for both Bibles; citation parsing; VersificationMap
    │   ├── EvangelizioService.swift  # REST service fetching online NAB Lectionary
    │   ├── GuidedRosaryBuilder.swift # Step sequencer for interactive bead-by-bead Rosary
    │   ├── LiturgicalCelebrationBlurbs.swift # Historical & theological feast summaries
    │   ├── NotificationManager.swift # Local push notifications: morning reminder + vigil alerts
    │   ├── PericoreIndex.swift       # Lectionary lookup: dated index, then liturgical-cycle keys
    │   ├── PrayersRepository.swift   # Offline Catholic prayers repository (English + Latin)
    │   ├── PsalmResponseProvider.swift # Lectionary Responsorial Psalm antiphon database
    │   ├── ReadingsRepository.swift  # Translation & cache coordinator (WEB-C / DRB offline, NAB online)
    │   ├── SaintsDatabase.swift      # Bundled saints database & commemorations
    │   └── VerseOfTheDayProvider.swift # Derives daily keynote scripture from readings
    │
    ├── Models/                       # Domain models
    │   ├── BibleVerse.swift          # Verse model for SQLite queries
    │   ├── CachedReading.swift       # SwiftData @Model for offline lectionary persistence
    │   ├── DailyReadings.swift       # Collection of readings for a single Mass
    │   ├── GuidedRosaryStep.swift    # Discrete bead/prayer step model
    │   ├── LiturgicalDay.swift       # Full metadata for a calendar day
    │   ├── Prayer.swift              # Traditional Catholic prayer model
    │   ├── Reading.swift             # Single Mass reading (First, Psalm, Gospel, etc.)
    │   ├── RosaryMystery.swift       # Joyful, Sorrowful, Glorious, Luminous mysteries
    │   ├── Saint.swift               # Hagiographical saint model
    │   └── VerseOfTheDay.swift       # Highlighted scripture model
    │
    ├── Theme/                        # Missal design system
    │   ├── AppTheme.swift            # Spacing, corner radii, shadows, semantic colors
    │   ├── LiturgicalColors.swift    # Seasonal color palettes, button backgrounds & contrast
    │   └── Typography.swift          # Font hierarchy; Font.scaled(size:) for Dynamic Type
    │
    ├── ViewModels/                   # UI state coordinators
    │   ├── CalendarViewModel.swift   # Month view pagination & date selection
    │   └── TodayViewModel.swift      # Today's readings, audio sync & pre-fetch triggers
    │
    ├── Views/                        # SwiftUI views
    │   ├── MainTabView.swift         # 4-tab bar (Today, Calendar, Prayers, Settings)
    │   ├── Today/                    # Today tab components
    │   │   ├── TodayView.swift       # Main scrolling devotional feed
    │   │   ├── VerseOfDayCard.swift  # Top hero scripture card
    │   │   ├── ReadingCard.swift     # Single Mass reading card
    │   │   ├── PsalmView.swift       # Responsorial Psalm with antiphon & stanza cues
    │   │   ├── SaintOfDayCard.swift  # Commemorated saint card
    │   │   ├── AudioMiniPlayerBar.swift # Persistent floating audio playback bar
    │   │   └── NoticeBanner.swift    # Message + Retry above the readings (load error, NAB unavailable)
    │   ├── Calendar/                 # Calendar tab
    │   │   ├── CalendarView.swift    # Monthly grid with liturgical dots
    │   │   ├── CalendarDayCell.swift # Individual date cell with selection highlight
    │   │   └── DateReadingsView.swift # Full-screen readings for selected date
    │   ├── Prayers/                  # Prayers tab
    │   │   ├── PrayersView.swift     # Category filter pills, search & Rosary hero
    │   │   ├── PrayerDetailView.swift # Missal reader with Latin/English & speech
    │   │   ├── RosaryDetailView.swift # Mysteries & "How to Pray" dual-mode container
    │   │   ├── HowToPrayRosaryView.swift # 6-step beginner tutorial & bead anatomy
    │   │   └── GuidedRosaryView.swift # Interactive bead-by-bead prayer companion
    │   ├── Reading/                  # Dedicated scripture reader
    │   │   └── ReadingDetailView.swift # Distraction-free full-screen scripture view
    │   └── Settings/                 # Settings tab
    │       └── SettingsView.swift    # Translation, audio voices, cache status, bookmarks
    │
    └── Resources/                    # Bundled offline assets
        ├── bible_webc.sqlite         # Complete World English Bible Catholic Edition (73 books, default)
        ├── bible_drb.sqlite          # Complete Douay-Rheims Bible database (73 books, traditional)
        ├── lectionary.json           # Readings by liturgical cycle (generated; see Scripts/)
        ├── lectionary_dates.json     # Readings by calendar date, 2023-01-01 to 2027-05-31
        ├── versification.json        # Lectionary → Bible verse numbering (generated; see Scripts/)
        └── saints.json               # Saints by date, built by Scripts/build_saints.py from the calendar, Wikipedia and Wikidata
DailyReadingsTests/                   # Automated Unit Test Target (104 passing tests)
├── LiturgicalCalendarTests.swift     # 22 tests: calendar edge cases, Advent bounds, Computus, Ascension, memorials, reminder content, Gospel Acclamation backfill (and when not to), translation labels, NAB cache clean-up, every obligatory memorial present, no crash when given no days to search for a Holy Day
├── ScriptureEngineTests.swift        # 22 tests: citation parsing (including "and"), Hebrew-Vulgate mapping (including Sirach 50), psalm stanza formatting & SQLite queries
├── LectionaryCoverageTests.swift     # 21 tests: the real lectionary through both Bibles, cycle coverage, memorial overrides, audio passages, Rosary schedule (Sunday mysteries by season)
├── AudioPlaybackTests.swift          # 10 tests: real playback across readings, pacing, skip, speed (including from Settings and while paused), liturgical announcements, Alleluia by season, phone-call interruptions, speech callbacks from another thread, Listen on another day starts that day
├── NotificationSchedulingTests.swift # 9 tests: which reminders and vigil alerts are pending after each settings change; a refresh in progress cannot outlive a later one; the reminder verse matches the Today screen; a return on a later day moves the 30 days forward; background refresh is permitted in Info.plist
├── ReadingsReloadTests.swift        # 8 tests: reload after a translation or Ascension change, failed NAB refresh keeps the cache, the NAB-unavailable notice, a load that finishes late cannot replace the latest
├── SaintLifeFactsTests.swift         # 4 tests: life facts and quotes reach the model; the LIVED line
└── SaintCalendarTests.swift          # 8 tests: current calendar dates, old dates gone, the day's saint is that day's (all of 2026), every description sourced, Martyrology day shown without moving the saint, no suppressed cult shown, balanced parentheses in every description
Scripts/                              # Data generators (not part of the app target)
├── build_versification.py            # Builds Resources/versification.json
├── BuildLectionaryIndex/main.swift   # Builds Resources/lectionary.json from the dated data
├── lectionary_seeds.json             # Hand-entered readings the dated data cannot supply
├── build_saints.py                   # Builds Resources/saints.json (calendar, Wikipedia, Wikidata, review decisions, quotes)
├── saint_calendar.json               # General Roman + US proper calendar celebrations and their Wikipedia articles
├── saint_date_review.json            # Reviewed moves, relinks and removals, each with its evidence
├── saint_quotes.json                 # Quotes and the source each is checked against
├── saints_unconfirmed.json           # Report: saints left out or not confirmed (written by the build)
├── martyrology_2004.json             # 2004 Martyrologium Romanum lines and days for the card
├── check_martyrology.py              # Checks martyrology_2004.json against the book (archive.org)
└── check_martyrs.py                  # Report: cross-check against the Vatican's martyr list
NAB_COPYRIGHT.md                      # NAB licensing research and translation options
```

---

## 6. Concurrency & Safety Model

DailyReadings compiles under **Swift 6 complete concurrency checking** (`SWIFT_STRICT_CONCURRENCY = complete`):
* **`@MainActor` Views & ViewModels**: All SwiftUI views and `@Observable` view models (`TodayViewModel`, `CalendarViewModel`, `AudioReadingPlayer`) are actor-isolated to `@MainActor` to prevent UI thread dataraces.
* **`BibleDatabase` Actor**: Isolated as a Swift `actor` to serialize SQLite connection access and avoid C-level thread conflicts on SQLite handles.
* **Audio Artwork Boundary**: `MPMediaItemArtwork(boundsSize:requestHandler:)` invokes its handler on background thread pools. To avoid actor isolation violations and runtime crashes (`_dispatch_assert_queue_fail`), artwork rendering logic is extracted into a `nonisolated` static helper.
* **`ReadingsRepository`**: `@MainActor`. Lectionary lookups run in a detached task, because the first lookup parses the bundled lectionary files.
* **`NotificationManager`**: `@MainActor`. Refreshes run one at a time: a new refresh cancels the one in progress and waits for it to finish before reading what is pending. The scheduling loops check for cancellation right before each `add`, so a pass that was preparing a day's readings when the reminder was turned off adds nothing more. The schedule covers 30 days; it is refreshed at launch, after any settings change, and when the app comes to the foreground on a later day than the last refresh (`refreshIfStale`), so it moves forward even when the app stays in memory. With no background refresh, a user who does not open the app for 30 days stops getting reminders.
* **Speech delegate**: Apple does not say which thread `AVSpeechSynthesizer` calls its delegate on. The delegate methods are `nonisolated`: on the main thread an event is handled at once; from any other thread it is handed to the main thread in order (`deliver(_:_:)`, then `handleSpeechEvent`). Either way no callback can trip Swift's main-actor check. Pinned by a test that sends a callback from a background thread.
* **`TodayViewModel` loads**: loads are not cancelled when another starts (pull to refresh, a return on a new day, a settings change), so each load is numbered and only the latest may show its result or clear `isLoading`.
* **Value Types & `Sendable`**: All data exchange structs (`Reading`, `LiturgicalDay`, `GuidedRosaryStep`, `Prayer`) strictly conform to `Sendable`.

---

## 7. Status & Audit History (Claude AI Review & Resolution)

In November 2026, Claude AI completed a comprehensive audit of the liturgical engine, offline Douay-Rheims path, audio playback, and Swift 6 concurrency. All critical findings were remediated and pinned with automated tests across Builds 13 and 14:

| Finding Category | Issue Discovered | Status & Resolution (Builds 13–14) |
| :--- | :--- | :--- |
| **Calendar: Advent Bound** | Advent starting in November was not recognized (`month == 12` check). | **Resolved**: Bounded by `adventStart` and `christmasDay`. Verified by test. |
| **Calendar: Epiphany Duplicate** | Epiphany Universal (Jan 6) showed duplicate after US Sunday celebration. | **Resolved**: Universal entry filtered out when celebration transfers to Sunday. |
| **Calendar: Lenten Abstinence** | Lenten Friday solemnities (e.g. St. Joseph) were marked for abstinence. | **Resolved**: Canon 1251 exemption properly waives meat abstinence. |
| **Calendar: Sacred Heart Collision** | Sacred Heart / Nativity of John the Baptist collision (June 24, 2033). | **Resolved**: UNLY §59 / Prot. N. 168/22 precedence implemented. |
| **Scripture: Psalm Numbering** | Lectionary cited Hebrew numbering, but DRB used Latin Vulgate. | **Resolved**: Canonical Hebrew ↔ Vulgate mapping implemented in `BibleDatabase`. |
| **Scripture: Multi-Chapter Citations** | Cross-chapter spans and multi-chapter semicolons were truncated. | **Resolved**: Multi-chapter span parser added with sequential chapter queries. |
| **Scripture: Missing Readings** | 12 dates in `lectionary_dates.json` lacked proper first readings. | **Resolved**: Patched all 12 dates with correct canonical lectionary citations. |
| **Scripture: Default Translation** | NAB licensing required offline public-domain default. | **Resolved**: Bundled full 73-book WEB-C as default modern translation. |
| **Audio: Utterance / Audition Race** | Voice preview completion advanced reading queue. | **Resolved**: Distinct tracking for `currentReadingUtterance` vs audition. |
| **Audio: Interruption Recovery** | Resume never reactivated `AVAudioSession`; no headphone disconnect handling. | **Resolved**: Added session reactivation and `routeChangeNotification` pauses. |
| **Audio: Synthesizer Consolidation** | 3 separate synthesizers existed across Views. | **Resolved**: Unified through `AudioReadingPlayer.shared`. |
| **App Lifecycle: Midnight Rollover** | Today view went stale overnight. | **Resolved**: Observed `scenePhase == .active` and `significantTimeChangeNotification`. |
| **Concurrency: Swift 6 Isolation** | Isolation warnings in interruption observers and cache fetching. | **Resolved**: Conformed to `@preconcurrency AVSpeechSynthesizerDelegate` on `@MainActor`. |

---

### Second audit round (12 November 2026, Build 16)

A second audit ran every lectionary citation through both bundled Bibles and found the remaining problems were in verse numbering and lectionary data, not the calendar.

| Finding | Status |
| :--- | :--- |
| WEB-C psalms shifted by one or two verses where the psalm has a title | **Resolved**: `versification.json` mapping; titles stripped. |
| WEB-C had no Joel, Malachi, Zechariah, Isaiah or Romans mapping | **Resolved**: same table, applied to both Bibles. |
| Long-or-short citations read the wrong chapter (regression) | **Resolved**: the long form is read. |
| Out-of-range start verse returned the whole chapter | **Resolved**. |
| "Esther C", "II Corinthians", "Psalm103:" failed to parse | **Resolved**. |
| 210 of 415 days through 2027 showed invented fallback readings | **Resolved**: cycle index; fallback removed. 1,845 of 1,876 days through 2031 are complete. |
| Prayer and Rosary audio never reset or released the session | **Resolved**: shared player. |
| Speed or voice change restarted the reading | **Resolved**: passage-level utterances. |
| Fixed font sizes ignored Dynamic Type | **Resolved in code** (`Font.scaled`, capped at 1.5x); not yet checked visually. |
| "31 of 30 days stored"; lectionary parsed on the main thread at launch; missing copyright footer on the date view | **Resolved**. |
| Rosary guide showed the wrong mysteries on Wednesday and Thursday (swapped) | **Resolved**: `RosaryMysteryType.forDate`; pinned by test. The written directions were reviewed and are accurate. |
| NAB tier shows "used by permission" without a license | **Open by decision**: kept as-is while the app has a single tester. See section 8. |
| Douay-Rheims Sirach verse numbers differ from the Lectionary's | **Resolved**: Mapped via `mapHebrewSirachToVulgate` (+2 offset to Vulgate Ecclesiasticus 50:24-26). |
| 31 days through 2031 have incomplete or no readings | **Resolved**: Seeded in `lectionary_seeds.json` and rebuilt `lectionary.json`. 1,876 of 1,876 days through 2031 now complete (100% coverage). |
| Lent Sundays 3 to 5 Year B & C readings | **Resolved**: Seeded proper Year B & C readings for Lent 3, 4, 5 in `lectionary_seeds.json`. |
| Ascension Thursday provinces not supported | **Resolved**: Added user toggle in `SettingsView`, dynamic `ascensionOnThursday` evaluation in `LiturgicalCalendar`, and seeded Seventh Sunday of Easter readings (`easter_sun_7_A/B/C`). |
| Memorials list partial in `FixedSolemnities` | **Resolved**: Added missing Roman and US calendar obligatory memorials and key optional memorials; precedence rule prevents optional memorials from displacing Ordinary Time weekday readings. |
| Empty state missing USCCB link | **Resolved**: Direct styled web links added to `DateReadingsView` and `TodayView`. |
| Responsorial psalm sentences ran together without stanza breaks | **Resolved**: Formatted with `\n\n` per citation segment in `BibleDatabase.formattedPsalmText`, enabling antiphon responses after each stanza in visual UI and audio recitation. |
| Spoken audio recited book chapter and verse numbers | **Resolved**: Added `BibleBook.liturgicalAnnouncement` covering all 73 Catholic canonical books; chapter and verse numbers omitted from audio recitation while preserved in visual UI. |
| Duplicate morning notification firing simultaneously | **Resolved**: Consolidated into a single unified morning notification pre-scheduled for 30 days, pairing the feast/saint title in the subtitle with the Verse of the Day in the body. |
| Evangelizo API omitted Gospel Acclamation | **Resolved**: Backfilled from official Lectionary index in `ReadingsRepository`; Verse of the Day aligns with Gospel Acclamation across NAB and notifications. |

---

### Third audit round (14 November 2026, resolved in Build 20)

| # | Finding | Status |
| :--- | :--- | :--- |
| 1 | From mid-2027, some weekdays read another day's Gospel or psalm (Oct 31, 2028: Luke 14 instead of Luke 13; Jan 18: Psalm 110; Aug 26, 2028: Psalm 128). `PericoreIndex` added a `proper_MM_DD` key on every weekday, and the index builder derived 14 such keys from dates that happened to repeat in the dated years. The builder was also nondeterministic, so the committed `lectionary.json` could not be reproduced. | **Resolved**: `proper_` only on obligatory memorials; a psalm only with its own First Reading; deterministic build; seeds win where they cite the same reading. 14 false keys removed, 6 real ones kept. Holdout: 469 of 512 right (was 466), 13 wrong (was 15). Pinned in `LectionaryCoverageTests`. |
| 2 | The NAB Gospel Acclamation backfill adds any missing reading type, so a feed carrying a different Mass from the app's calendar gets readings from both; backfilled WEB-C text is labelled NAB. | **Resolved**: `backfillGospelAcclamation` adds only the acclamation, only when the feed's Gospel is the Lectionary's Gospel for the day, labelled WEB-C. NAB days cached by Build 19 are cleared once at launch and download again. Pinned in `LiturgicalCalendarTests`. |
| 3 | Holy Day vigil alerts never fired for a new user: Settings showed them on, but the scheduler read the unsaved setting as off. Turning off the daily reminder also removed the vigil alerts, and vigil alerts were only refreshed with the daily reminder. | **Resolved**: `refreshScheduledNotifications()`; pinned in `NotificationSchedulingTests`. |
| 4 | Turning the reminder off (or changing translation) while a 30-day schedule was being built let the earlier pass keep adding reminders. | **Resolved**: refreshes are serialized and cancellable; pinned in `NotificationSchedulingTests`. |
| 5 | Changing the translation or "Ascension on Thursday" does not reload the Today screen. | **Resolved**: each screen remembers the settings it loaded with and reloads when it reappears with different ones (`TodayViewModel.reloadIfSettingsChanged`, also used by the calendar's date view); the calendar grid recomputes its days when the Ascension setting changed (`CalendarViewModel.reloadIfCalendarSettingChanged`). Pinned in `ReadingsReloadTests`. |
| 6 | The reading detail badge shows the setting, not `reading.translation` (wrong after the NAB fallback and for old bookmarks). | **Resolved**: the badge shows `Reading.translationDisplayName`. |
| 7 | The NAB-to-WEB-C fallback is silent; pull-to-refresh never re-downloads NAB. | **Resolved**: pull-to-refresh and Retry download NAB again; a download that fails keeps the cached NAB before falling back to WEB-C; when NAB was chosen but WEB-C is shown, Today and the date view say so with a Retry button. Pinned in `ReadingsReloadTests`. |
| 8 | Psalm stanzas split at every comma (Pentecost's Psalm 104 becomes 5 stanzas, not 3). | **Resolved where the data allows**: `PericoreIndex` uses the "and" spelling of a psalm wherever the dated data has one (20 psalms, 36 dated days); the Pentecost seed now reads `104:1ab and 24ac, 29bc-30, 31 and 34`. A citation the data never spells with "and" is still split at every comma. |
| 9 | Saint Francis de Sales (Jan 24) missing from `FixedSolemnities`. | **Resolved**; a test now checks every obligatory memorial and feast of the General Roman and US calendars. |
| 10 | Each refresh builds 30 complete Masses for one verse per day. | **Resolved**: `verseOfTheDay` reads only the Gospel Acclamation when that gives the verse; about twice as fast, same verse. |
| — | Found while fixing #8: citations with "and" lost every verse after it ("Psalm 67:… 6 and 8" read verse 6 only). 409 of 1,874 days through 2031 had such a citation, 404 of them in the psalm. The coverage tests only checked that some verses came back. | **Resolved**: `parseVerseNumbers` reads "and" as a comma; pinned in `ScriptureEngineTests`. |
| — | Smaller: two launch tasks both loaded Today; a pace set in Settings, or while paused, was not applied; the spoken Gospel Acclamation had no Alleluia; text size defaulted to 20 in the reading view and 18 elsewhere; an unused-variable warning; date formatters created per call in `LiturgicalDay.id`, `CachedReading.makeDateKey`, the calendar cells and the USCCB link; the Advent December 17–24 titles depended on the device language. | **Resolved**. |
| — | Lent Sundays 3 to 5 in 2027 seemed to show only the Year A readings. | **Checked, no change**: the 2027 dated data lists both the Year A and Year B readings, as USCCB does. |

---

### Fourth audit round (18 November 2026, resolved in Build 21)

Claude and Codex audited Build 20; a third audit (Google Antigravity) was also reviewed.

| # | Finding | Status |
| :--- | :--- | :--- |
| 1 | A reading the listener had paused started playing again when a phone call ended (`resume()` ran whenever iOS allowed it; the `isInterrupted` flag was never read). | **Resolved**: `handleInterruption` resumes only what the interruption paused. Pinned in `AudioPlaybackTests`. |
| 2 | Speech delegate callbacks off the main thread would crash under Swift 6's main-actor check; this was an open device check. | **Resolved**: `nonisolated` delegate methods hand events to the main thread. Pinned by a background-thread test. |
| 3 | The 30 days of reminders and vigil alerts were only extended at a cold launch or a settings change, so an app kept in memory ran out. | **Resolved**: `refreshIfStale` on every return to the foreground on a new day. No background refresh task (a user who never opens the app for 30 days still runs out). Pinned in `NotificationSchedulingTests`. |
| 4 | A slow NAB refresh that finished after a later load put the previous day's readings under today's date; Retry could be tapped repeatedly. | **Resolved**: numbered loads in `TodayViewModel`; Retry shows a spinner while it runs. Pinned in `ReadingsReloadTests`. |
| 5 | `EvangelizioService` supplies "used by permission of the copyright owner" when the feed has no notice. | **Open by decision**, with the NAB tier (section 8, item 1). The text is not shown today because the cached day drops the copyright field. |
| 6 | `nextHolyDayOfObligation(daysAhead: 0)` crashed (`1...0`). No caller passed 0. | **Resolved**: returns nil. Pinned in `LiturgicalCalendarTests`. |
| — | Not done: the Lenten acclamation ("Praise to you, Lord Jesus Christ…") is not spoken around the verse in Lent; the play button on a calendar date controls the readings already playing from Today. | Open, low. |

---

## 8. Open Items

Listed in the order they matter. `TODOS.md` carries the same list as checkboxes.

**Before any release**
1. **NAB licensing.** The NAB tier fetches, caches and reads aloud text the app has no license for, and `EvangelizioService` attaches a notice saying it is "used by permission". Digital NABRE permissions are currently closed (`NAB_COPYRIGHT.md`). The tier is kept for personal testing only. Remove or gate it, and correct the notice, before TestFlight or the App Store.
2. **Check the hand-entered readings** in `Scripts/lectionary_seeds.json` against USCCB: Holy Thursday (Lord's Supper), Ascension (and its Gospel for Years A, B, C), Pentecost (Mass during the Day), Nativity of John the Baptist, Saints Peter and Paul, Thursday of the Sixth Week of Easter. They were typed from memory. The older `fixed_*` seeds (Jan 1, Mar 19, Mar 25, Aug 15, Nov 1, Nov 2, Dec 25) were also never verified.
3. **Check the bundled psalm refrains** (`PsalmResponseProvider`, seed responses). They quote the Lectionary, which is copyrighted separately from the Bible text.

**Needs a device**
4. **Listen to a full set of readings.** A device test of Build 16 found playback stopping after the First Reading and the pace too quick. The player now queues the whole Mass at once and uses longer pauses, but the stop was never reproduced in the simulator, so this is unconfirmed. Check with the screen on and locked.
5. **View every screen at the largest text sizes.** Fonts now scale up to 1.5x; fixed-size layouts (calendar grid, category pills, mini player) have not been looked at. Changing the text size also rebuilds the tab content, which resets navigation.

**Resolved in Post-Build-16 Work**
- **31 days through 2031 data gaps:** Resolved (100% complete coverage across all 1,876 days through 2031).
- **Lent Sundays 3 to 5 (Years B & C):** Seeded and verified.
- **Douay-Rheims Sirach 50:22-24:** Resolved via `mapHebrewSirachToVulgate`.
- **Esther additions:** Verified; Greek Addition C is the sole lectionary reading.
- **Empty state USCCB links:** Implemented in `DateReadingsView` and `TodayView`.
- **December 9 obligation:** Verified and confirmed with Vatican Dicastery ruling.
- **Ascension Thursday provinces:** Fully supported with `SettingsView` toggle and Seventh Sunday of Easter seed data.
- **Roman Calendar memorials:** Completed obligatory memorials and key optional memorials in `FixedSolemnities`.
- **Responsorial Psalm formatting & antiphon placement:** Stanza separation with `\n\n` for proper antiphon placement in visual UI and audio recitation.
- **Liturgical spoken announcements:** Omitted chapter and verse numbers from audio recitation using canonical Roman Lectionary book announcements.
- **Unified morning notification with Verse of the Day:** Single consolidated daily reminder with Saint/Feast subtitle and scripture quote body.
- **Gospel Acclamation backfill for NAB:** Remote service omission backfilled from canonical Lectionary index, displaying the Acclamation card and aligning the Verse of the Day across all translations.
- **App Store listing & privacy policy:** Documented in `APP_STORE_LISTING.md` and `PRIVACY.md`.

**Psalm stanzas** (section 4.2, item 4)
- A psalm citation the data only spells with commas is still split at every comma. Correct stanza breaks for those need the Lectionary's own text.

**Rosary guide (optional)**
- The guide says the Fatima Prayer after the opening Glory Be; the usual practice says it only after each decade.
- Sundays always give the Glorious Mysteries. A setting could offer the seasonal custom (Joyful in Advent and Christmas, Sorrowful in Lent).
- The Fourth and Fifth Glorious Mysteries entries were not reviewed.

**Smaller**
6. Speed and voice changes restart the current passage, not the exact word.
7. For freshly downloaded NAB days the copyright line under the readings is empty (the feed's notice is not carried into the cached day). Left as is while the NAB tier stays unchanged by decision; see item 1.

---

## 9. Recommended Focus Areas for Ongoing Claude AI Analysis

When reviewing DailyReadings at this stage, Claude AI should focus on:

1. **User Experience & Contemplative Flow**:
   * Evaluated reading cadence, typography scaling, whitespace balance, and line height across light and dark modes.
   * Feedback on the interactive bead-by-bead Holy Rosary guide and "How to Pray" tutorial.
2. **Dynamic Type & Accessibility**:
   * Verify all scripture cards and button touch targets properly accommodate Accessibility Large text sizes.
   * Audit VoiceOver accessibility labels on custom components (e.g., decade tracker dots, antiphon badges).
3. **Audio Utterance Pacing**:
   * Fine-tuning speech synthesizer boundary pauses between readings, liturgical announcements, and psalm antiphons for maximum reverence.
4. **Codebase Cleanliness & Invariant Verification**:
   * Verify all 104 unit tests in `DailyReadingsTests` remain green under Swift 6 strict concurrency.
   * After any change to `lectionary_dates.json` or the seeds, rebuild `lectionary.json` and re-run `LectionaryCoverageTests`.
