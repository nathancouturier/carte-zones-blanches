#!/usr/bin/env bash
# Andorre et Monaco, sonde 3 : compléments.
#  A. UIT (édition 2023) : bloc brut Espagne (noms sur plusieurs lignes), bloc Liechtenstein.
#  B. Italie : fichier officiel « File assegnati » du MIMIT (hôte injoignable depuis le runner : copie archivée).
#  C. Espagne : registre de numérotation de la CNMC (API de l'application, rapport annuel).
#  D. Andorre : visionneuse et services de l'IDE Andorra, avis légal (propriété intellectuelle), téléchargements.
#  E. Monaco : fiches des couches CartoRadio (conditions, champs, date), menus du site, conditions du portail du
#     Gouvernement en français, traces archivées de data.gouv.mc. Aucune entité de carte n'est téléchargée.
set -u
. "$(dirname "$0")/_lib.sh"
# User-Agent générique : aucun nom de projet ni de personne dans les requêtes sortantes.
UA="sonde-sources-ouvertes/1.0 (verification ponctuelle de sources publiques)"
export UA T
(apt-get install -y -qq poppler-utils || { apt-get update -qq && apt-get install -y -qq poppler-utils; }) >/dev/null 2>&1
python3 - <<'PY'
import re, os, subprocess, html, json, traceback, urllib.parse, datetime

T = os.environ["T"]; UA = os.environ["UA"]
KW = r"telecom|telef|t[eé]l[eé]ph|t[eé]l[eé]com|antena|antenes|antenne|cobertura|couverture|radio|m[oò]bil|mobile|emissi|[eé]mission|comunicaci|communication|electromagn|[eé]lectromagn|ondes|\b[45]g\b|xarxa|r[eé]seau"

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
        out.append((href, text_of(m.group(2))[:70]))
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

def jget(url, name, maxtime=60):
    out = f"{T}/{name}.json"
    st = fetch(url, out, maxtime)
    print("  ->", st[:150], "|", url[:190])
    try:
        return json.load(open(out, encoding="utf-8", errors="replace"))
    except Exception as e:
        print("     (pas du JSON :", str(e)[:50], ") début :", text_of(read(out))[:160])
        return None

def ms(x):
    try:
        return datetime.datetime.fromtimestamp(int(x) / 1000, datetime.timezone.utc).strftime("%Y-%m-%d")
    except Exception:
        return str(x)

def wayback(url, out, stamp="2026", maxtime=120):
    """Copie archivée (Internet Archive) la plus proche de la date demandée ; renvoie (état, horodatage)."""
    r = jget("https://archive.org/wayback/available?url=" + urllib.parse.quote(url, safe="") + "&timestamp=" + stamp, "wb")
    snap = (((r or {}).get("archived_snapshots") or {}).get("closest") or {})
    print("     copie archivée la plus proche :", snap.get("timestamp"), "| état", snap.get("status"), "|", snap.get("url"))
    if not snap.get("timestamp"):
        # l'API de disponibilité ne connaît pas toujours les fichiers : essai direct de la capture la plus récente
        st = fetch(f"https://web.archive.org/web/2id_/{url}", out, maxtime)
        print("  ->", st[:230])
        m = re.search(r"/web/(\d{14})", st)
        return (st, m.group(1) if m else "date inconnue") if st.startswith("200") else ("", None)
    st = fetch(f"https://web.archive.org/web/{snap['timestamp']}id_/{url}", out, maxtime)
    print("  ->", st[:230])
    return st, snap["timestamp"]

