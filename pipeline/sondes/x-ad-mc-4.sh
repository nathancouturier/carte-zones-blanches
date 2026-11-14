#!/usr/bin/env bash
# Andorre et Monaco, sonde 4 : derniers compléments.
#  A. Andorre : catalogue de métadonnées de l'IDE Andorra (CSW, toutes les fiches) et services WMS : y a-t-il une
#     couche de couverture mobile, de télécommunications ou d'antennes ? Conditions d'accès des services.
#  B. Espagne : fichiers du registre de numérotation de la CNMC (bd-num.zip), codes IRM (MNC) ; tableau du rapport annuel.
#  C. Italie : copies archivées des fichiers de numérotation du MIMIT (hôte injoignable depuis le runner).
set -u
. "$(dirname "$0")/_lib.sh"
# User-Agent générique : aucun nom de projet ni de personne dans les requêtes sortantes.
UA="sonde-sources-ouvertes/1.0 (verification ponctuelle de sources publiques)"
export UA T
(apt-get install -y -qq poppler-utils || { apt-get update -qq && apt-get install -y -qq poppler-utils; }) >/dev/null 2>&1
python3 - <<'PY'
import re, os, subprocess, html, json, traceback, urllib.parse, zipfile, io, csv
import xml.etree.ElementTree as ET

T = os.environ["T"]; UA = os.environ["UA"]
KW = r"telecom|telef|antena|antenes|cobertura|radio|m[oò]bil|emissi|comunicaci|electromagn|\b[45]g\b|xarxa|repetidor|fibra"

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

def head(url):
    r = subprocess.run(["curl", "-sS", "-I", "-L", "--connect-timeout", "15", "-m", "40", "-A", UA, "-o", "/dev/null", "-w",
                        "%{http_code} %{content_type} longueur=%header{content-length} modifié=%header{last-modified}", url], capture_output=True, text=True)
    return (r.stdout or r.stderr).strip()[:220]

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

def jget(url, name, maxtime=60):
    out = f"{T}/{name}.json"
    st = fetch(url, out, maxtime)
    print("  ->", st[:150], "|", url[:200])
    try:
        return json.load(open(out, encoding="utf-8", errors="replace"))
    except Exception as e:
        print("     (pas du JSON :", str(e)[:50], ") début :", text_of(read(out))[:160])
        return None

def xlsx_sheets(path):
    """Lecture minimale d'un classeur XLSX (zip + XML) : renvoie [(nom de feuille, [lignes de cellules non vides])]."""
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

