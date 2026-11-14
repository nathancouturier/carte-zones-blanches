#!/usr/bin/env bash
# Andorre et Monaco, sonde 1 : reconnaissance.
#  A. UIT : dernière liste récapitulative E.212 des codes MCC + MNC (Andorre, Monaco, Suisse, Italie, Espagne, France).
#  B. Monaco : portail data.gouv.mc, site officiel cartoradio.mc (ce qu'il publie, mentions légales), page gouv.mc.
#  C. Andorre : IDE Andorra (services OGC, catalogue), portail du Govern (données ouvertes ?).
#  D. Régulateurs : où sont les listes nationales de MNC (OFCOM, MIMIT, CNMC).
# Aucune donnée de carte n'est téléchargée ici : on lit des pages, des catalogues et des conditions d'utilisation.
set -u
. "$(dirname "$0")/_lib.sh"
# User-Agent générique : aucun nom de projet ni de personne dans les requêtes sortantes.
UA="sonde-sources-ouvertes/1.0 (verification ponctuelle de sources publiques)"
export UA T
(apt-get install -y -qq poppler-utils || { apt-get update -qq && apt-get install -y -qq poppler-utils; }) >/dev/null 2>&1
python3 - <<'PY'
import re, os, subprocess, html, json, traceback, urllib.parse
import xml.etree.ElementTree as ET

T = os.environ["T"]; UA = os.environ["UA"]
KW = r"telecom|telef|t[eé]l[eé]ph|antena|antenes|antenne|cobertura|couverture|radio|m[oò]bil|mobile|emissi|[eé]mission|comunicaci|communication|electromagn|[eé]lectromagn|ondes|\b[45]g\b|xarxa|r[eé]seau"

def fetch(url, out, maxtime=120, extra=()):
    r = subprocess.run(["curl", "-sS", "-L", "-m", str(maxtime), "-A", UA, *extra, "-o", out, "-w",
                        "%{http_code} %{size_download}o %{content_type} | final=%{url_effective}", url],
                       capture_output=True, text=True)
    return (r.stdout or r.stderr).strip()[:300]

def head(url):
    r = subprocess.run(["curl", "-sS", "-I", "-L", "-m", "40", "-A", UA, "-o", "/dev/null", "-w",
                        "%{http_code} %{content_type} longueur=%header{content-length}", url], capture_output=True, text=True)
    return (r.stdout or r.stderr).strip()[:200]

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
    s = re.sub(r"\s+", " ", s).strip()
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
        out.append((href, text_of(m.group(2))[:70]))
    return out

def scripts(s, base):
    return [urllib.parse.urljoin(base, html.unescape(u)) for u in re.findall(r'<script\b[^>]*?src\s*=\s*["\']([^"\']+)["\']', s, flags=re.I)]

def endpoints(s):
    rx = r'["\'`]((?:https?:)?/?/?[^"\'`\s<>]*(?:geoserver|geonetwork|/wms|/wfs|/ows|/csw|wmts|arcgis|rest/services|/api/|\.geojson|\.json|\.csv|\.kml|\.gpkg|export|download|descarreg)[^"\'`\s<>]*)["\'`]'
    out = []
    for u in re.findall(rx, s, flags=re.I):
        if u not in out and len(u) < 220:
            out.append(u)
    return out

def guarded(fn):
    try:
        fn()
    except Exception:
        print("    ECHEC :", traceback.format_exc()[-600:])

def page(url, name, nchars=900, link_rx=None, maxlinks=25, want_endpoints=False):
    out = f"{T}/{name}.html"
    st = fetch(url, out)
    print("  ->", st, "|", url)
    s = read(out)
    if not st.startswith("200"):
        if s:
            print("     titre :", title_of(s))
        return ""
    print("     titre :", title_of(s))
    if nchars:
        show(text_of(s), nchars)
    if link_rx is not None:
        ls = [(h, t) for h, t in links(s, url) if re.search(link_rx, h + " " + t, re.I)]
        print(f"     liens retenus ({len(ls)}) :")
        for h, t in ls[:maxlinks]:
            print(f"       {t[:60]} => {h[:170]}")
    if want_endpoints:
        eps = endpoints(s)
        print(f"     chaînes de type service ou données dans la page ({len(eps)}) :", eps[:20])
    return s