# ---------------------------------------------------------------------------------------------------------------
print("##### A. UIT, édition 2023 : blocs bruts Espagne et Liechtenstein")
def section_a():
    out = f"{T}/e212.pdf"
    print("  ->", fetch("https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-E.212B-2023-PDF-E.pdf", out, 300)[:110])
    subprocess.run(["pdftotext", "-layout", out, out + ".txt"])
    lines = read(out + ".txt").splitlines()
    for pays, cap in (("Spain", 60), ("Liechtenstein", 14)):
        for i, l in enumerate(lines):
            if re.match(r"^%s\s*$" % pays, l):
                rows = []
                for j in range(i + 1, min(i + cap + 1, len(lines))):
                    x = lines[j]
                    if x[:1].strip() and not re.search(r"Annex to ITU", x):
                        break
                    if not x.strip() or re.search(r"Annex to ITU|Country or|Geographical|Networks", x):
                        continue
                    rows.append(re.sub(r"\s{2,}", "  ", x.strip()))   # lignes brutes, dans l'ordre du document
                print(f"   bloc « {pays} » (ligne {i}) : {len(rows)} ligne(s) brutes, séparées par ¦")
                show(" ¦ ".join(rows), 3600, 230, "     ")
                break
guarded(section_a)

# ---------------------------------------------------------------------------------------------------------------
print("##### B. ITALIE : fichier des ressources de numérotation assignées (MIMIT)")
def xlsx_sheets(path):
    """Lecture minimale d'un classeur XLSX (zip + XML) : renvoie [(nom de feuille, [lignes de cellules non vides])]."""
    import zipfile
    import xml.etree.ElementTree as ET
    def loc(t):
        return t.rsplit("}", 1)[-1]
    z = zipfile.ZipFile(path)
    names = z.namelist()
    shared = []
    if "xl/sharedStrings.xml" in names:
        for si in ET.fromstring(z.read("xl/sharedStrings.xml")):
            shared.append("".join(t.text or "" for t in si.iter() if loc(t.tag) == "t"))
    rels = {}
    if "xl/_rels/workbook.xml.rels" in names:
        for r in ET.fromstring(z.read("xl/_rels/workbook.xml.rels")):
            rels[r.attrib.get("Id")] = r.attrib.get("Target")
    out = []
    wb = ET.fromstring(z.read("xl/workbook.xml"))
    for sh in wb.iter():
        if loc(sh.tag) != "sheet":
            continue
        rid = next((v for k, v in sh.attrib.items() if loc(k) == "id"), None)
        target = rels.get(rid, "")
        target = target.lstrip("/") if target.startswith("/") else "xl/" + target
        rows = []
        if target in names:
            for row in ET.fromstring(z.read(target)).iter():
                if loc(row.tag) != "row":
                    continue
                vals = []
                for c in row:
                    if loc(c.tag) != "c":
                        continue
                    typ = c.attrib.get("t")
                    v = next((x for x in c if loc(x.tag) == "v"), None)
                    if typ == "s" and v is not None and (v.text or "").isdigit():
                        val = shared[int(v.text)] if int(v.text) < len(shared) else ""
                    elif typ == "inlineStr":
                        val = "".join(t.text or "" for t in c.iter() if loc(t.tag) == "t")
                    else:
                        val = (v.text or "") if v is not None else ""
                    val = re.sub(r"\s+", " ", val).strip()
                    if val:
                        vals.append(val)
                if vals:
                    rows.append(vals)
        out.append((sh.attrib.get("name"), rows))
    return out

def section_b():
    u = "https://www.mimit.gov.it/images/stories/digitale/numerazione/File_assegnati_31.03.2026_2.xlsx"
    out = f"{T}/it_assegnati.xlsx"
    st = fetch(u, out, 40)
    print("  ->", st[:230], "|", u)
    stamp = "direct"
    if not st.startswith("200"):
        st, stamp = wayback(u, out, "20260608")
    if not st.startswith("200"):
        print("     fichier non obtenu")
        return
    print("     origine de la copie :", stamp, "| taille", os.path.getsize(out), "octets | signature", open(out, "rb").read(4))
    sheets = xlsx_sheets(out)
    print("     feuilles :", [(n, len(r)) for n, r in sheets])
    for name, rows in sheets:
        head = " / ".join(" ; ".join(r)[:150] for r in rows[:3])
        is_mnc = bool(re.search(r"\bMNC\b|mobile network|radiomobil", str(name) + " " + head, re.I))
        print(f"   feuille « {name} » : {len(rows)} ligne(s) non vides | début : {head[:330]}")
        if is_mnc:
            print("     >>> contenu de la feuille MNC :")
            show(" | ".join(" ; ".join(r) for r in rows[:170]), 6500, 230, "       ")
