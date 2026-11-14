#!/usr/bin/env bash
# Andorre et Monaco, sonde 2 : approfondissement.
#  A. UIT (édition 2023) : bloc brut Italie, tableau des usages extraterritoriaux (Monaco, Suisse et Liechtenstein).
#  B. Monaco : cartoradio.mc (configuration, mentions légales, métadonnées des services cartographiques, SANS
#     télécharger d'entités), mentions légales de gouv.mc, traces archivées du portail data.gouv.mc (en maintenance).
#  C. Andorre : www.cartografia.ad (services OGC, catalogue, téléchargements, avis légal), portail de transparence.
#  D. Listes nationales de MNC : MIMIT (Italie), CNMC (Espagne), OFCOM (Suisse).
set -u
. "$(dirname "$0")/_lib.sh"
# User-Agent générique : aucun nom de projet ni de personne dans les requêtes sortantes.
UA="sonde-sources-ouvertes/1.0 (verification ponctuelle de sources publiques)"
export UA T
(apt-get install -y -qq poppler-utils || { apt-get update -qq && apt-get install -y -qq poppler-utils; }) >/dev/null 2>&1
python3 - <<'PY'
import re, os, subprocess, html, json, traceback, urllib.parse, datetime
import xml.etree.ElementTree as ET

T = os.environ["T"]; UA = os.environ["UA"]
KW = r"telecom|telef|t[eé]l[eé]ph|t[eé]l[eé]com|antena|antenes|antenne|cobertura|couverture|radio|m[oò]bil|mobile|emissi|[eé]mission|comunicaci|communication|electromagn|[eé]lectromagn|ondes|\b[45]g\b|xarxa|r[eé]seau"

def fetch(url, out, maxtime=120, extra=()):
    try:
        os.remove(out)   # jamais de relecture d'une réponse précédente
    except OSError:
        pass
    r = subprocess.run(["curl", "-sS", "-L", "-m", str(maxtime), "-A", UA, *extra, "-o", out, "-w",
                        "%{http_code} %{size_download}o %{content_type} | final=%{url_effective}", url],
                       capture_output=True, text=True)
    err = (r.stderr or "").strip().replace("\n", " ")[:160]
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
        out.append((href, text_of(m.group(2))[:70]))
    return out

def guarded(fn):
    try:
        fn()
    except Exception:
        print("    ECHEC :", traceback.format_exc()[-700:])

def contexts(t, rx, n=2, before=250, after=450, must=None):
    k = 0
    last = -10**9
    for m in re.finditer(rx, t, flags=re.I):
        if m.start() - last < after:
            continue
        c = t[max(0, m.start() - before):m.start() + after]
        if must and not re.search(must, c, re.I):
            continue
        show("« " + c + " »", before + after + 10)
        last = m.start(); k += 1
        if k >= n:
            break
    return k

def main_text(s):
    # texte du contenu principal : on coupe l'en-tête et le pied quand des balises <main> ou <article> existent
    m = re.search(r"<(main|article)\b.*?</\1>", s, flags=re.S | re.I)
    return text_of(m.group(0)) if m else text_of(s)

def jget(url, name, maxtime=90):
    out = f"{T}/{name}.json"
    st = fetch(url, out, maxtime)
    print("  ->", st[:200], "|", url[:200])
    try:
        return json.load(open(out, encoding="utf-8", errors="replace"))
    except Exception as e:
        s = read(out)
        print("     (pas du JSON :", str(e)[:60], ") début :", re.sub(r"\s+", " ", text_of(s))[:200])
        return None

def ms(x):
    try:
        return datetime.datetime.fromtimestamp(int(x) / 1000, datetime.timezone.utc).strftime("%Y-%m-%d")
    except Exception:
        return str(x)

