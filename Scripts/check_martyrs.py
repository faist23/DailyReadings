#!/usr/bin/env python3
"""Report-only: checks the saints in saints.json that are outside the calendar against the Vatican's
list of martyrs by day (Pontifical Academy Cultorum Martyrum), matching by Wikidata's Italian
names. Prints confirmed / other date / not in list and writes the details to a JSON file for
review. It changes nothing; moves go in Scripts/saint_date_review.json with the quoted evidence.
A shared first name is not the same person: read each "other date" snippet before acting.

Run from the repo root:  python3 -I Scripts/check_martyrs.py OUT.json [--cache DIR]
"""
import sys,json,re,html,unicodedata,urllib.parse
OUT=sys.argv[1]
exec(open('Scripts/build_saints.py').read().split('def main')[0])
VATICAN="https://www.vatican.va/roman_curia/pontifical_academies/cult-martyrum/martiri/009.html"
# Vatican list -> [(date, text)] per day
t=fetch(VATICAN, as_json=False)
t=re.sub(r'\s+',' ',html.unescape(re.sub(r'<[^>]+>',' ',t)))
mesi=['Gennaio','Febbraio','Marzo','Aprile','Maggio','Giugno','Luglio','Agosto','Settembre','Ottobre','Novembre','Dicembre']
marks=[(m.start(),f"{[x.lower() for x in mesi].index(m.group(2).lower())+1:02d}-{int(m.group(1)):02d}") for m in re.finditer(r'\b(\d{1,2})\s+('+'|'.join(mesi)+r')\s*\.?\s+(?=S\.|SS\.|Ss\.|B\.|BB\.|Bb\.|Memoria|Commemorazione|Ricordo|Santi|Beati)',t,re.I)]
days={}
for i,(p,k) in enumerate(marks):
    days[k]=days.get(k,'')+' '+t[p:(marks[i+1][0] if i+1<len(marks) else len(t))]
fold=lambda s: unicodedata.normalize('NFKD',s).encode('ascii','ignore').decode().lower()
D={k:fold(v) for k,v in days.items()}
print('vatican days',len(D))
data=json.load(open(PATH))
rows=[(k,s) for k,v in data.items() if re.fullmatch(r'\d\d-\d\d',k) for s in v['saints'] if not s.get('rank')]
wt=lambda u: urllib.parse.unquote(u.rsplit('/',1)[1]).replace('_',' ')
pages=resolve([wt(s['wikipedia']) for _,s in rows])
qids=sorted({p['qid'] for p in pages.values() if p['qid']})
it={}
for i in range(0,len(qids),50):
    r=api(WD,{"action":"wbgetentities","ids":"|".join(qids[i:i+50]),"props":"labels|aliases","languages":"it"})
    for q,e in r.get('entities',{}).items():
        names=[e.get('labels',{}).get('it',{}).get('value')]+[a['value'] for a in e.get('aliases',{}).get('it',[])]
        it[q]=[n for n in names if n]
def keys(n):
    n=fold(n); n=re.sub(r"^(san|santa|santo|sant'|beato|beata|papa|santi|sante)\s+","",n)
    n=re.sub(r"\s*\(.*?\)","",n).strip()
    return n
out=[]
for date,s in rows:
    p=pages.get(wt(s['wikipedia'])); q=p and p['qid']
    names=sorted({keys(n) for n in it.get(q,[])} - {''})
    hits={}
    for n in names:
        if len(n)<4: continue
        for k,v in D.items():
            for m in re.finditer(r'\b'+re.escape(n)+r'\b',v):
                hits.setdefault(k,v[max(0,m.start()-80):m.start()+220])
    status='not in list' if not hits else ('confirmed' if date in hits else 'other date')
    out.append(dict(date=date,name=s['name'],article=p['title'] if p else None,italian=names,status=status,
                    vatican_dates=sorted(hits),snippets={k:hits[k] for k in sorted(hits)[:4]}, date_source=s.get('date_source','')[:80]))
json.dump(out,open(OUT,'w'),ensure_ascii=False,indent=1)
from collections import Counter; print(Counter(o['status'] for o in out))