guarded(section_b)

# ---------------------------------------------------------------------------------------------------------------
print("##### C. ESPAGNE : registre de numérotation de la CNMC")
def section_c():
    base = "https://numeracionyoperadores.cnmc.es"
    out = f"{T}/es_app.js"
    print("  ->", fetch(base + "/build/assets/app-Dc0n3bxb.js", out, 120)[:110])
    js = read(out)
    if not js:
        s = read(f"{T}/es_home.html") if fetch(base + "/", f"{T}/es_home.html").startswith("200") else ""
        m = re.search(r'src="([^"]*build/assets/app-[^"]+\.js)"', s)
        if m:
            print("  ->", fetch(urllib.parse.urljoin(base, m.group(1)), out, 120)[:110])
            js = read(out)
    for rx, b, a in ((r"Tambi[eé]n puede descargarse", 100, 900), (r"get_tipos_numeracion", 350, 500), (r"get_busqueda_numeracion", 500, 600), (r"turnstile", 200, 400)):
        print(f"   contexte « {rx} » ({len(re.findall(rx, js, flags=re.I))} occurrence(s)) :")
        contexts(js, rx, 1, b, a)
    d = jget(base + "/api/numeracion/get_tipos_numeracion", "es_tipos")
    if d is not None:
        show("réponse : " + json.dumps(d, ensure_ascii=False), 1500)
    print("--- rapport annuel de la CNMC sur la numérotation (section IRM ou MNC)")
    for u in ("https://www.cnmc.es/sites/default/files/6171181.pdf", "https://www.cnmc.es/sites/default/files/5318661.pdf"):
        out = f"{T}/es_inf.pdf"
        st = fetch(u, out, 120)
        print("  ->", st[:120], "|", u)
        if not st.startswith("200") or "pdf" not in st:
            continue
        subprocess.run(["pdftotext", "-layout", out, out + ".txt"])
        L = read(out + ".txt").splitlines()
        heads = [x.strip() for x in L if x.strip()][:7]
        print("     début du document :", " / ".join(heads)[:420])
        idx = [i for i, x in enumerate(L) if re.search(r"\bIRM\b|\bMNC\b", x)]
        print("     lignes citant IRM ou MNC :", len(idx), "| premières :", [(i, L[i].strip()[:110]) for i in idx[:6]])
        best, score = None, 0
        for i in idx:
            sc = sum(1 for x in L[i:i + 60] if re.search(r"^\s*(214[\s-]*)?\d{2,3}\s{2,}\S", x))
            if sc > score:
                best, score = i, sc
        if best is not None and score >= 5:
            print(f"     tableau repéré à la ligne {best} ({score} lignes de codes) :")
            k = 0
            for x in L[best:best + 110]:
                if x.strip() and (re.search(r"^\s*(214[\s-]*)?\d{2,3}\s{2,}\S", x) or re.search(r"IRM|MNC|Operador|Asignatario|Estado", x)):
                    print("       |", re.sub(r"\s{3,}", "  ", x.strip())[:190]); k += 1
                if k >= 60:
                    break
            break
guarded(section_c)