# ---------------------------------------------------------------------------------------------------------------
print("##### A. UIT, édition 2023 : bloc Italie, usages extraterritoriaux")
def section_a():
    u = "https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-E.212B-2023-PDF-E.pdf"
    out = f"{T}/e212.pdf"
    print("  ->", fetch(u, out, 300)[:120])
    subprocess.run(["pdftotext", "-layout", out, out + ".txt"])
    lines = read(out + ".txt").splitlines()
    for pays in ("Italy", "Andorra", "San Marino", "Vatican"):
        for i, l in enumerate(lines):
            if re.match(r"^%s\b" % pays, l):
                print(f"   bloc « {pays} » (ligne {i}) :")
                for j in range(i, min(i + 14, len(lines))):
                    if j > i and lines[j][:1].strip():
                        break
                    if lines[j].strip():
                        print("     |", lines[j].rstrip()[:170])
                break
    first = next((i for i, l in enumerate(lines) if re.search(r"Country B", l)), None)
    if first is not None:
        print("   titre et en-tête du tableau des usages extraterritoriaux :")
        seen = 0
        for j in range(max(0, first - 28), first):
            if lines[j].strip() and not re.search(r"\d{3}\s\d{2,3}\s*$", lines[j]):
                print("     |", lines[j].strip()[:230]); seen += 1
        print("   lignes « Country A / Country B » concernant la zone :")
        k = 0
        for i, l in enumerate(lines):
            if re.search(r"(Monaco|Switzerland|Liechtenstein|Italy|Spain|Andorra|San Marino|Vatican)\s*-\s*(Country [AB])?", l) and re.search(r"\b\d{3}\s\d{2,3}\b", l):
                print("     |", re.sub(r"\s{3,}", "   ", l.strip())[:230]); k += 1
            if k >= 26:
                break
guarded(section_a)

# ---------------------------------------------------------------------------------------------------------------
print("##### B. MONACO")
def agol_item(base, item, label):
    d = jget(f"{base}/sharing/rest/content/items/{item}?f=json", "item")
    if not d:
        return None
    if d.get("error"):
        print("     erreur :", json.dumps(d.get("error"))[:300]); return None
    print(f"     {label} : titre « {d.get('title')} » | type {d.get('type')} | propriétaire {d.get('owner')} | accès {d.get('access')} | créé {ms(d.get('created'))} | modifié {ms(d.get('modified'))}")
    print("     url :", d.get("url"), "| tags :", (d.get("tags") or [])[:10])
    print("     accessInformation (crédits) :", repr(d.get("accessInformation")))
    print("     licenseInfo (conditions d'utilisation) :"); show(text_of(d.get("licenseInfo") or "") or "(vide)", 1500)
    print("     snippet :", repr((d.get("snippet") or "")[:300]))
    show("description : " + (text_of(d.get("description") or "") or "(vide)"), 700)
    return d

def layer_meta(url, label):
    d = jget(url + ("&" if "?" in url else "?") + "f=json", "layer")
    if not d:
        return
    if d.get("error"):
        print("     erreur :", json.dumps(d.get("error"))[:300]); return
    print(f"     {label} : nom « {d.get('name') or d.get('mapName') or d.get('serviceDescription', '')[:60]} » | type {d.get('type')} | géométrie {d.get('geometryType')} | capabilities {d.get('capabilities')} | maxRecordCount {d.get('maxRecordCount')}")
    print("     copyrightText :", repr(d.get("copyrightText")), "| description :", repr(text_of(d.get("description") or d.get("serviceDescription") or "")[:300]))
    if d.get("fields"):
        print("     champs :", [(f.get("name"), f.get("alias"), (f.get("type") or "").replace("esriFieldType", "")) for f in d["fields"]][:45])
    if d.get("layers"):
        print("     couches :", [(l.get("id"), l.get("name")) for l in d["layers"]][:40])
    if d.get("tables"):
        print("     tables :", [(l.get("id"), l.get("name")) for l in d["tables"]][:20])
    sr = (d.get("extent") or d.get("fullExtent") or {}).get("spatialReference")
    print("     référence spatiale :", sr)

