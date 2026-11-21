#!/usr/bin/env python3
"""Rebuilds DailyReadings/Resources/saints.json so that every fact in it has a source.

  Dates        The app shows the day a saint is celebrated. Where the 2004 Martyrologium Romanum
               lists the saint on another day (often the day of death), that day is added as
               "martyrology" for the card (Scripts/martyrology_2004.json, checked against the
               book's index by Scripts/check_martyrology.py); it never moves the saint.
               Each celebration of the General Roman Calendar and the US proper calendar
               (Scripts/saint_calendar.json) is placed on its date, first in that day's list.
               Any other saint keeps its date unless Scripts/saint_date_review.json moves, relinks or
               removes it; the date counts as confirmed when Wikidata's feast day (P841) or the
               article's infobox gives it. Nothing moves automatically (both often list Eastern
               dates); the rest are listed in Scripts/saints_unconfirmed.json.
  Descriptions The introduction of the saint's (or feast's) English Wikipedia article, trimmed at
               a sentence; each entry keeps the article links for the app's "From Wikipedia" credit
               (CC BY-SA 4.0).
  Tagline      The calendar's own wording ("Priest and Doctor of the Church") and rank, or the
               Wikidata description for saints outside the calendar.
  Patronages   Kept only when the saint's Wikipedia infobox lists them.
  Life facts   Wikidata (CC0): born, died, birthplace, religious order, canonization year.
  Quotes       Scripts/saint_quotes.json; each is fetched from its source and must appear there word
               for word, or it is left out.
  Feasts       Descriptions for the solemnities and feasts the app names from the liturgical day
               (LiturgicalCelebrationBlurbs), under the "celebrations" key.

Run from the repo root:  python3 -I Scripts/build_saints.py [--cache DIR]
It reads the current saints.json for the saints outside the calendar, so it can be rerun.
"""
import hashlib, html, json, os, re, sqlite3, sys, time, urllib.parse, urllib.request

PATH = "DailyReadings/Resources/saints.json"
CALENDAR = "Scripts/saint_calendar.json"
QUOTES = "Scripts/saint_quotes.json"
UNCONFIRMED = "Scripts/saints_unconfirmed.json"
REVIEW = "Scripts/saint_date_review.json"
MARTYROLOGY = "Scripts/martyrology_2004.json"
BIBLE = "DailyReadings/Resources/bible_webc.sqlite"
UA = {"User-Agent": "DailyReadings-data-script/1.0 (offline saints data build)"}
WD = "https://www.wikidata.org/w/api.php"
WP = "https://en.wikipedia.org/w/api.php"
WQ = "https://en.wikiquote.org/w/api.php"

# The app's feast descriptions (LiturgicalCelebrationBlurbs ids) and their Wikipedia articles.
CELEBRATIONS = {
    "lateran_basilica": "Dedication of the Lateran Basilica", "all_saints": "All Saints' Day",
    "all_souls": "All Souls' Day", "christmas": "Christmas",
    "mary_mother_of_god": "Solemnity of Mary, the Holy Mother of God", "epiphany": "Epiphany (holiday)",
    "baptism_of_the_lord": "Feast of the Baptism of the Lord", "presentation_of_the_lord": "Presentation of Jesus at the Temple",
    "ash_wednesday": "Ash Wednesday", "annunciation": "Annunciation", "palm_sunday": "Palm Sunday",
    "holy_thursday": "Maundy Thursday", "good_friday": "Good Friday", "holy_saturday": "Holy Saturday",
    "easter_sunday": "Easter", "divine_mercy": "Divine Mercy Sunday", "ascension": "Feast of the Ascension",
    "pentecost": "Pentecost", "holy_trinity": "Trinity Sunday", "corpus_christi": "Feast of Corpus Christi",
    "sacred_heart": "Feast of the Sacred Heart", "transfiguration": "Feast of the Transfiguration",
    "assumption": "Assumption of Mary", "exaltation_of_the_cross": "Feast of the Cross",
    "christ_the_king": "Feast of Christ the King", "immaculate_conception": "Immaculate Conception",
}