# ---------------------------------------------------------------------------------------------------------------
print("##### A. UIT : liste récapitulative E.212 (MCC + MNC)")
def section_a():
    best = None
    for y in range(2026, 2018, -1):
        u = f"https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-E.212B-{y}-PDF-E.pdf"
        st = head(u)
        print(f"   édition {y} : {st}")
        if st.startswith("200") and "pdf" in st.lower():
            best = u
            break
    if best is None:
        best = "https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-E.212B-2018-PDF-E.pdf"
    out = f"{T}/e212.pdf"
    print("  ->", fetch(best, out, 300), "|", best)
    info = subprocess.run(["pdfinfo", out], capture_output=True, text=True).stdout
    print("    ", " | ".join(l.strip() for l in info.splitlines() if re.search(r"^(Title|Pages|CreationDate|ModDate)", l))[:300])
    subprocess.run(["pdftotext", "-layout", out, out + ".txt"])
    txt = read(out + ".txt")
    lines = txt.splitlines()
    print("   premières lignes non vides du document :")
    k = 0
    for l in lines:
        if l.strip():
            print("     |", l.strip()[:200]); k += 1
        if k >= 14:
            break
    targets = {"213": "Andorre", "212": "Monaco", "228": "Suisse", "222": "Italie", "214": "Espagne", "208": "France",
               "295": "Liechtenstein", "221": "Kosovo"}
    entries, country = [], None
    for l in lines:
        m = re.search(r"(?<!\d)(\d{3})\s(\d{2,3})\s*$", l)
        if m:
            left = l[:m.start()].rstrip()
            parts = [p for p in re.split(r"\s{2,}", left.strip()) if p]
            if l[:1].strip() and len(parts) >= 2:
                country = parts[0]; name = " ".join(parts[1:])
            else:
                name = " ".join(parts)
            entries.append((country, name, m.group(1), m.group(2)))
        elif l[:1].strip() and not re.search(r"Annex to ITU|^\s*–\s*\d+\s*–|Country or|Geographical|^_+|^\*|Networks", l):
            country = l.strip()
    print("   entrées MCC+MNC reconnues dans tout le document :", len(entries))
    for mcc, nom in targets.items():
        es = [e for e in entries if e[2] == mcc]
        pays = sorted({e[0] or "?" for e in es})
        print(f"   --- MCC {mcc} ({nom}) : {len(es)} entrée(s) ; rubrique(s) du document : {pays}")
        show(" | ".join(f"{e[3]} {e[1]}" for e in es), 2600, 230, "       ")
    print("   lignes brutes autour d'Andorre, de Monaco et du Kosovo :")
    for i, l in enumerate(lines):
        if re.search(r"^\s*(Andorra|Monaco|Kosovo)\b", l):
            for j in range(i, min(i + 5, len(lines))):
                if lines[j].strip():
                    print("     |", lines[j].rstrip()[:200])
            print("     .")
    notes = [l.strip() for l in lines if re.search(r"^\s*\*|shared|Kosovo|footnote", l, re.I)]
    print("   notes (extrait) :")
    for l in notes[:8]:
        print("     |", l[:230])
guarded(section_a)