def section_b():
    print("--- B1. cartoradio.mc : configuration de la page")
    out = f"{T}/mc_carto.html"
    print("  ->", fetch("https://cartoradio.mc/", out)[:160])
    s = read(out)
    su = s.replace("\\/", "/").replace("&quot;", '"').replace("&amp;", "&")
    urls = []
    for u in re.findall(r'https?://[^\s"\'<>\\)]+', su):
        if u not in urls and not re.search(r"\.(png|jpg|jpeg|gif|svg|woff2?|ttf|css|ico)(\?|$)", u, re.I):
            urls.append(u)
    print(f"     URL présentes dans la page ({len(urls)}) :")
    for u in urls[:32]:
        print("       ", u[:210])
    for rx in (r"montecarto", r"licen|mention|l[eé]gal|cgu|condition", r"op[eé]rateur|operator"):
        m = re.search(rx, su, re.I)
        if m:
            print(f"     contexte de « {rx} » dans la page :"); show(su[max(0, m.start() - 350):m.start() + 600], 950)
    forms = re.findall(r"<(?:meta)\b[^>]*(?:name|property)=[\"'](description|author|copyright|generator)[\"'][^>]*content=[\"']([^\"']*)", s, flags=re.I)
    print("     balises meta :", forms[:6])

    print("--- B2. cartoradio.mc : textes juridiques et services cités dans le script de l'application")
    js_urls = [urllib.parse.urljoin("https://cartoradio.mc/", u) for u in re.findall(r'<script\b[^>]*?src\s*=\s*["\']([^"\']+)["\']', s, flags=re.I)]
    js = ""
    for u in js_urls:
        if "app." in u:
            out = f"{T}/mc_app.js"
            print("  ->", fetch(u, out, 180)[:150])
            js = read(out)
    if js:
        svc = []
        for u in re.findall(r'https?:(?://|\\/\\/)[A-Za-z0-9_.\-]+(?:/|\\/)[^\s"\'`<>]*', js):
            u = u.replace("\\/", "/")
            if re.search(r"gouv\.mc|arcgis|cartoradio|monaco", u, re.I) and u not in svc:
                svc.append(u)
        print(f"     URL monégasques ou ArcGIS citées dans le script ({len(svc)}) :", [u[:150] for u in svc[:25]])
        for rx in (r"mentions? l[eé]gales?", r"conditions? (?:g[eé]n[eé]rales? )?d.utilisation", r"r[eé]utilis", r"open ?data|donn[eé]es ouvertes", r"tous droits|droits r[eé]serv", r"propri[eé]t[eé] intellectuelle", r"t[eé]l[eé]charg|export"):
            n = len(re.findall(rx, js, flags=re.I))
            print(f"     motif « {rx} » : {n} occurrence(s)")
            if n:
                contexts(js, rx, 1, 200, 520, r"[a-zéèàù]{4,} [a-zéèàù]{2,} [a-zéèàù]{3,}")

    print("--- B3. éléments ArcGIS cités par cartoradio.mc : métadonnées et conditions (aucune entité téléchargée)")
    items = []
    for m in re.finditer(r"(https?://[A-Za-z0-9_.\-]+(?:/arcgis)?)/sharing/rest/content/items/([0-9a-f]{32})", su):
        if (m.group(1), m.group(2)) not in items:
            items.append((m.group(1), m.group(2)))
    for m in re.finditer(r"(https?://[A-Za-z0-9_.\-]+)/apps/[A-Za-z]+/index\.html\?appid=([0-9a-f]{32})", su):
        if (m.group(1), m.group(2)) not in items:
            items.append((m.group(1), m.group(2)))
    print("     éléments :", items[:6])
    layer_urls = []
    for base, item in items[:4]:
        d = agol_item(base, item, "élément")
        if not d:
            continue
        if d.get("url") and re.search(r"(Feature|Map)Server", d["url"]):
            layer_urls.append(d["url"])
        if d.get("type") in ("Web Map", "Web Mapping Application", "Feature Service", "Map Service"):
            dd = jget(f"{base}/sharing/rest/content/items/{item}/data?f=json", "itemdata")
            if isinstance(dd, dict):
                ols = dd.get("operationalLayers") or []
                print(f"     couches opérationnelles ({len(ols)}) :")
                for l in ols[:30]:
                    print("       ", (l.get("title") or "")[:60], "|", l.get("layerType"), "|", (l.get("url") or "")[:150], "| itemId", l.get("itemId"))
                    if l.get("url"):
                        layer_urls.append(l["url"])
                if not ols:
                    show("données de l'élément : " + json.dumps(dd, ensure_ascii=False), 700)
    for u in re.findall(r'https?://[^\s"\'<>\\)]+?/(?:Feature|Map)Server(?:/\d+)?', su):
        if u not in layer_urls:
            layer_urls.append(u)
    print(f"     services de couches repérés ({len(layer_urls)}) :", [u[:140] for u in layer_urls[:20]])
    done = []
    for u in layer_urls:
        if len(done) >= 6:
            break
        if u in done:
            continue
        layer_meta(u, "service ou couche")
        done.append(u)

    print("--- B4. catalogue public du géoportail du Gouvernement (recherche par mots-clés, métadonnées seulement)")
    for base in ("https://montecarto.gouv.mc/arcgis", "https://gvt-mc.maps.arcgis.com"):
        p = jget(f"{base}/sharing/rest/portals/self?f=json", "portal")
        if isinstance(p, dict) and not p.get("error"):
            print("     portail :", p.get("name"), "| id", p.get("id"), "| accès", p.get("access"), "| description :", text_of(p.get("description") or "")[:200])
            oid = p.get("id")
            q = "(radio OR antenne OR antennes OR mobile OR couverture OR telecom OR ondes OR 4G OR 5G)"
            if "arcgis.com" in base and oid:
                q = f"orgid:{oid} AND " + q
            r = jget(f"{base}/sharing/rest/search?q={urllib.parse.quote(q)}&num=40&f=json", "search")
            if isinstance(r, dict):
                print("     résultats :", r.get("total"))
                for it in (r.get("results") or [])[:25]:
                    print("       ", (it.get("title") or "")[:70], "|", it.get("type"), "|", it.get("owner"), "|", it.get("access"), "| licence :", text_of(it.get("licenseInfo") or "")[:80] or "(vide)", "|", (it.get("url") or "")[:110])

    print("--- B5. mentions légales du portail du Gouvernement Princier")
    out = f"{T}/mc_gouv.html"
    u0 = "https://www.gouv.mc/en/action-gouvernementale/poursuivre-la-transition-energetique-et-renaturer-la-ville/reduire-les-emissions-de-gaz-a-effet-de-serre/carte-des-mesures-electromagnetiques"
    print("  ->", fetch(u0, out)[:60])
    g = read(out)
    cand = [(h, t) for h, t in links(g, u0) if re.search(r"legal|l[eé]gal|mention|terms|cgu", h + " " + t, re.I)]
    print("     liens juridiques :", cand[:5])
    tried = []
    for h, t in cand[:2]:
        for v in (re.sub(r"/en/", "/fr/", h, count=1), h):
            if v in tried:
                continue
            tried.append(v)
            out = f"{T}/mc_legal.html"
            st = fetch(v, out)
            print("  ->", st[:150])
            if st.startswith("200"):
                t2 = main_text(read(out))
                print("     titre :", title_of(read(out)), "| longueur du texte :", len(t2))
                if not contexts(t2, r"reproduction|r[eé]utilis|re-?use|reproduc|propri[eé]t[eé] intellectuelle|intellectual property|droits d.auteur|copyright|licen[cs]e", 4, 300, 700):
                    show(t2, 1200)
                break

    print("--- B6. data.gouv.mc : état actuel et traces dans les archives du Web (Internet Archive)")
    out = f"{T}/mc_data.html"
    print("  ->", fetch("https://data.gouv.mc/", out)[:140])
    show(main_text(read(out)), 400)
    r = jget("https://web.archive.org/cdx/search/cdx?url=data.gouv.mc&matchType=domain&output=json&fl=timestamp,original,statuscode,mimetype&collapse=urlkey&limit=3000", "cdx", 180)
    if isinstance(r, list) and len(r) > 1:
        rows = r[1:]
        ts = sorted(x[0] for x in rows)
        st = {}
        for x in rows:
            st[x[2]] = st.get(x[2], 0) + 1
        print(f"     captures distinctes : {len(rows)} | de {ts[0][:8]} à {ts[-1][:8]} | codes HTTP : {st}")
        ok = [x for x in rows if x[2] == "200"]
        seg = {}
        for x in ok:
            p = urllib.parse.urlparse(x[1]).path.strip("/").split("/")
            key = "/".join(p[:2]) if p and p[0] else "/"
            seg[key] = seg.get(key, 0) + 1
        print("     chemins (2 premiers segments, captures 200) :", sorted(seg.items(), key=lambda kv: -kv[1])[:40])
        ds = sorted({urllib.parse.unquote(urllib.parse.urlparse(x[1]).path) for x in ok if re.search(r"dataset|jeux|donnees|explore/|/d/", x[1], re.I)})
        print(f"     chemins de type jeu de données ({len(ds)}) :"); show(" ; ".join(ds), 3000, 230, "       ")
        hits = sorted({x[1] for x in rows if re.search(KW, urllib.parse.unquote(x[1]), re.I)})
        print(f"     URL archivées évoquant les télécoms ({len(hits)}) :", [h[:140] for h in hits[:20]])
        last_ok = sorted((x for x in ok if urllib.parse.urlparse(x[1]).path in ("", "/")), key=lambda x: x[0])
        if last_ok:
            t0, orig = last_ok[-1][0], last_ok[-1][1]
            out = f"{T}/mc_wb.html"
            print("  ->", fetch(f"https://web.archive.org/web/{t0}id_/{orig}", out, 120)[:170])
            w = read(out)
            print("     capture du", t0[:8], "| titre :", title_of(w))
            show(main_text(w), 900)
            print("     liens :", [(h[-90:], t[:40]) for h, t in links(w, orig) if re.search(r"dataset|jeu|donn|licen|condition|api|explore|th[eè]m", h + " " + t, re.I)][:25])