cache_dir = None
if "--cache" in sys.argv:
    cache_dir = sys.argv[sys.argv.index("--cache") + 1]
    os.makedirs(cache_dir, exist_ok=True)


def fetch(url, as_json=True):
    key = None
    if cache_dir:
        key = os.path.join(cache_dir, hashlib.sha1(url.encode()).hexdigest() + (".json" if as_json else ".html"))
        if os.path.exists(key):
            return json.load(open(key)) if as_json else open(key, encoding="utf-8", errors="replace").read()
    for attempt in range(8):
        try:
            raw = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read()
            break
        except Exception as error:
            print(f"  retry {attempt + 1} after {error}: {url[:90]}", file=sys.stderr, flush=True)
            time.sleep(60 * (attempt + 1))  # Wikimedia rate limits: back off well
    else:
        raise RuntimeError("request failed: " + url)
    time.sleep(4.0)
    text = raw.decode("utf-8", errors="replace") if b"charset=iso-8859-1" not in raw[:600].lower() else raw.decode("latin-1")
    if key:
        open(key, "w", encoding="utf-8").write(text)
    return json.loads(text) if as_json else text


def api(base, params):
    return fetch(base + "?" + urllib.parse.urlencode({**params, "format": "json", "formatversion": 2}))


# ---------------------------------------------------------------- Wikipedia

def resolve(titles):
    """Wikipedia title -> {title, url, qid, extract} following redirects."""
    out = {}
    titles = sorted(set(titles))
    for i in range(0, len(titles), 20):
        batch = titles[i:i + 20]
        r = api(WP, {"action": "query", "titles": "|".join(batch), "redirects": 1, "prop": "extracts|pageprops",
                     "exintro": 1, "explaintext": 1, "exlimit": 20, "ppprop": "wikibase_item|disambiguation"})
        q = r.get("query", {})
        hop = {}
        for n in q.get("normalized", []) + q.get("redirects", []):
            hop[n["from"]] = n["to"]
        pages = {p["title"]: p for p in q.get("pages", []) if "missing" not in p}
        for t in batch:
            target = t
            for _ in range(4):
                target = hop.get(target, target)
            p = pages.get(target)
            if p and "disambiguation" not in p.get("pageprops", {}):
                out[t] = {"title": p["title"], "qid": p.get("pageprops", {}).get("wikibase_item"),
                          "extract": p.get("extract", ""),
                          "url": "https://en.wikipedia.org/wiki/" + urllib.parse.quote(p["title"].replace(" ", "_"))}
    return out


def infobox_field(text, name):
    """An infobox field's text, including multi-line templates like {{UBL | ... }}."""
    m = re.search(r"\|\s*" + name + r"\s*=", text, re.I)
    if not m:
        return ""
    depth, i = 0, m.end()
    while i < len(text):
        if text.startswith("{{", i):
            depth += 1; i += 2; continue
        if text.startswith("}}", i):
            if depth == 0:
                break
            depth -= 1; i += 2; continue
        if text[i] == "\n" and depth == 0 and re.match(r"\n\s*\|", text[i:]):
            break
        i += 1
    value = re.sub(r"<ref[^>]*/>|<ref[^>]*>.*?</ref>|<!--.*?-->", "", text[m.end():i], flags=re.S)
    return re.sub(r"\s+", " ", re.sub(r"\[\[(?:[^|\]]*\|)?([^\]]*)\]\]", r"\1", value)).strip()


