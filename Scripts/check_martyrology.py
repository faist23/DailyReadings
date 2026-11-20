#!/usr/bin/env python3
"""Checks Scripts/martyrology_2004.json against the 2004 Martyrologium Romanum.

Each entry records a saint's line in the book's index of names ("Macarius Alexandrinus,
19 ian., 5 (s. V)") and the date taken from it, or (with "in": "text") a passage from the
day's entry in the body of the book, accents removed and lowercased ("romae, sancti eusebii,
tituli sui conditoris in exquiliis"); such a passage must sit under that day's heading
("Die 14 augusti") with the next day's heading present, so the day is not in doubt. This downloads the book's OCR text from the
Internet Archive (https://archive.org/details/MartRom2004) and fails if any line is not in the
index or its date does not match the line. The book's text is not kept in the repository.

Run from the repo root:  python3 -I Scripts/check_martyrology.py [--cache FILE]
"""
import datetime, json, os, re, sys, unicodedata, urllib.request

URL = "https://archive.org/download/MartRom2004/Martyrologium%20Romanum%20(2004)_djvu.txt"
DATA = "Scripts/martyrology_2004.json"
MONTHS = {"ian": 1, "feb": 2, "febr": 2, "mar": 3, "mart": 3, "apr": 4, "mai": 5, "maii": 5, "iun": 6,
          "iul": 7, "aug": 8, "sep": 9, "sept": 9, "oct": 10, "nov": 11, "dec": 12}
OCR = [(r"1ian|1an|lan|tan|1ani", "ian"), (r"1iun|1un|lun", "iun"), (r"1iul|1ul|lul|il|iu1", "iul"),
       (r"mati|mail|maij|man|mau", "maii")]


def text():
    cache = sys.argv[sys.argv.index("--cache") + 1] if "--cache" in sys.argv else None
    if cache and os.path.exists(cache):
        return open(cache, encoding="utf-8", errors="replace").read()
    raw = urllib.request.urlopen(urllib.request.Request(URL, headers={"User-Agent": "DailyReadings-data-script/1.0"}),
                                 timeout=120).read().decode("utf-8", errors="replace")
    if cache:
        open(cache, "w", encoding="utf-8").write(raw)
    return raw


def dates(line):
    for bad, good in OCR:
        line = re.sub(r"(\b\d{1,2})\s*(?:" + bad + r")\b", r"\1 " + good, line)
    return {f"{MONTHS[m.group(2)]:02d}-{int(m.group(1)):02d}"
            for m in re.finditer(r"\b(\d{1,2})\s*\.?\s*(" + "|".join(MONTHS) + r")\b", line)}


LATIN_MONTHS = ["ianuarii", "februarii", "martii", "aprilis", "maii", "iunii", "iulii", "augusti",
                "septembris", "octobris", "novembris", "decembris"]


def body_days(book):
    """Day -> folded text of that day's entries, for days whose next day's heading is present."""
    body = book[:book.index("INDEX NOMINUM SANCTORUM ET BEATORUM")]
    heads = {}
    for m in re.finditer(r"^Die (\d{1,2}) (" + "|".join(LATIN_MONTHS) + r")\s*$", body, re.M):
        heads.setdefault(f"{LATIN_MONTHS.index(m.group(2)) + 1:02d}-{int(m.group(1)):02d}", m.start())
    order = sorted(heads.items(), key=lambda kv: kv[1])
    fold = lambda t: unicodedata.normalize("NFKD", t).encode("ascii", "ignore").decode().lower()
    days = {}
    for i, (day, start) in enumerate(order):
        nxt = (datetime.date(2024, int(day[:2]), int(day[3:])) + datetime.timedelta(1)).strftime("%m-%d")
        if i + 1 < len(order) and order[i + 1][0] == nxt:
            days[day] = re.sub(r"\s+", " ", fold(re.sub(r"-\s*\n\s*", "", body[start:order[i + 1][1]])))
    return days


def main():
    book = text()
    index = book[book.index("INDEX NOMINUM SANCTORUM ET BEATORUM"):]
    # Page headers and page numbers interrupt entries that run across a page break.
    index = re.sub(r"INDEX NOMINUM SANCTORUM ET BEATORUM|\n\s*\d{3,4}\s*\n", " ", index)
    index = re.sub(r"\s+", " ", index)
    entries = json.load(open(DATA))["saints"]
    days = body_days(book)
    bad = []
    for article, e in entries.items():
        line = re.sub(r"\s+", " ", e["entry"]).strip()
        if e.get("in") == "text":
            if e["date"] not in days:
                bad.append(f"{article}: no unambiguous section for {e['date']} in the text")
            elif line not in days[e["date"]]:
                bad.append(f"{article}: passage not under {e['date']}: {line}")
        elif line not in index:
            bad.append(f"{article}: line not in the index: {line}")
        elif e["date"] not in dates(line):
            bad.append(f"{article}: {e['date']} is not the date in: {line}")
    print(f"{len(entries)} entries checked, {len(bad)} problems")
    for b in bad:
        print("  " + b)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