guarded(section_b)

# ---------------------------------------------------------------------------------------------------------------
print("##### C. ANDORRE")
def caps(url, label):
    out = f"{T}/caps.xml"
    st = fetch(url, out, 120)
    print("  ->", st[:170], "|", url[:170])
    s = read(out)
    if not st.startswith("200") or "<" not in s[:300]:
        if s:
            show(text_of(s), 200)
        return False
    try:
        root = ET.fromstring(s.encode("utf-8", "replace"))
    except Exception as e:
        print("     (XML illisible :", str(e)[:100], ")"); show(text_of(s), 200); return False
    def loc(t):
        return t.rsplit("}", 1)[-1]
    items = []
    for el in root.iter():
        if loc(el.tag) in ("Layer", "FeatureType", "BriefRecord", "SummaryRecord", "Record"):
            name = title = None
            for c in el:
                if loc(c.tag) in ("Name", "identifier", "Identifier") and name is None:
                    name = (c.text or "").strip()
                if loc(c.tag) in ("Title", "title") and title is None:
                    title = (c.text or "").strip()
            if name or title:
                items.append((name, title))
    svc = [(loc(el.tag), (el.text or "").strip()[:260]) for el in root.iter() if loc(el.tag) in ("AccessConstraints", "Fees", "ProviderName", "ContactOrganization") and (el.text or "").strip()]
    print(f"     {label} : racine {loc(root.tag)} | {len(items)} couche(s) ou fiche(s) | service : {svc[:6]}")
    for el in root.iter():
        if loc(el.tag) == "SearchResults":
            print("     SearchResults :", {k: v for k, v in el.attrib.items()})
    hits = [i for i in items if re.search(KW, f"{i[0]} {i[1]}", re.I)]
    print(f"     couches ou fiches évoquant les télécoms ({len(hits)}) :", hits[:30])
    show(" ; ".join(f"{i[0]}={i[1]}" if i[1] and i[1] != i[0] else str(i[0]) for i in items), 2600, 230, "       tout : ")
    return True