def infoboxes(titles):
    """Article -> {"patronage": lowercased text, "feast": text} from its infobox."""
    out = {}
    titles = sorted(set(titles))
    for i in range(0, len(titles), 50):
        r = api(WP, {"action": "query", "titles": "|".join(titles[i:i + 50]), "prop": "revisions",
                     "rvprop": "content", "rvslots": "main"})
        for p in r.get("query", {}).get("pages", []):
            text = (p.get("revisions") or [{}])[0].get("slots", {}).get("main", {}).get("content", "")
            out[p["title"]] = {"patronage": infobox_field(text, "patronage").lower(),
                               "feast": infobox_field(text, r"feast[_ ]day")}
    return out


OTHER_CHURCHES = re.compile(r"orthodox|anglican|lutheran|coptic|eastern|church of england|episcopal|syriac|armenian|"
                            r"ethiopian|byzantine|church of the east|maronite|greek|oriental", re.I)


def catholic_dates(text):
    """Dates in an infobox feast field, leaving out those it labels for other churches
    ("18 January: Confession of Saint Peter (Anglicanism, Lutheranism)")."""
    parts = re.split(r";|<br\s*/?>|\||\*|\n|\),", text)
    keep = [p for p in parts if not OTHER_CHURCHES.search(p) or re.search(r"catholic|roman", p, re.I)]
    return set().union(*[dates_in(p) for p in keep] or [set()])


def dates_in(text):
    """MM-DD keys for every "2 January" or "January 2" in a text."""
    found = set()
    names = "|".join(MONTHS_FULL)
    for m in re.finditer(r"(\d{1,2})\s+(" + names + r")\b|\b(" + names + r")\s+(\d{1,2})\b", text):
        day, month = (m.group(1), m.group(2)) if m.group(1) else (m.group(4), m.group(3))
        found.add(f"{MONTHS_FULL.index(month) + 1:02d}-{int(day):02d}")
    return found


MONTHS_FULL = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
               "October", "November", "December"]
ABBREV = {"st", "sts", "ss", "c", "ca", "mt", "dr", "mr", "mrs", "fr", "no", "vol", "jr", "sr", "e.g", "i.e", "ad", "bc"}


def sentences(text):
    out, start = [], 0
    for m in re.finditer(r"[.!?][\"”’)]?\s+(?=[A-Z“\"])", text):
        word = re.findall(r"([\w.]+)[.!?][\"”’)]?\s+$", text[start:m.end()])
        if word and (word[0].lower() in ABBREV or len(word[0]) == 1):
            continue
        out.append(text[start:m.end()].strip())
        start = m.end()
    if text[start:].strip():
        out.append(text[start:].strip())
    return out


NOISE = re.compile(r"[ˈˌːəɛɔɪʊæʃʒθðŋ]|IPA|pronunciation|pronounced|\b[A-Z][a-z]+(?: [A-Za-z]+)?:|\b[A-Z]{2}:|\bborn\b|\bdied\b|"
                   r"\d{3,4}\s*[–-]|[–-]\s*\d{1,2}? ?[A-Z]?[a-z]* ?\d{3,4}|\bc\. \d|;")


def drop_lead_parenthetical(paragraph):
    """Remove parentheses holding pronunciations, names in other languages, or life dates
    (the app shows the years separately), including nested ones."""
    paragraph = re.sub(r",?\s*pronounced \[[^\]]*\]", "", paragraph)
    i = 0
    while True:
        i = paragraph.find("(", i)
        if i < 0:
            break
        depth, j = 0, i
        while j < len(paragraph):
            depth += {"(": 1, ")": -1}.get(paragraph[j], 0)
            if depth == 0:
                break
            j += 1
        inner = paragraph[i + 1:j]
        if j < len(paragraph) and (NOISE.search(inner) or not inner.strip()):
            start = i
            while start > 0 and paragraph[start - 1] == " ":
                start -= 1
            paragraph = paragraph[:start] + paragraph[j + 1:]
            i = start
        else:
            i += 1
    paragraph = re.sub(r",\s*Latin: [^)]*\)", "", paragraph)  # a parenthesis Wikipedia left unopened
    paragraph = repair_parentheses(paragraph)
    return re.sub(r",\s*,", ",", re.sub(r"\s+([,.;])", r"\1", paragraph))


