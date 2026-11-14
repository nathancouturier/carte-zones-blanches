#!/usr/bin/env bash
# Andorre et Monaco, sonde 5 : vérifications finales (lecture de catalogues et de pages, aucune donnée de carte).
#  A. Andorre : toutes les fiches du catalogue de l'IDE Andorra (CSW en POST), espaces de travail du WMS, résumé des
#     couches « antrepetidor » et « cobertura_FEDA », rubriques du portail du Govern (radiations, télécommunications).
#  B. Monaco : page de la Direction des Plateformes et des Ressources Numériques (couverture ? données ouvertes ?).
#  C. OpenCelliD : nombre de cellules connues pour l'Andorre et Monaco (page publique de statistiques).
set -u
. "$(dirname "$0")/_lib.sh"
# User-Agent générique : aucun nom de projet ni de personne dans les requêtes sortantes.
UA="sonde-sources-ouvertes/1.0 (verification ponctuelle de sources publiques)"
export UA T
python3 - <<'PY'
import re, os, subprocess, html, json, traceback, urllib.parse
import xml.etree.ElementTree as ET

T = os.environ["T"]; UA = os.environ["UA"]
KW = r"telecom|telef|antena|antenes|antrepetidor|cobertura|radio|m[oò]bil|emissi|comunicaci|electromagn|\b[45]g\b|xarxa|repetidor|fibra"

def fetch(url, out, maxtime=60, extra=()):
    try:
        os.remove(out)   # jamais de relecture d'une réponse précédente
    except OSError:
        pass
    r = subprocess.run(["curl", "-sS", "-L", "--connect-timeout", "15", "-m", str(maxtime), "-A", UA, *extra, "-o", out, "-w",
                        "%{http_code} %{size_download}o %{content_type} | final=%{url_effective}", url],
                       capture_output=True, text=True)
    err = (r.stderr or "").strip().replace("\n", " ")[:140]
    return ((r.stdout or "").strip()[:260] + (" | ERREUR " + err if err else ""))

def read(path):
    try:
        return open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return ""

def text_of(s):
    s = re.sub(r"<(script|style|svg|noscript)\b.*?</\1>", " ", s, flags=re.S | re.I)
    s = re.sub(r"<!--.*?-->", " ", s, flags=re.S)
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", s))).strip()

def show(s, maxc=1500, width=240, indent="    "):
    s = re.sub(r"\s+", " ", str(s)).strip()
    cut = s[:maxc]
    for k in range(0, len(cut), width):
        print(indent + cut[k:k + width])
    if len(s) > maxc:
        print(indent + f"[... tronqué, {len(s)} caractères au total]")

def title_of(s):
    m = re.search(r"<title[^>]*>(.*?)</title>", s, flags=re.S | re.I)
    return re.sub(r"\s+", " ", html.unescape(m.group(1))).strip()[:160] if m else "(pas de titre)"

def links(s, base):
    out, seen = [], set()
    for m in re.finditer(r'<a\b[^>]*?href\s*=\s*["\']([^"\'#]+)["\'][^>]*>(.*?)</a>', s, flags=re.S | re.I):
        href = urllib.parse.urljoin(base, html.unescape(m.group(1)).strip())
        if href in seen or href.startswith(("javascript:", "mailto:", "tel:")):
            continue
        seen.add(href)
        out.append((href, text_of(m.group(2))[:90]))
    return out

def guarded(fn):
    try:
        fn()
    except Exception:
        print("    ECHEC :", traceback.format_exc()[-700:])

def contexts(t, rx, n=2, before=250, after=450, flags=re.I):
    k, last = 0, -10**9
    for m in re.finditer(rx, t, flags=flags):
        if m.start() - last < after:
            continue
        show("« " + t[max(0, m.start() - before):m.start() + after] + " »", before + after + 10)
        last = m.start(); k += 1
        if k >= n:
            break
    return k

def main_text(s):
    m = re.search(r"<(main|article)\b.*?</\1>", s, flags=re.S | re.I)
    return text_of(m.group(0)) if m else text_of(s)

def loc(t):
    return t.rsplit("}", 1)[-1]

# ---------------------------------------------------------------------------------------------------------------
print("##### A. ANDORRE")
def parse_records(s):
    root = ET.fromstring(s.encode("utf-8", "replace"))
    sr = next((e for e in root.iter() if loc(e.tag) == "SearchResults"), None)
    if sr is None:
        return None, 0, 0, root
    recs = []
    for rec in sr:
        d = {"id": None, "title": None, "type": None, "subject": [], "abstract": None}
        for c in rec:
            k = loc(c.tag); v = (c.text or "").strip()
            if k == "identifier" and not d["id"]: d["id"] = v
            elif k == "title" and not d["title"]: d["title"] = v
            elif k == "type" and not d["type"]: d["type"] = v
            elif k == "subject" and v: d["subject"].append(v)
            elif k == "abstract" and not d["abstract"]: d["abstract"] = v
        recs.append(d)
    return recs, int(sr.attrib.get("numberOfRecordsMatched", "0")), int(sr.attrib.get("nextRecord", "0")), root