# ---------------------------------------------------------------------------------------------------------------
print("##### D. ANDORRE : IDE Andorra (www.cartografia.ad)")
def section_d():
    base = "https://www.cartografia.ad/"
    for path, n in (("visor-de-mapes", 500), ("cartografia-home", 900)):
        out = f"{T}/ad_{path}.html"
        st = fetch(base + path, out)
        print("  ->", st[:150], "|", base + path)
        s = read(out)
        if not s:
            continue
        t = main_text(s)
        t = re.sub(r"^.*?Web de descàrregues IDE Andorra Infraestructura de dades espacials d'Andorra", "", t, count=1)
        print("     titre :", title_of(s)); show(t, n)
        print("     iframes :", [html.unescape(x)[:170] for x in re.findall(r'<iframe\b[^>]*?src\s*=\s*["\']([^"\']+)["\']', s, flags=re.I)][:5])
        keep = [(x[:50], h[:170]) for h, x in links(s, base) if re.search(r"visor|geoportal\.|/Visor|/Cataleg|/Serveis|descarreg|condici|llic[eè]n|producte|preus|tarif", h + " " + x, re.I) and not re.search(r"cartografia\.ad/(geoportal|visor-de-mapes|web-de-descarregues)$", h)]
        print("     liens retenus :", keep[:14])
    print("--- adresses candidates des services (délais courts)")
    for u in ("https://www.cartografia.ad/Cataleg/", "https://www.cartografia.ad/Serveis/wms_GR/ows?service=WMS&version=1.1.1&request=GetCapabilities",
              "https://www.ideandorra.ad/Cataleg/srv/cat/csw?service=CSW&version=2.0.2&request=GetCapabilities", "http://www.ideandorra.ad/Cataleg/",
              "https://www.cartografia.ad/visor/", "https://visor.cartografia.ad/"):
        out = f"{T}/ad_try.bin"
        st = fetch(u, out, 30)
        s = read(out)
        print("  ->", st[:200], "|", u)
        if st.startswith("200") and s:
            print("     titre :", title_of(s), "| début :", text_of(s)[:160])
    print("--- avis légal : rubriques et propriété intellectuelle")
    out = f"{T}/ad_legal.html"
    print("  ->", fetch(base + "avis-legal", out)[:110])
    s = read(out)
    t = main_text(s)
    caps_ = re.findall(r"(?<![A-ZÀ-Ý])((?:[A-ZÀ-ÝÇ·’'´]{2,}[ ,]+){1,9}[A-ZÀ-ÝÇ·’'´]{2,})(?![a-zà-ÿ])", t)
    print("     rubriques en capitales :", [c.strip() for c in caps_ if len(c.strip()) > 8][:25])
    if not contexts(t, r"PROPIETAT INTEL|propietat intel·lectual i industrial|drets de propietat", 2, 100, 1500):
        contexts(t, r"reproducci|distribuci[oó]|comunicaci[oó] p[uú]blica|transformaci", 2, 400, 900)
    contexts(t, r"condicions d.[uú]s|CONDICIONS", 1, 100, 900, 0)
    print("--- web de téléchargement : fin du texte et application")
    out = f"{T}/ad_desc.html"
    print("  ->", fetch(base + "web-de-descarregues", out)[:110])
    s = read(out)
    t = main_text(s)
    m = re.search(r"acceptar les condicions", t)
    show(t[m.start() - 100:m.start() + 1300] if m else t[-1300:], 1400)
    print("     iframes :", [html.unescape(x)[:170] for x in re.findall(r'<iframe\b[^>]*?src\s*=\s*["\']([^"\']+)["\']', s, flags=re.I)][:5])
    print("     liens vers l'application :", [(x[:50], h[:170]) for h, x in links(s, base) if re.search(r"descarreg|download|botiga|cistella", h, re.I) and "cartografia.ad/web-de-descarregues" not in h][:8])
guarded(section_d)