VERB = re.compile(r"\s(?:was|is|are|were)\b")


def repair_parentheses(paragraph):
    """Mend a lead whose parentheses Wikipedia (or the removals above) left unbalanced.

    An unclosed "(" is closed before the sentence's verb, or dropped with its text when that
    text is a name in another language or a date ("Felix of Valois, OSsT (French: Félix de
    Valois; was" -> "Felix of Valois, OSsT was"). A ")" with no "(" is dropped alone, or with
    the clause it ends when that clause is dates or names ("Vincenzo Strambi, religious name
    ...; 1 January 1745 — 1 January 1824) was" -> "Vincenzo Strambi was")."""
    for _ in range(6):
        depth, stray, opened = 0, None, []
        for k, ch in enumerate(paragraph):
            if ch == "(":
                opened.append(k)
            elif ch == ")":
                if opened:
                    opened.pop()
                elif stray is None:
                    stray = k
        if stray is not None:
            start = max(paragraph.rfind(",", 0, stray), paragraph.rfind(";", 0, stray))
            first = min([x for x in (paragraph.find(","), paragraph.find(";")) if x >= 0] or [stray])
            clause = paragraph[first:stray]
            if NOISE.search(clause) and stray - first < 260:
                paragraph = paragraph[:first] + paragraph[stray + 1:]
            else:
                paragraph = paragraph[:stray] + paragraph[stray + 1:]
            continue
        if opened:
            i = opened[0]
            verb = VERB.search(paragraph, i)
            if not verb:
                paragraph = paragraph[:i] + paragraph[i + 1:]
            elif NOISE.search(paragraph[i + 1:verb.start()]):
                paragraph = paragraph[:i].rstrip() + paragraph[verb.start():]
            else:
                paragraph = paragraph[:verb.start()].rstrip(" ;,") + ")" + paragraph[verb.start():]
            continue
        break
    # A separator left in front of the verb by a removal: "or Æthelred; was" -> "or Æthelred, was".
    return re.sub(r";\s+(?=(?:was|is|are|were)\b)", ", ", paragraph)


def join_broken_lines(extract):
    """Wikipedia sometimes breaks a line inside a parenthesis ("1499 – October\n18, 1562)");
    keep such a line with the next one instead of starting a new paragraph."""
    lines, out = extract.split("\n"), []
    for line in lines:
        if out and out[-1].count("(") > out[-1].count(")"):
            out[-1] += " " + line
        else:
            out.append(line)
    return "\n".join(out)


def description(extract, target=650, limit=1100):
    extract = join_broken_lines(extract)
    paras = [re.sub(r"\s+", " ", p).strip() for p in extract.split("\n") if p.strip()]
    paras = [p for p in paras if "." in p or len(p) > 60]  # section headings in a full-article extract
    if not paras:
        return ""
    paras = [drop_lead_parenthetical(p) for p in paras]
    out = []
    for p in paras:
        if sum(len(x) for x in out) >= target:
            break
        out.append(p)
    text = "\n\n".join(out)
    if len(text) > limit:
        kept = ""
        for para in out:
            for s in sentences(para):
                if len(kept) + len(s) + 1 > limit:
                    return kept.strip()
                kept += s + " "
            kept = kept.rstrip() + "\n\n"
        text = kept.strip()
    return text


def short_description(extract):
    paras = [p for p in join_broken_lines(extract).split("\n") if p.strip()]
    if not paras:
        return ""
    s = sentences(drop_lead_parenthetical(re.sub(r"\s+", " ", paras[0]).strip()))
    text = ""
    for x in s[:2]:
        if text and len(text) + len(x) > 450:
            break
        text += x + " "
    return text.strip()


# ---------------------------------------------------------------- Wikidata