print("##### A2. UIT : dernier Bulletin d'exploitation (référence de la liste MNC en vigueur et amendement en cours)")
def section_a2():
    u = "https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-OB.1351-2026-OAS-PDF-E.pdf"
    out = f"{T}/ob.pdf"
    print("  ->", fetch(u, out, 300), "|", u)
    subprocess.run(["pdftotext", "-layout", out, out + ".txt"])
    lines = read(out + ".txt").splitlines()
    k = 0
    for i, l in enumerate(lines):
        if re.search(r"Mobile Network Codes? \(MNC\)", l):
            print("     | l.%d : %s" % (i, " / ".join(x.strip() for x in lines[i:i + 5] if x.strip())[:420]))
            k += 1
        if k >= 5:
            break
    # contenu de l'amendement publié dans ce bulletin
    for i, l in enumerate(lines):
        if re.search(r"\(Amendment No\.?\s*\d+\)", l) and any("Mobile Network Codes" in x for x in lines[max(0, i - 6):i + 1]):
            print("   amendement MNC de ce bulletin :")
            for x in lines[i - 4:i + 22]:
                if x.strip():
                    print("     |", x.rstrip()[:200])
            break
guarded(section_a2)

# ---------------------------------------------------------------------------------------------------------------
print("##### B. MONACO")
def section_b():
    print("--- B1. portail de données ouvertes data.gouv.mc")
    s = page("https://data.gouv.mc/", "mc_data", 500, r"donn|data|jeu|licen|condition|mention|api|catalog|explore|th[eè]me", 20, True)
    for name, u in [("ods", "https://data.gouv.mc/api/explore/v2.1/catalog/datasets?limit=100"),
                    ("ckan", "https://data.gouv.mc/api/3/action/package_search?rows=300"),
                    ("udata", "https://data.gouv.mc/api/1/datasets/?page_size=200")]:
        out = f"{T}/mc_{name}.json"
        st = fetch(u, out, 90)
        print("  ->", st, "|", u)
        if not st.startswith("200"):
            continue
        try:
            d = json.load(open(out, encoding="utf-8", errors="replace"))
        except Exception as e:
            print("     (pas du JSON :", str(e)[:80], ")"); continue
        rows = []
        if name == "ods":
            print("     total_count :", d.get("total_count"))
            for r in d.get("results", []):
                meta = (r.get("metas") or {}).get("default") or {}
                rows.append((r.get("dataset_id"), meta.get("title"), meta.get("license"), meta.get("publisher"), meta.get("modified"), " ".join(meta.get("theme") or []) + " " + " ".join(meta.get("keyword") or [])))
        elif name == "ckan":
            res = d.get("result") or {}
            print("     count :", res.get("count"))
            for r in res.get("results", []):
                rows.append((r.get("name"), r.get("title"), r.get("license_title") or r.get("license_id"), (r.get("organization") or {}).get("title"), r.get("metadata_modified"), " ".join(t.get("name", "") for t in r.get("tags") or [])))
        else:
            print("     total :", d.get("total"))
            for r in d.get("data", []):
                rows.append((r.get("slug"), r.get("title"), r.get("license"), (r.get("organization") or {}).get("name"), r.get("last_modified"), " ".join(r.get("tags") or [])))
        print("     jeux listés :", len(rows))
        lic = {}
        for r in rows:
            lic[r[2]] = lic.get(r[2], 0) + 1
        print("     licences :", lic)
        hits = [r for r in rows if re.search(KW, " ".join(str(x) for x in r if x), re.I)]
        print(f"     jeux dont le titre ou les mots-clés évoquent les télécoms ({len(hits)}) :")
        for r in hits[:25]:
            print("       ", " | ".join(str(x)[:90] for x in r[:5]))
        show(" ; ".join(str(r[1]) for r in rows), 2200, 230, "       tous les titres : ")
        break

    print("--- B2. cartoradio.mc (site officiel des mesures et des sites radio)")
    for u in ["https://www.cartoradio.mc/", "https://cartoradio.mc/"]:
        s = page(u, "mc_carto", 1500, r".", 40, True)
        if s:
            base = u
            break
    else:
        s, base = "", ""
    if s:
        sc = scripts(s, base)
        print("     scripts :", [x[:130] for x in sc[:14]])
        host = urllib.parse.urlparse(base).netloc.replace("www.", "")
        seen = []
        for x in [x for x in sc if host in urllib.parse.urlparse(x).netloc][:6]:
            out = f"{T}/mc_js.js"
            st = fetch(x, out, 90)
            js = read(out)
            eps = [e for e in endpoints(js) if e not in seen]
            seen += eps
            print(f"     script {x[:110]} : {st[:40]} | chaînes de type service ou données : {eps[:14]}")
        legal = [(h, t) for h, t in links(s, base) if re.search(r"mention|l[eé]gal|condition|cgu|propos|cr[eé]dit|donn[eé]es|open|licen|confidential|aide|faq", h + " " + t, re.I)]
        print("     liens juridiques ou d'aide :", legal[:10])
        done = 0
        for h, t in legal:
            if done >= 3:
                break
            if urllib.parse.urlparse(h).netloc.replace("www.", "") not in (host, "gouv.mc", "en.gouv.mc"):
                continue
            page(h, "mc_legal", 2600)
            done += 1
        m = re.search(r"(?is)(mentions?\s+l[eé]gales?|conditions?\s+d.utilisation|droits? d.auteur|propri[eé]t[eé] intellectuelle|r[eé]utilisation|reproduction)", text_of(s))
        if m:
            t = text_of(s)
            print("     passage juridique dans la page d'accueil :"); show(t[max(0, m.start() - 200):m.start() + 900], 1100)

    print("--- B3. page du Gouvernement Princier sur la carte des mesures électromagnétiques")
    for u in ["https://www.gouv.mc/fr/action-gouvernementale/poursuivre-la-transition-energetique-et-renaturer-la-ville/reduire-les-emissions-de-gaz-a-effet-de-serre/carte-des-mesures-electromagnetiques",
              "https://www.gouv.mc/en/action-gouvernementale/poursuivre-la-transition-energetique-et-renaturer-la-ville/reduire-les-emissions-de-gaz-a-effet-de-serre/carte-des-mesures-electromagnetiques"]:
        out = f"{T}/mc_gouv.html"
        st = fetch(u, out)
        print("  ->", st, "|", u[:150])
        s2 = read(out)
        if st.startswith("200") and s2:
            print("     titre :", title_of(s2))
            t = text_of(s2)
            for m in list(re.finditer(r"cartoradio", t, re.I))[:2]:
                show(t[max(0, m.start() - 700):m.start() + 500], 1200)
                print("     .")
            print("     liens :", [(h[:120], x[:40]) for h, x in links(s2, u) if re.search(r"cartoradio|data\.gouv|open|carte|ondes|mesure", h + " " + x, re.I)][:12])
            break