def section_c():
    base = "https://www.cartografia.ad/"
    ogc = []
    out = f"{T}/ad_home.html"
    st = fetch(base + "geoportal", out)
    print("  ->", st[:170], "|", base + "geoportal")
    menu = {}
    for h, x in links(read(out), base + "geoportal"):
        for key, rxm in (("serveis-ogc", r"serveis ogc"), ("cataleg-de-metadades", r"cat[aà]leg de metadades"), ("web-de-descarregues", r"web de desc[aà]rregues"),
                         ("aplicacions-tematiques", r"aplicacions tem[aà]tiques"), ("avis-legal", r"av[ií]s legal"), ("visor-de-mapes", r"visor de mapes")):
            if re.search(rxm, x, re.I) and key not in menu:
                menu[key] = h
    print("     adresses réelles du menu :", menu)
    for path, n, rx in (("serveis-ogc", 1800, r"wms|wfs|wmts|csw|ows|geoserver|capabilit|servei|service|arcgis"),
                        ("cataleg-de-metadades", 700, r"cat[aà]leg|metadad|geonetwork|csw|srv"),
                        ("web-de-descarregues", 1200, r"desc[aà]rreg|download|\.zip|shp|dxf|dwg|gpkg|llic|condici"),
                        ("aplicacions-tematiques", 1500, r"."),
                        ("avis-legal", 0, None)):
        out = f"{T}/ad_{path}.html"
        st = fetch(menu.get(path, base + path), out)
        print("  ->", st[:170], "|", menu.get(path, base + path))
        s = read(out)
        if not st.startswith("200") or not s:
            continue
        t = main_text(s)
        # le site répète le même gabarit : on retire le menu commun
        t = re.sub(r"^.*?Web de descàrregues IDE Andorra Infraestructura de dades espacials d'Andorra", "", t, count=1)
        print("     titre :", title_of(s), "| texte utile :", len(t), "caractères")
        if n:
            show(t, n)
        else:
            if not contexts(t, r"reproducci|reutilitz|llic[eè]nci|propietat intel|drets|copyright|[uú]s de (?:la|les) (?:informaci|dades)|autoritzaci", 4, 250, 700):
                show(t, 1500)
        ifr = re.findall(r'<iframe\b[^>]*?src\s*=\s*["\']([^"\']+)["\']', s, flags=re.I)
        if ifr:
            print("     iframes :", [html.unescape(x)[:170] for x in ifr[:6]])
        if rx:
            ls = [(h, x) for h, x in links(s, base) if re.search(rx, h + " " + x, re.I) and not re.search(r"ideandorra\.ad/(geoportal|cartografia-home|ergand|contacta|visor|guia|nomenclator|presentacio|politica|avis)|themeforest|idee\.es|geoportail|inspire\.ec", h)]
            keep = [(h, x) for h, x in ls if "cartografia.ad/" + path not in h]
            print(f"     liens retenus ({len(keep)}) :")
            for h, x in keep[:22]:
                print(f"       {x[:55]} => {h[:175]}")
        for u in re.findall(r'https?://[^\s"\'<>\\)]+', html.unescape(s)):
            if re.search(r"wms|wfs|wmts|ows|csw|geoserver|geonetwork|MapServer|FeatureServer", u, re.I) and u not in ogc:
                ogc.append(u)
    print(f"     adresses de services repérées ({len(ogc)}) :", [u[:170] for u in ogc[:20]])
    tested = []
    for u in ogc:
        b = u.split("?")[0]
        if b in tested or len(tested) >= 6:
            continue
        tested.append(b)
        if re.search(r"csw|geonetwork", b, re.I):
            caps(b + "?service=CSW&version=2.0.2&request=GetRecords&resultType=results&typeNames=csw:Record&elementSetName=summary&maxRecords=400&outputSchema=http://www.opengis.net/cat/csw/2.0.2", "CSW")
        elif re.search(r"wmts", b, re.I):
            caps(b + "?service=WMTS&request=GetCapabilities", "WMTS")
        elif re.search(r"wfs", b, re.I):
            caps(b + "?service=WFS&request=GetCapabilities", "WFS")
        else:
            caps(b + "?service=WMS&request=GetCapabilities", "WMS")

    print("--- C2. portail de transparence du Govern : rubriques de données")
    out = f"{T}/ad_tr.html"
    u = "https://www.transparencia.ad/"
    print("  ->", fetch(u, out)[:120])
    s = read(out)
    ls = links(s, u)
    print("     rubriques (toutes) :", [x for h, x in ls if "transparencia.ad/web/guest" in h and x][:60])
    print("     liens évoquant données ouvertes, réutilisation, statistiques ou télécoms :", [(x, h[:120]) for h, x in ls if re.search(r"dades obertes|open ?data|reutilitz|estad[ií]st|telecom|cartograf|geoportal", h + " " + x, re.I)][:12])