def entities(qids):
    out = {}
    qids = sorted(q for q in set(qids) if q)
    for i in range(0, len(qids), 50):
        r = api(WD, {"action": "wbgetentities", "ids": "|".join(qids[i:i + 50]), "props": "claims|descriptions",
                     "languages": "en"})
        out.update(r.get("entities", {}))
    return out


def labels(qids):
    out = {}
    qids = sorted(q for q in set(qids) if q)
    for i in range(0, len(qids), 50):
        r = api(WD, {"action": "wbgetentities", "ids": "|".join(qids[i:i + 50]), "props": "labels", "languages": "en"})
        for q, e in r.get("entities", {}).items():
            lab = e.get("labels", {}).get("en", {}).get("value")
            if lab:
                out[q] = lab
    return out


def values(claims, prop):
    return [c["mainsnak"]["datavalue"]["value"] for c in claims.get(prop, [])
            if c.get("mainsnak", {}).get("snaktype") == "value"]


def item_ids(claims, prop):
    return [v["id"] for v in values(claims, prop) if isinstance(v, dict) and "id" in v]


def year(claims, prop):
    for c in claims.get(prop, []):
        snak = c.get("mainsnak", {})
        if snak.get("snaktype") != "value":
            continue
        v = snak["datavalue"]["value"]
        if v.get("precision", 0) < 9:
            continue
        y = int(v["time"][:v["time"].index("-", 1)])
        circa = any(q.get("datavalue", {}).get("value", {}).get("id") == "Q5727902"
                    for q in c.get("qualifiers", {}).get("P1480", []))
        return ("c. " if circa else "") + (f"{-y} BC" if y <= 0 else str(y))
    return None


def canonized_year(claims):
    for c in claims.get("P411", []):
        if c.get("mainsnak", {}).get("datavalue", {}).get("value", {}).get("id") != "Q43115":
            continue
        for q in c.get("qualifiers", {}).get("P585", []):
            v = q.get("datavalue", {}).get("value")
            if v and v.get("precision", 0) >= 9:
                return str(int(v["time"][1:v["time"].index("-", 1)]))
    return None


MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
          "November", "December"]


def day_key(label):
    m = re.fullmatch(r"(\w+) (\d{1,2})", label or "")
    if m and m.group(1) in MONTHS:
        return f"{MONTHS.index(m.group(1)) + 1:02d}-{int(m.group(2)):02d}"
    return None


# ---------------------------------------------------------------- quotes

def normalize(text):
    text = html.unescape(re.sub(r"<[^>]+>", " ", text))
    text = re.sub(r"\[\[(?:[^|\]]*\|)?([^\]]*)\]\]", r"\1", text).replace("'''", "").replace("''", "")
    text = text.replace("’", "'").replace("‘", "'").lower()
    return re.sub(r"\s+", " ", re.sub(r"[^a-z' ]", " ", text)).strip()


def verify_quote(quote):
    v = quote["verify"]
    if "webc" in v:
        book, ref = v["webc"].rsplit(" ", 1)
        chapter, verse = map(int, ref.split(":"))
        row = sqlite3.connect(BIBLE).execute(
            "select v.text from verses v join books b on b.id = v.book_id where b.name = ? and chapter = ? and verse = ?",
            (book, chapter, verse)).fetchone()
        source = row[0] if row else ""
    elif "wikiquote" in v:
        source = api(WQ, {"action": "parse", "page": v["wikiquote"], "prop": "wikitext", "redirects": 1}) \
            .get("parse", {}).get("wikitext", "")
    else:
        source = fetch(v["url"], as_json=False)
    return normalize(quote["text"]) in normalize(source)


# ---------------------------------------------------------------- entries

ROLE_WORDS = {"priest", "priests", "bishop", "bishops", "martyr", "martyrs", "virgin", "virgins", "doctor", "doctors",
              "of", "the", "church", "religious", "abbot", "pope", "deacon", "apostle", "apostles", "evangelist",
              "hermit", "monk", "and", "first", "parents", "blessed", "mary", "spouse"}