guarded(section_b)

# ---------------------------------------------------------------------------------------------------------------
print("##### C. ANDORRE")
def caps(url, label):
    out = f"{T}/caps.xml"
    st = fetch(url, out, 120)
    print("  ->", st, "|", url[:170])
    s = read(out)
    if not st.startswith("200") or "<" not in s[:200]:
        if s:
            show(text_of(s), 200)
        return False
    try:
        root = ET.fromstring(s.encode("utf-8", "replace"))
    except Exception as e:
        print("     (XML illisible :", str(e)[:100], ")"); show(s, 300); return False
    def loc(t):
        return t.rsplit("}", 1)[-1]
    items = []
    for el in root.iter():
        if loc(el.tag) in ("Layer", "FeatureType", "BriefRecord", "SummaryRecord", "Record"):
            name = title = None
            for c in el:
                if loc(c.tag) in ("Name", "identifier") and name is None:
                    name = (c.text or "").strip()
                if loc(c.tag) in ("Title", "title") and title is None:
                    title = (c.text or "").strip()
            if name or title:
                items.append((name, title))
    svc = [(loc(el.tag), (el.text or "").strip()[:200]) for el in root.iter() if loc(el.tag) in ("AccessConstraints", "Fees", "ProviderName", "ContactOrganization") and (el.text or "").strip()]
    print(f"     {label} : racine {loc(root.tag)} | {len(items)} couche(s) ou fiche(s) | service : {svc[:6]}")
    for el in root.iter():
        if loc(el.tag) == "SearchResults":
            print("     SearchResults :", {k: v for k, v in el.attrib.items()})
    hits = [i for i in items if re.search(KW, f"{i[0]} {i[1]}", re.I)]
    print(f"     couches ou fiches évoquant les télécoms ({len(hits)}) :", hits[:30])
    show(" ; ".join(f"{i[0]}={i[1]}" if i[1] and i[1] != i[0] else str(i[0]) for i in items), 3200, 230, "       tout : ")
    return True