guarded(section_c)

# ---------------------------------------------------------------------------------------------------------------
print("##### D. Listes nationales de MNC")
def pdf_lines(path):
    subprocess.run(["pdftotext", "-layout", path, path + ".txt"])
    info = subprocess.run(["pdfinfo", path], capture_output=True, text=True).stdout
    print("     ", " | ".join(l.strip() for l in info.splitlines() if re.search(r"^(Title|Pages|CreationDate|ModDate)", l))[:300])
    return read(path + ".txt").splitlines()

def section_d():
    print("--- D1. Italie : MIMIT, risorse di numerazione")
    u = "https://www.mimit.gov.it/it/comunicazioni/telefonia/risorse-di-numerazione"
    out = f"{T}/it_num.html"
    st = fetch(u, out, 60)
    print("  ->", st, "|", u)
    via = ""
    if not st.startswith("200"):
        st0 = fetch("https://www.mimit.gov.it/", f"{T}/it_home.html", 40)
        print("  ->", st0, "| https://www.mimit.gov.it/")
        r = jget("https://archive.org/wayback/available?url=" + urllib.parse.quote(u, safe="") + "&timestamp=20261101", "wb")
        snap = (((r or {}).get("archived_snapshots") or {}).get("closest") or {})
        print("     copie archivée la plus proche :", snap.get("timestamp"), snap.get("url"), snap.get("status"))
        if snap.get("timestamp"):
            via = f"https://web.archive.org/web/{snap['timestamp']}id_/"
            st = fetch(via + u, out, 120)
            print("  ->", st[:200])
    s = read(out)
    if st.startswith("200") and s:
        print("     titre :", title_of(s))
        t = main_text(s)
        contexts(t, r"\bMNC\b|Mobile Network Code|radiomobil", 3, 300, 600)
        ls = [(h, x) for h, x in links(s, u) if re.search(r"mnc|radiomobil|mobile.network|codici", h + " " + x, re.I)]
        allp = [(h, x) for h, x in links(s, u) if re.search(r"\.(pdf|xlsx?|ods|csv)(\?|$)", h, re.I)]
        print(f"     documents liés ({len(allp)}) :", [(x[:50], h[-110:]) for h, x in allp[:25]])
        print(f"     liens MNC ({len(ls)}) :", [(x[:60], h[:170]) for h, x in ls[:8]])
        for h, x in ls[:2]:
            if not re.search(r"\.pdf(\?|$)", h, re.I):
                continue
            out = f"{T}/it_mnc.pdf"
            st2 = fetch(h, out, 120)
            print("  ->", st2[:200])
            if not st2.startswith("200") and via:
                st2 = fetch(via + h, out, 120)
                print("  ->", st2[:200])
            if st2.startswith("200"):
                L = pdf_lines(out)
                k = 0
                for l in L:
                    if l.strip():
                        print("     |", re.sub(r"\s{3,}", "   ", l.strip())[:200]); k += 1
                    if k >= 75:
                        print("     [... tronqué]"); break

    print("--- D2. Espagne : CNMC, application du registre de numérotation")
    u = "https://numeracionyoperadores.cnmc.es/"
    out = f"{T}/es_num.html"
    print("  ->", fetch(u, out)[:150])
    s = read(out)
    sc = [urllib.parse.urljoin(u, x) for x in re.findall(r'<script\b[^>]*?src\s*=\s*["\']([^"\']+)["\']', s, flags=re.I)]
    print("     scripts :", [x[:120] for x in sc[:8]])
    api = []
    for x in sc[:5]:
        out = f"{T}/es_js.js"
        st = fetch(x, out, 120)
        js = read(out)
        found = []
        for m in re.findall(r'["\'`]([^"\'`\s]{0,160}(?:api/|/descarga|download|export|/irm|mnc|numeracion/)[^"\'`\s]{0,120})["\'`]', js, flags=re.I):
            if m not in found and m not in api:
                found.append(m)
        api += found
        print(f"     script {x[-70:]} : {st[:30]} | chaînes : {found[:40]}")
        for rx in (r"IRM", r"red m[oó]vil", r"descarga"):
            ms_ = re.search(rx, js)
            if ms_:
                print(f"     contexte « {rx} » :", re.sub(r"\s+", " ", js[max(0, ms_.start() - 300):ms_.start() + 500])[:800])

    print("--- D3. Suisse : OFCOM, recherche de MNC")
    u = "https://www.egov.swiss/en/other-numbers-codes/search-mnc-form"
    out = f"{T}/ch_form.html"
    print("  ->", fetch(u, out)[:170])
    s = read(out)
    print("     titre :", title_of(s)); show(main_text(s), 600)
    print("     formulaires :", re.findall(r"<form\b[^>]*>", s, flags=re.I)[:4])
    print("     champs :", re.findall(r"<(?:input|select|button)\b[^>]*?name=[\"']([^\"']+)[\"']", s, flags=re.I)[:25])
    eps = []
    for m in re.findall(r'["\'`]([^"\'`\s]{0,120}(?:api/|search|mnc)[^"\'`\s]{0,120})["\'`]', s, flags=re.I):
        if m not in eps:
            eps.append(m)
    print("     chaînes :", eps[:30])
guarded(section_d)
PY
echo "FIN"