def split_title(title):
    if ", " in title:
        name, rest = title.split(", ", 1)
        if all(w.lower() in ROLE_WORDS for w in re.findall(r"[A-Za-z]+", rest)):
            return name, rest
    return title, None


def capitalized(text):
    return text[:1].upper() + text[1:] if text else text


def main():
    calendar = json.load(open(CALENDAR))["celebrations"]
    quotes = {k: v for k, v in json.load(open(QUOTES)).items() if not k.startswith("_")}
    current = json.load(open(PATH))
    old = [(k, s) for k, v in current.items() if re.fullmatch(r"\d\d-\d\d", k) for s in v["saints"]]

    def wiki_title(url):
        return urllib.parse.unquote(url.rsplit("/", 1)[1]).replace("_", " ")

    titles = {w for c in calendar for w in c["wikipedia"]} | set(CELEBRATIONS.values()) | set(quotes)
    titles |= {wiki_title(s["wikipedia"]) for _, s in old if s.get("wikipedia")}
    review = {(d["date"], d["name"]): d for d in json.load(open(REVIEW))["decisions"]}
    # A rerun reads saints already moved or renamed by a decision: find it there too.
    for d in list(review.values()):
        if d["action"] != "remove":
            review.setdefault((d.get("to", d["date"]), d.get("new_name", d["name"])), d)
    martyrology = json.load(open(MARTYROLOGY))["saints"] if os.path.exists(MARTYROLOGY) else {}
    titles |= set(martyrology)
    titles |= {d["article"] for d in review.values() if d.get("article")}
    pages = resolve(titles)
    pages.update({p["title"]: p for p in list(pages.values())})  # also by the article's own title
    for p in {id(p): p for p in pages.values()}.values():
        if not p["extract"].strip():  # an article whose text starts under a heading
            r = api(WP, {"action": "query", "titles": p["title"], "prop": "extracts", "explaintext": 1,
                         "exsectionformat": "plain"})
            p["extract"] = (r.get("query", {}).get("pages") or [{}])[0].get("extract", "")
    canon = lambda t: pages[t]["title"] if t in pages else None

    ents = entities(p["qid"] for p in pages.values())
    claims = lambda title: ents.get(pages.get(title, {}).get("qid") or "", {}).get("claims", {})
    place_order = labels(q for e in ents.values() for p in ("P19", "P611") for q in item_ids(e.get("claims", {}), p)[:1])
    feast_labels = labels(q for e in ents.values() for q in item_ids(e.get("claims", {}), "P841"))

    def facts(title):
        c = claims(title)
        if "Q5" not in item_ids(c, "P31"):
            return {}
        return {k: v for k, v in {
            "born": year(c, "P569"), "died": year(c, "P570"),
            "birthplace": capitalized(place_order.get((item_ids(c, "P19") or [None])[0])),
            "order": place_order.get((item_ids(c, "P611") or [None])[0]),
            "canonized": canonized_year(c)}.items() if v}

    # Quotes, checked against their sources, keyed by canonical article.
    checked_quotes, failed_quotes = {}, []
    for key, q in quotes.items():
        if verify_quote(q):
            checked_quotes[canon(key) or key] = {"text": q["text"], "source": q["source"]}
        else:
            failed_quotes.append(key)

    # Patronages from the current data, by canonical article; kept only when the infobox lists them.
    old_by_article = {}
    for _, s in old:
        arts = [x["title"] for x in s.get("sources", [])] or ([wiki_title(s["wikipedia"])] if s.get("wikipedia") else [])
        for t in filter(None, map(canon, arts)):
            old_by_article.setdefault(t, s)
    infobox = infoboxes(set(old_by_article) | {canon(d["article"]) for d in review.values() if d.get("article")} - {None})

    def patronages(article):
        s = old_by_article.get(article)
        text = infobox.get(article, {}).get("patronage", "")
        if not s or not s.get("patronage") or not text:
            return None
        kept = [p.strip() for p in s["patronage"]
                if p.strip().lower() in text or all(w in text for w in re.findall(r"[a-z]{4,}", p.lower()))]
        return kept or None

    def sources(articles):
        return [{"title": a, "url": pages[a]["url"]} for a in articles]

    days = {f"{m:02d}-{d:02d}": [] for m in range(1, 13) for d in range(1, 32)
            if not (m in (4, 6, 9, 11) and d == 31) and not (m == 2 and d > 29)}

    mr_by_article = {canon(t) or t: v for t, v in martyrology.items()}

    def add_martyrology(entry, article, shown_date):
        """The day the 2004 Martyrologium Romanum lists the saint, when it differs from the day
        the app shows (the celebrated day). It is shown on the card, not used to move anyone."""
        mr = mr_by_article.get(article)
        if mr and mr["date"] != shown_date:
            m, d = int(mr["date"][:2]), int(mr["date"][3:])
            entry["martyrology"] = {"date": mr["date"], "label": f"{d} {MONTHS[m - 1]}", "entry": mr["entry"]}

    # 1. The calendar.
    calendar_articles = set()
    for c in calendar:
        articles = [canon(w) for w in c["wikipedia"] if canon(w)]
        calendar_articles |= set(articles)
        name, roles = split_title(c["title"])
        rank = c["rank"].capitalize()
        entry = {"name": name, "legacy": f"{roles} · {rank}" if roles else rank, "rank": c["rank"],
                 "calendar": c["calendar"]}
        if len(articles) == 1:
            entry["summary"] = description(pages[articles[0]]["extract"])
            entry.update(facts(articles[0]))
        else:
            entry["summary"] = "\n\n".join(short_description(pages[a]["extract"]) for a in articles)
        entry["patronage"] = None
        for a in articles:
            entry["patronage"] = entry["patronage"] or patronages(a)
        quote = next((checked_quotes[a] for a in articles if a in checked_quotes), None)
        if quote:
            entry["quote"] = quote
        if articles:
            entry["wikipedia"] = pages[articles[0]]["url"]
            entry["sources"] = sources(articles)
        if len(articles) == 1:
            add_martyrology(entry, articles[0], c["date"])
        days[c["date"]].append(entry)

    # 2. Other saints. A date is confirmed by Wikidata's feast day, the article's infobox feast
    # day, or a recorded review decision (Scripts/saint_date_review.json). Nothing is moved
    # automatically, because both sources often list Eastern dates; unconfirmed saints are listed.
    unconfirmed, removed = [], []
    for date, s in old:
        if s.get("rank"):
            continue  # a calendar entry from an earlier run; rebuilt above
        name = s["name"]
        article = canon(wiki_title(s["wikipedia"])) if s.get("wikipedia") else None
        decision = review.get((date, name))
        if decision and decision["action"] == "remove":
            removed.append({"date": date, "name": name, "reason": decision["evidence"], "basis": decision["basis"]})
            continue
        if decision and decision["action"] == "relink":
            article, name = canon(decision["article"]), decision.get("new_name", name)
        if article in calendar_articles:
            continue
        if not article:
            unconfirmed.append({"date": date, "name": name, "wikipedia": s.get("wikipedia"),
                                "wikidata_feast_days": [], "kept": False, "reason": "no Wikipedia article"})
            continue
        feasts = sorted({day_key(feast_labels.get(q)) for q in item_ids(claims(article), "P841")} - {None})
        box = infobox.get(article, {}).get("feast", "")
        if decision:
            target, date_source = decision.get("to", date), f"Review ({decision['basis']}): {decision['evidence']}"
        elif date in feasts:
            target, date_source = date, "Wikidata feast day"
        elif date in catholic_dates(box):
            target, date_source = date, f"Wikipedia infobox feast day: {box}"
        elif s.get("date_source"):
            target, date_source = date, s["date_source"]  # confirmed on an earlier run
        else:
            target, date_source = date, None
            unconfirmed.append({"date": date, "name": name, "wikipedia": pages[article]["url"],
                                "wikidata_feast_days": feasts, "infobox_feast_day": box, "kept": True,
                                "reason": "neither Wikidata nor the infobox gives this date"})
        if any(normalize(name) in normalize(e["name"]) or article in [x["title"] for x in e.get("sources", [])]
               for e in days[target]):
            continue  # the calendar already celebrates it that day
        desc = ents.get(pages[article]["qid"] or "", {}).get("descriptions", {}).get("en", {}).get("value")
        entry = {"name": name, "legacy": capitalized(desc) if desc else None,
                 "summary": description(pages[article]["extract"]), "patronage": patronages(article),
                 "wikipedia": pages[article]["url"], "sources": sources([article])}
        entry.update(facts(article))
        if date_source:
            entry["date_source"] = date_source
        add_martyrology(entry, article, target)
        if article in checked_quotes:
            entry["quote"] = checked_quotes[article]
        if not any(x.get("wikipedia") == entry["wikipedia"] for x in days[target]):
            days[target].append(entry)

    # 3. Feast descriptions for LiturgicalCelebrationBlurbs.
    celebrations = {}
    for cid, title in CELEBRATIONS.items():
        a = canon(title)
        celebrations[cid] = {"summary": description(pages[a]["extract"]), "wikipedia": pages[a]["url"],
                             "sources": sources([a])}

    out = {}
    for date, entries in days.items():
        m, d = int(date[:2]), int(date[3:])
        for e in entries:
            e["feast_day"] = f"{MONTHS[m - 1]} {d}"
        out[date] = {"date": date, "feast_day": f"{MONTHS[m - 1]} {d}", "count": len(entries), "saints": entries}
    out["index"] = {"days": len(days), "saints": sum(len(v) for v in days.values()), "dates": list(days)}
    out["celebrations"] = celebrations
    with open(PATH, "w") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    # Saints removed or left out on an earlier run are no longer in the input; keep their record.
    if os.path.exists(UNCONFIRMED):
        before = json.load(open(UNCONFIRMED))
        seen = {(u["date"], u["name"]) for u in unconfirmed}
        unconfirmed += [u for u in before.get("saints", []) if not u.get("kept") and (u["date"], u["name"]) not in seen]
        seen = {(r["date"], r["name"]) for r in removed}
        removed += [r for r in before.get("removed", []) if (r["date"], r["name"]) not in seen]
    for r in removed:  # the reason as the review file now gives it
        decision = review.get((r["date"], r["name"]))
        if decision and decision["action"] == "remove":
            r["reason"], r["basis"] = decision["evidence"], decision["basis"]
    with open(UNCONFIRMED, "w") as f:
        json.dump({"_about": "Saints outside the calendar whose date neither Wikidata, the Wikipedia infobox nor a "
                             "review decision confirms. 'kept': true means the saint is still shown on that date; "
                             "'kept': false means it is left out (no Wikipedia article to describe it). 'removed' "
                             "lists saints taken out by Scripts/saint_date_review.json, with the reason.",
                   "saints": unconfirmed, "removed": removed}, f, ensure_ascii=False, indent=1)

    empty = [d for d, e in days.items() if not e]
    print(f"calendar entries {len(calendar)}, other saints kept {sum(len(e) for e in days.values()) - len(calendar)}, "
          f"unconfirmed dates kept {sum(u['kept'] for u in unconfirmed)}, "
          f"left out {sum(not u['kept'] for u in unconfirmed)}, removed by review {len(removed)}, "
          f"days with no saint {len(empty)}")
    print(f"quotes: {len(checked_quotes)} verified, failed: {failed_quotes}")
    print("empty days:", " ".join(empty))


if __name__ == "__main__":
    main()