def section_c():
    print("--- C1. IDE Andorra")
    base = "https://www.ideandorra.ad/"
    s = page(base, "ad_ide", 700, r".", 30, True)
    found = endpoints(s) if s else []
    sc = scripts(s, base) if s else []
    print("     scripts :", [x[:130] for x in sc[:14]])
    for x in [x for x in sc if "ideandorra" in urllib.parse.urlparse(x).netloc][:6]:
        out = f"{T}/ad_js.js"
        st = fetch(x, out, 90)
        eps = [e for e in endpoints(read(out)) if e not in found]
        found += eps
        print(f"     script {x[:110]} : {st[:40]} | chaînes de type service ou données : {eps[:16]}")
    s2 = page(base + "web-de-descarregues", "ad_desc", 900, r".", 30, True)
    found += [e for e in endpoints(s2) if e not in found] if s2 else []
    bases = []
    for e in found:
        m = re.match(r"((?:https?:)?//[^/]+)?(/[^?]*?(?:geoserver|geonetwork))", e, re.I)
        if m:
            b = (m.group(1) or "https://www.ideandorra.ad")
            if b.startswith("//"):
                b = "https:" + b
            b += m.group(2)
            if b not in bases:
                bases.append(b)
    for b in ["https://www.ideandorra.ad/geoserver", "https://www.ideandorra.ad/geonetwork"]:
        if b not in bases:
            bases.append(b)
    print("     bases de services à tester :", bases[:8])
    for b in bases[:6]:
        if "geoserver" in b.lower():
            caps(b + "/ows?service=WMS&version=1.3.0&request=GetCapabilities", "WMS")
            caps(b + "/ows?service=WFS&version=2.0.0&request=GetCapabilities", "WFS")
        else:
            caps(b + "/srv/eng/csw?service=CSW&version=2.0.2&request=GetRecords&resultType=results&typeNames=csw:Record&elementSetName=summary&maxRecords=400&outputSchema=http://www.opengis.net/cat/csw/2.0.2", "CSW")

    print("--- C2. Govern d'Andorra : données ouvertes, transparence, télécommunications")
    for u in ["https://www.govern.ad/", "https://www.transparencia.ad/", "https://www.govern.ad/dades-obertes"]:
        page(u, "ad_gov", 0, r"dades|obert|open|transpar|telecom|estad[ií]st|cartograf|geoportal|sig\b|mapa", 18, False)
guarded(section_c)

# ---------------------------------------------------------------------------------------------------------------
print("##### D. Régulateurs : où sont les listes nationales de MNC")
def section_d():
    page("https://www.egov.swiss/en/other-numbers-codes/search-mnc-description", "ch_mnc", 900, r"mnc|search|eofcom|numb|code|list", 15, True)
    page("https://www.mimit.gov.it/it/comunicazioni/telefonia/risorse-di-numerazione", "it_mnc", 500, r"mnc|radiomobil|codic|numeraz|\.pdf|\.xls|\.ods|\.csv", 25, False)
    page("https://www.cnmc.es/sectores-que-regulamos/telecomunicaciones/registro-de-numeracion", "es_mnc", 700, r"numeraci|descarg|\.zip|\.csv|\.xls|irm|mnc|registro", 20, False)
    page("https://numeracionyoperadores.cnmc.es/", "es_num", 500, r"numeraci|descarg|\.zip|\.csv|\.xls|irm|mnc|m[oó]vil", 25, True)
guarded(section_d)
PY
echo "FIN"