# ---------------------------------------------------------------------------------------------------------------
print("##### A. ANDORRE : catalogue de métadonnées et services de l'IDE Andorra")
def section_a():
    CSW = "https://www.ideandorra.ad/Cataleg/srv/cat/csw"
    out = f"{T}/csw_caps.xml"
    st = fetch(CSW + "?service=CSW&version=2.0.2&request=GetCapabilities", out)
    print("  ->", st[:170])
    try:
        root = ET.fromstring(read(out).encode("utf-8", "replace"))
        info = [(loc(e.tag), (e.text or "").strip()[:200]) for e in root.iter() if loc(e.tag) in ("Title", "Abstract", "Fees", "AccessConstraints", "ProviderName", "ServiceTypeVersion") and (e.text or "").strip()]
        print("     identification du service :", info[:8])
        ops = [e.attrib.get("name") for e in root.iter() if loc(e.tag) == "Operation"]
        print("     opérations :", ops)
    except Exception as e:
        print("     (capacités illisibles :", str(e)[:100], ")")
    records, start, matched = [], 1, None
    for page in range(4):
        u = (CSW + "?service=CSW&version=2.0.2&request=GetRecords&resultType=results&typeNames=csw:Record&elementSetName=summary"
             "&outputSchema=http://www.opengis.net/cat/csw/2.0.2&maxRecords=200&startPosition=%d" % start)
        out = f"{T}/csw_{page}.xml"
        st = fetch(u, out, 120)
        print("  ->", st[:120], "| startPosition", start)
        s = read(out)
        try:
            root = ET.fromstring(s.encode("utf-8", "replace"))
        except Exception as e:
            print("     (XML illisible :", str(e)[:100], ") début :", text_of(s)[:300]); break
        sr = next((e for e in root.iter() if loc(e.tag) == "SearchResults"), None)
        if sr is None:
            print("     (pas de SearchResults) début :", text_of(s)[:400]); break
        matched = int(sr.attrib.get("numberOfRecordsMatched", "0")); nxt = int(sr.attrib.get("nextRecord", "0"))
        got = 0
        for rec in sr:
            d = {"id": None, "title": None, "type": None, "subject": [], "abstract": None}
            for c in rec:
                k = loc(c.tag); v = (c.text or "").strip()
                if k == "identifier" and not d["id"]: d["id"] = v
                elif k == "title" and not d["title"]: d["title"] = v
                elif k == "type" and not d["type"]: d["type"] = v
                elif k == "subject" and v: d["subject"].append(v)
                elif k == "abstract" and not d["abstract"]: d["abstract"] = v
            records.append(d); got += 1
        print(f"     fiches correspondantes : {matched} | reçues dans cette page : {got} | suivante : {nxt}")
        if not got or nxt == 0 or nxt > matched:
            break
        start = nxt
    print("     total de fiches lues :", len(records), "sur", matched)
    types = {}
    for d in records:
        types[d["type"]] = types.get(d["type"], 0) + 1
    print("     types :", types)
    subj = {}
    for d in records:
        for x in d["subject"]:
            subj[x] = subj.get(x, 0) + 1
    show("mots-clés (les plus fréquents) : " + " ; ".join(f"{k} ({v})" for k, v in sorted(subj.items(), key=lambda kv: -kv[1])[:70]), 2200, 230, "     ")
    show("titres de toutes les fiches : " + " ¦ ".join(sorted({(d["title"] or "?") for d in records})), 7000, 230, "     ")
    hits = [d for d in records if re.search(KW, " ".join([d["title"] or "", " ".join(d["subject"]), d["abstract"] or ""]), re.I)]
    print(f"     fiches dont le titre, les mots-clés ou le résumé évoquent télécoms, radio, antennes, couverture ou communications : {len(hits)}")
    for d in hits[:14]:
        m = re.search(KW, " ".join([d["title"] or "", " ".join(d["subject"]), d["abstract"] or ""]), re.I)
        print(f"       - [{d['type']}] {d['title']} | id {d['id']} | mot trouvé : « {m.group(0)} » | résumé : {(d['abstract'] or '')[:260]}")
    print("--- services WMS de l'IDE Andorra (adresses en https)")
    for u in ("https://www.ideandorra.ad/Serveis/ows?service=WMS&version=1.3.0&request=GetCapabilities",
              "https://www.ideandorra.ad/Serveis/wms_GR/ows?service=WMS&version=1.1.1&request=GetCapabilities"):
        out = f"{T}/wms.xml"
        st = fetch(u, out, 120)
        print("  ->", st[:170], "|", u)
        s = read(out)
        try:
            root = ET.fromstring(s.encode("utf-8", "replace"))
        except Exception as e:
            print("     (XML illisible :", str(e)[:80], ") début :", text_of(s)[:200]); continue
        svc = [(loc(e.tag), (e.text or "").strip()[:220]) for e in root.iter() if loc(e.tag) in ("AccessConstraints", "Fees", "ContactOrganization") and (e.text or "").strip()]
        layers = []
        for e in root.iter():
            if loc(e.tag) == "Layer":
                n = next(((c.text or "").strip() for c in e if loc(c.tag) == "Name"), None)
                t = next(((c.text or "").strip() for c in e if loc(c.tag) == "Title"), None)
                if n:
                    layers.append((n, t))
        print(f"     racine {loc(root.tag)} | {len(layers)} couche(s) nommée(s) | service : {svc[:5]}")
        print("     couches évoquant les télécoms :", [l for l in layers if re.search(KW, f"{l[0]} {l[1]}", re.I)][:20])
        show("couches : " + " ; ".join(f"{n}={t}" if t and t != n else n for n, t in layers), 3000, 230, "     ")
guarded(section_a)