def section_a():
    CSW = "https://www.ideandorra.ad/Cataleg/srv/cat/csw"
    print("--- A1. catalogue de métadonnées : toutes les fiches")
    out = f"{T}/csw_get.xml"
    st = fetch(CSW + "?service=CSW&version=2.0.2&request=GetRecords&resultType=results&typeNames=csw:Record&elementSetName=summary&outputSchema=http://www.opengis.net/cat/csw/2.0.2&maxRecords=5&startPosition=1", out)
    print("  ->", st[:110], "| réponse brute de la requête GET :", re.sub(r"\s+", " ", read(out))[:420])
    body_tpl = ('<?xml version="1.0" encoding="UTF-8"?>'
                '<csw:GetRecords xmlns:csw="http://www.opengis.net/cat/csw/2.0.2" xmlns:ogc="http://www.opengis.net/ogc" service="CSW" version="2.0.2" '
                'resultType="results" startPosition="%d" maxRecords="200" outputSchema="http://www.opengis.net/cat/csw/2.0.2">'
                '<csw:Query typeNames="csw:Record"><csw:ElementSetName>summary</csw:ElementSetName>%s</csw:Query></csw:GetRecords>')
    constraint = ('<csw:Constraint version="1.1.0"><ogc:Filter><ogc:PropertyIsLike wildCard="%" singleChar="_" escapeChar="!">'
                  '<ogc:PropertyName>AnyText</ogc:PropertyName><ogc:Literal>%</ogc:Literal></ogc:PropertyIsLike></ogc:Filter></csw:Constraint>')
    records, matched = [], None
    for variant, cons in (("sans contrainte", ""), ("avec contrainte AnyText", constraint)):
        records, start, matched = [], 1, None
        for page in range(6):
            req = f"{T}/req.xml"
            open(req, "w", encoding="utf-8").write(body_tpl % (start, cons))
            out = f"{T}/csw_post.xml"
            st = fetch(CSW, out, 120, ("-H", "Content-Type: application/xml", "--data-binary", "@" + req))
            s = read(out)
            try:
                recs, matched, nxt, root = parse_records(s)
            except Exception as e:
                print(f"  -> {st[:90]} | POST {variant}, position {start} : XML illisible ({str(e)[:60]}) :", re.sub(r"\s+", " ", s)[:300]); recs = None
                break
            if recs is None:
                print(f"  -> {st[:90]} | POST {variant}, position {start} : pas de SearchResults :", re.sub(r"\s+", " ", s)[:400])
                break
            records += recs
            print(f"  -> {st[:60]} | POST {variant}, position {start} : {matched} fiches correspondantes, {len(recs)} reçues, suivante {nxt}")
            if not recs or nxt == 0 or nxt > matched:
                break
            start = nxt
        if records:
            break
    print("     total de fiches lues :", len(records), "sur", matched)
    if records:
        types = {}
        for d in records:
            types[d["type"]] = types.get(d["type"], 0) + 1
        print("     types :", types)
        subj = {}
        for d in records:
            for x in d["subject"]:
                subj[x] = subj.get(x, 0) + 1
        show("mots-clés : " + " ; ".join(f"{k} ({v})" for k, v in sorted(subj.items(), key=lambda kv: -kv[1])[:90]), 2600, 230, "     ")
        show("titres de toutes les fiches : " + " ¦ ".join(sorted({(d["title"] or "?") for d in records})), 9000, 230, "     ")
        hits = [d for d in records if re.search(KW, " ".join([d["title"] or "", " ".join(d["subject"]), d["abstract"] or ""]), re.I)]
        print(f"     fiches évoquant télécoms, radio, antennes, couverture, réseau ou communications : {len(hits)}")
        for d in hits[:16]:
            m = re.search(KW, " ".join([d["title"] or "", " ".join(d["subject"]), d["abstract"] or ""]), re.I)
            print(f"       - [{d['type']}] {d['title']} | mot trouvé : « {m.group(0)} » | résumé : {(d['abstract'] or '')[:230]}")

    print("--- A2. service WMS global : espaces de travail et couches à examiner")
    out = f"{T}/wms.xml"
    u = "https://www.ideandorra.ad/Serveis/ows?service=WMS&version=1.3.0&request=GetCapabilities"
    st = fetch(u, out, 180)
    print("  ->", st[:120])
    root = ET.fromstring(read(out).encode("utf-8", "replace"))
    svc = [(loc(e.tag), (e.text or "").strip()[:200]) for e in root.iter() if loc(e.tag) in ("AccessConstraints", "Fees", "ContactOrganization", "ContactElectronicMailAddress") and (e.text or "").strip()]
    st_title = next(((c.text or "").strip() for e in root.iter() if loc(e.tag) == "Service" for c in e if loc(c.tag) == "Title"), None)
    st_abs = next(((c.text or "").strip() for e in root.iter() if loc(e.tag) == "Service" for c in e if loc(c.tag) == "Abstract"), None)
    print("     service :", repr(st_title), "| résumé :", repr((st_abs or "")[:300]), "|", svc[:6])
    layers = []
    for e in root.iter():
        if loc(e.tag) == "Layer":
            n = next(((c.text or "").strip() for c in e if loc(c.tag) == "Name"), None)
            t = next(((c.text or "").strip() for c in e if loc(c.tag) == "Title"), None)
            a = next(((c.text or "").strip() for c in e if loc(c.tag) == "Abstract"), None)
            kws = [(k.text or "").strip() for c in e if loc(c.tag) == "KeywordList" for k in c]
            if n:
                layers.append((n, t, a, kws))
    ws = {}
    for n, t, a, k in layers:
        p = n.split(":", 1)[0] if ":" in n else "(sans préfixe)"
        ws[p] = ws.get(p, 0) + 1
    print(f"     {len(layers)} couches nommées dans {len(ws)} espaces de travail :")
    show(" ; ".join(f"{k} ({v})" for k, v in sorted(ws.items())), 3500, 230, "       ")
    for n, t, a, k in layers:
        if re.search(r"antrepetidor|cobertura|telecom|antena|radioel|telefon", f"{n} {t} {a}", re.I):
            print(f"     couche {n} | titre : {t} | résumé : {(a or '')[:400]!r} | mots-clés : {k[:8]}")

    print("--- A3. portail du Govern : rubriques sur les radiations, les antennes ou les télécommunications")
    out = f"{T}/gov.html"
    u = "https://www.govern.ad/"
    st = fetch(u, out, 90)
    print("  ->", st[:110])
    s = read(out)
    ls = links(s, "https://www.govern.ad/ca/inici")
    print("     nombre de liens dans la page d'accueil :", len(ls))
    hit = [(x[:70], h[:150]) for h, x in ls if re.search(r"radiaci|electromagn|antena|antenes|telecom|telefonia|comunicacions electr|cobertura|transformaci[oó] digital|dades obertes|open ?data", h + " " + x, re.I)]
    print(f"     liens retenus ({len(hit)}) :")
    for x, h in hit[:16]:
        print("       ", x, "=>", h)
    for h in [h for x, h in hit if re.search(r"telecom|transformaci", h + x, re.I)][:2]:
        out = f"{T}/gov2.html"
        st = fetch(h, out, 60)
        s2 = read(out)
        print("  ->", st[:100], "|", h[:150])
        if st.startswith("200"):
            t = main_text(s2)
            print("     titre :", title_of(s2), "| longueur :", len(t))
            if not contexts(t, r"cobertura|mapa|antenes|dades obertes", 2, 200, 450):
                show(t, 500)