# ---------------------------------------------------------------------------------------------------------------
print("##### E. MONACO")
def section_e():
    P = "https://montecarto.gouv.mc/arcgis"
    print("--- E1. fiches des trois couches CartoRadio et recherche « CartoRadio » dans le portail")
    for item, nom in (("2b3abc5fb038441fb5f5f5c6cfa1986e", "Sites Radioélectriques"), ("37b6de85566844c69acb2199fa2809be", "Mesures Exposition"), ("6fd7eeb7f26a48c6ab2667aaedbf8c2b", "Cadastre électromagnétique")):
        d = jget(f"{P}/sharing/rest/content/items/{item}?f=json", "item")
        if isinstance(d, dict) and not d.get("error"):
            print(f"     {nom} : titre « {d.get('title')} » | type {d.get('type')} | propriétaire {d.get('owner')} | accès {d.get('access')} | créé {ms(d.get('created'))} | modifié {ms(d.get('modified'))}")
            print("       licenseInfo :", repr(text_of(d.get("licenseInfo") or "")[:300]), "| accessInformation :", repr(d.get("accessInformation")), "| snippet :", repr((d.get("snippet") or "")[:200]))
            print("       description :", repr(text_of(d.get("description") or "")[:300]), "| url :", d.get("url"))
        elif isinstance(d, dict):
            print("     erreur :", json.dumps(d.get("error"))[:200])
    r = jget(f"{P}/sharing/rest/search?q=CartoRadio&num=20&f=json", "search")
    if isinstance(r, dict):
        print("     résultats « CartoRadio » :", r.get("total"))
        for it in (r.get("results") or [])[:14]:
            print("       ", (it.get("title") or "")[:60], "|", it.get("type"), "|", it.get("owner"), "|", it.get("access"), "| modifié", ms(it.get("modified")), "| licence :", text_of(it.get("licenseInfo") or "")[:90] or "(vide)")
    print("--- E2. couche des sites : description complète (métadonnées seulement)")
    S = "https://montecarto-srv.gouv.mc/arcgis/rest/services/Hosted/CartoRadio_Sites/FeatureServer"
    d = jget(S + "?f=json", "fs")
    if isinstance(d, dict):
        print("     service : serviceDescription", repr(text_of(d.get("serviceDescription") or "")[:200]), "| copyrightText", repr(d.get("copyrightText")), "| capabilities", d.get("capabilities"),
              "| supportedQueryFormats", d.get("supportedQueryFormats"), "| supportedExportFormats", d.get("supportedExportFormats"), "| currentVersion", d.get("currentVersion"))
        print("     couches :", [(l.get("id"), l.get("name")) for l in d.get("layers") or []], "| tables :", [(l.get("id"), l.get("name")) for l in d.get("tables") or []])
    d = jget(S + "/0?f=json", "fl")
    if isinstance(d, dict):
        fs = d.get("fields") or []
        print("     nombre de champs :", len(fs))
        show("champs (nom=alias:type) : " + ", ".join(f"{f.get('name')}={f.get('alias')}:{(f.get('type') or '').replace('esriFieldType', '')}" for f in fs), 4200, 230, "       ")
        print("     editingInfo :", {k: ms(v) if "Date" in k else v for k, v in (d.get("editingInfo") or {}).items()}, "| étendue :", {k: (round(v, 1) if isinstance(v, (int, float)) else v) for k, v in (d.get("extent") or {}).items() if k != "spatialReference"})
        print("     référence spatiale :", (d.get("extent") or {}).get("spatialReference", {}).get("latestWkid"), "| copyrightText :", repr(d.get("copyrightText")), "| description :", repr(text_of(d.get("description") or "")[:200]))
    print("--- E3. cartoradio.mc : libellés et liens du site (recherche de mentions légales ou d'une page d'aide)")
    out = f"{T}/mc_carto.html"
    print("  ->", fetch("https://cartoradio.mc/", out)[:110])
    su = read(out).replace("\\/", "/")
    su = re.sub(r"\\u([0-9a-fA-F]{4})", lambda m: chr(int(m.group(1), 16)), html.unescape(su))
    titles = []
    for m in re.finditer(r'"(?:title|label|name|text|tooltip)"\s*:\s*"([^"]{3,90})"', su):
        if m.group(1) not in titles:
            titles.append(m.group(1))
    print(f"     libellés ({len(titles)}) :"); show(" ; ".join(titles), 2600, 230, "       ")
    hrefs = []
    for m in re.finditer(r'href=\\?["\']([^"\'\\]+)', su):
        if m.group(1) not in hrefs:
            hrefs.append(m.group(1))
    print("     liens dans les gabarits :", [h[:140] for h in hrefs[:25]])
    for rx in (r"Source\s*:", r"©|copyright", r"DPRN|DDUN|Direction des Plateformes|Direction du D[eé]veloppement"):
        mm = re.search(rx, su, re.I)
        if mm:
            print(f"     contexte « {rx} » :"); show(re.sub(r"<[^>]+>", " ", su[max(0, mm.start() - 300):mm.start() + 500]), 800)
    print("--- E4. conditions d'utilisation du portail du Gouvernement Princier, en français")
    out = f"{T}/mc_legal_en.html"
    u_en = "https://www.gouv.mc/en/legal-notices-and-terms-of-use"
    print("  ->", fetch(u_en, out)[:110])
    g = read(out)
    alt = re.findall(r'<link\b[^>]*rel=["\']alternate["\'][^>]*>', g, flags=re.I)
    print("     balises alternate :", [re.sub(r"\s+", " ", a)[:170] for a in alt[:6]])
    fr = None
    for a in alt:
        if re.search(r'hreflang=["\']fr', a, re.I):
            m = re.search(r'href=["\']([^"\']+)', a)
            if m:
                fr = urllib.parse.urljoin(u_en, html.unescape(m.group(1)))
    if not fr:
        cands = [h for h, x in links(g, u_en) if re.search(r"mentions-legales", h, re.I)]
        fr = cands[0] if cands else "https://www.gouv.mc/fr/mentions-legales-et-conditions-generales-d-utilisation"
    out = f"{T}/mc_legal_fr.html"
    st = fetch(fr, out)
    print("  ->", st[:150], "|", fr)
    t = main_text(read(out)) if st.startswith("200") else main_text(g)
    print("     titre :", title_of(read(out) if st.startswith("200") else g), "| longueur :", len(t))
    show("début : " + t, 900)
    contexts(t, r"6\.1\s|Droits? d.auteur|Copyright", 1, 60, 1300, 0)
    contexts(t, r"Il est strictement interdit|strictly prohibited", 1, 60, 500, 0)
    print("--- E5. data.gouv.mc dans les archives du Web")
    out = f"{T}/mc_wb.html"
    st, stamp = wayback("https://data.gouv.mc/", out, "20260101")
    if st.startswith("200"):
        w = read(out)
        print("     capture du", stamp, "| titre :", title_of(w)); show(main_text(w), 700)
        ls = links(w, "https://data.gouv.mc/")
        print("     liens :", [(h[-80:], x[:40]) for h, x in ls if re.search(r"dataset|jeu|donn|licen|condition|api|explore|th[eè]m|catalog", h + " " + x, re.I)][:20])
    r = jget("https://web.archive.org/cdx/search/cdx?url=data.gouv.mc/*&output=json&fl=timestamp,original,statuscode&collapse=urlkey&limit=400", "cdx", 90)
    if isinstance(r, list) and len(r) > 1:
        rows = r[1:]
        ts = sorted(x[0] for x in rows)
        st = {}
        for x in rows:
            st[x[2]] = st.get(x[2], 0) + 1
        print(f"     captures distinctes (400 au plus) : {len(rows)} | de {ts[0][:8]} à {ts[-1][:8]} | codes HTTP : {st}")
        paths = sorted({urllib.parse.unquote(urllib.parse.urlparse(x[1]).path)[:90] for x in rows if x[2] == "200"})
        show("chemins archivés : " + " ; ".join(paths), 2600, 230, "       ")
        print("     chemins évoquant les télécoms :", [p for p in paths if re.search(KW, p, re.I)][:20])
guarded(section_e)
PY
echo "FIN"