# ---------------------------------------------------------------------------------------------------------------
print("##### B. ESPAGNE : fichiers du registre de numérotation de la CNMC")
def section_b():
    u = "https://numeracionyoperadores.cnmc.es/bd-num.zip"
    h = head(u)
    print("   en-têtes :", h)
    m = re.search(r"longueur=(\d+)", h)
    if m and int(m.group(1)) > 400_000_000:
        print("     fichier trop gros, non téléchargé"); return
    out = f"{T}/bd-num.zip"
    st = fetch(u, out, 300)
    print("  ->", st[:170])
    try:
        z = zipfile.ZipFile(out)
    except Exception as e:
        print("     (pas une archive zip :", str(e)[:80], ") début :", text_of(read(out))[:200]); return
    infos = z.infolist()
    print("     contenu :", [(i.filename, i.file_size, "%04d-%02d-%02d" % i.date_time[:3]) for i in infos][:40])
    for i in infos:
        name = i.filename
        if i.file_size == 0 or i.file_size > 80_000_000:
            continue
        raw = z.read(name)
        if name.lower().endswith((".csv", ".txt", ".tsv")):
            txt = None
            for enc in ("utf-8-sig", "cp1252", "latin-1"):
                try:
                    txt = raw.decode(enc); break
                except UnicodeDecodeError:
                    continue
            lines = txt.splitlines()
            is_irm = bool(re.search(r"irm|mnc", name, re.I))
            if not is_irm and not any(re.search(r"\bIRM\b", l) for l in lines[:400000]):
                print(f"     {name} : {len(lines)} lignes | en-tête : {lines[0][:200] if lines else ''}")
                continue
            print(f"   >>> {name} : {len(lines)} lignes | en-tête : {lines[0][:300] if lines else ''}")
            sel = lines[1:] if is_irm else [l for l in lines if re.search(r"\bIRM\b", l)]
            print("       lignes IRM :", len(sel))
            show(" ¦ ".join(re.sub(r"\s+", " ", l.strip()) for l in sel[:140]), 9000, 230, "       ")
        elif name.lower().endswith(".xlsx"):
            open(f"{T}/m.xlsx", "wb").write(raw)
            for sh, rows in xlsx_sheets(f"{T}/m.xlsx"):
                is_irm = bool(re.search(r"irm|mnc", f"{name} {sh}", re.I)) or any(re.search(r"\bIRM\b", " ".join(r)) for r in rows[:5])
                print(f"     {name} / feuille « {sh} » : {len(rows)} lignes | début : {' ; '.join(rows[0])[:200] if rows else ''}")
                if is_irm:
                    show(" ¦ ".join(" ; ".join(r) for r in rows[:140]), 9000, 230, "       ")
        else:
            print(f"     {name} : format non lu ({i.file_size} octets), signature {raw[:8]!r}")
    print("--- avis légal de la CNMC (réutilisation)")
    out = f"{T}/es_legal.html"
    print("  ->", fetch("https://www.cnmc.es/aviso-legal", out)[:120])
    t = main_text(read(out))
    if not contexts(t, r"reutilizaci", 1, 200, 900):
        show(t, 500)
    print("--- rapport annuel 2024 de la CNMC : tableau « Estado actual de los MNC »")
    out = f"{T}/es_inf.pdf"
    print("  ->", fetch("https://www.cnmc.es/sites/default/files/6171181.pdf", out, 120)[:110])
    subprocess.run(["pdftotext", "-layout", out, out + ".txt"])
    L = read(out + ".txt").splitlines()
    idx = [i for i, x in enumerate(L) if re.search(r"Tabla 40\b", x)]
    print("     lignes « Tabla 40 » :", [(i, L[i].strip()[:90]) for i in idx])
    if idx:
        i0 = idx[-1]
        k = 0
        for x in L[max(0, i0 - 45):i0 + 12]:
            if x.strip():
                print("       |", re.sub(r"\s{3,}", "  ", x.strip())[:200]); k += 1
            if k >= 50:
                break
guarded(section_b)

# ---------------------------------------------------------------------------------------------------------------
print("##### C. ITALIE : copies archivées des fichiers de numérotation du MIMIT")
def section_c():
    page = "https://www.mimit.gov.it/it/comunicazioni/telefonia/risorse-di-numerazione"
    out = f"{T}/it_page.html"
    print("  ->", fetch("https://web.archive.org/web/20260608082145id_/" + page, out, 120)[:150])
    t = main_text(read(out))
    print("     longueur du texte :", len(t))
    contexts(t, r"File assegnati", 1, 700, 500)
    contexts(t, r"\bMNC\b|Mobile Network|radiomobil", 2, 300, 500)
    found = []
    for q in ("mimit.gov.it/images/stories/digitale/numerazione/*", "mise.gov.it/images/stories/digitale/numerazione/*"):
        r = jget("https://web.archive.org/cdx/search/cdx?url=" + urllib.parse.quote(q, safe="/*") + "&output=json&fl=timestamp,original,statuscode,mimetype,length&collapse=urlkey&limit=300", "cdx", 90)
        if isinstance(r, list) and len(r) > 1:
            rows = r[1:]
            print(f"     captures sous {q} : {len(rows)}")
            for x in sorted(rows, key=lambda x: x[0])[-40:]:
                print("       ", x[0][:8], x[2], x[3][:40], x[4], x[1][-90:])
            found += [x for x in rows if x[2] == "200" and re.search(r"assegnat|mnc", x[1], re.I)]
        else:
            print(f"     aucune capture listée sous {q}")
    if not found:
        print("     aucun fichier « assegnati » archivé : la liste italienne des MNC n'a pas pu être lue")
        return
    best = sorted(found, key=lambda x: x[0])[-1]
    out = f"{T}/it.xlsx"
    st = fetch(f"https://web.archive.org/web/{best[0]}id_/{best[1]}", out, 180)
    print("  ->", st[:200])
    print("     copie archivée du", best[0][:8], "| taille", os.path.getsize(out) if os.path.exists(out) else 0, "| signature", open(out, "rb").read(4) if os.path.exists(out) else None)
    if open(out, "rb").read(2) != b"PK":
        print("     (ce n'est pas un classeur XLSX)"); return
    sheets = xlsx_sheets(out)
    print("     feuilles :", [(n, len(r)) for n, r in sheets])
    for name, rows in sheets:
        headtxt = " / ".join(" ; ".join(r)[:150] for r in rows[:3])
        is_mnc = bool(re.search(r"\bMNC\b|mobile network|radiomobil", str(name) + " " + headtxt, re.I))
        print(f"   feuille « {name} » : {len(rows)} ligne(s) | début : {headtxt[:300]}")
        if is_mnc:
            show(" ¦ ".join(" ; ".join(r) for r in rows[:170]), 7000, 230, "       ")
guarded(section_c)
PY
echo "FIN"