guarded(section_a)

# ---------------------------------------------------------------------------------------------------------------
print("##### B. MONACO : Direction des Plateformes et des Ressources Numériques")
def section_b():
    u0 = "https://www.gouv.mc/en/action-gouvernementale/poursuivre-la-transition-energetique-et-renaturer-la-ville/reduire-les-emissions-de-gaz-a-effet-de-serre/carte-des-mesures-electromagnetiques"
    out = f"{T}/mc0.html"
    print("  ->", fetch(u0, out)[:60])
    g = read(out)
    cand = [(h, x) for h, x in links(g, u0) if re.search(r"digital platforms|plateformes|ressources num|measurements of electromagnetic|mesures", h + " " + x, re.I)]
    print("     liens :", [(x[:60], h[:160]) for h, x in cand[:6]])
    for h, x in cand[:3]:
        out = f"{T}/mc1.html"
        st = fetch(h, out)
        s = read(out)
        print("  ->", st[:100], "|", h[:160])
        if st.startswith("200"):
            t = main_text(s)
            print("     titre :", title_of(s), "| longueur :", len(t))
            show(t, 700)
            n = contexts(t, r"coverage|couverture|open ?data|donn[eé]es ouvertes|cartoradio|mobile network|r[eé]seaux? mobiles?", 3, 200, 450)
            print("     passages trouvés :", n)
guarded(section_b)

# ---------------------------------------------------------------------------------------------------------------
print("##### C. OpenCelliD : statistiques publiques par pays")
def section_c():
    out = f"{T}/oc.html"
    st = fetch("https://opencellid.org/stats.php", out, 90)
    print("  ->", st[:120])
    s = read(out)
    rows = re.findall(r"<tr[^>]*>(.*?)</tr>", s, flags=re.S | re.I)
    head = None
    for r in rows:
        cells = [text_of(c) for c in re.findall(r"<t[hd][^>]*>(.*?)</t[hd]>", r, flags=re.S | re.I)]
        if cells and re.search(r"^Country$", cells[0], re.I):
            head = cells
        if cells and cells[0] in ("Andorra", "Monaco", "France", "Spain", "Italy", "Switzerland", "Kosovo"):
            print("     ", dict(zip(head or [], cells)) if head and len(head) == len(cells) else cells)
    m = re.search(r"(updated|last update|as of)[^<]{0,80}", text_of(s), re.I)
    print("     mention de date :", m.group(0)[:120] if m else "(aucune)")
guarded(section_c)
PY
echo "FIN"
