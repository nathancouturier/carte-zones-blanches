#!/usr/bin/env bash
set -u
. "$(dirname "$0")/_lib.sh"
# Contre-verification independante : pages OpenCelliD (licence, mention, telechargements, format, positions).
D=$T/cv1; mkdir -p "$D"
f() { # f <cle> <url> : une requete, a la suite, avec une pause
  local w
  w=$(curl -sS -L --connect-timeout 20 -m 90 -A "$UA" -o "$D/$1.html" -w "%{http_code} %{size_download}o %{content_type} -> %{url_effective}" "$2" 2>&1 | head -c 300)
  echo "  $1 : $2 : $w"
  sleep 2
}
echo "## Pages (code HTTP, taille, type, adresse finale)"
f attribution https://docs.opencellid.org/docs/attribution
f access https://docs.opencellid.org/docs/getting-started/access-and-limits
f coverage https://docs.opencellid.org/docs/getting-started/coverage
f overview https://docs.opencellid.org/docs/downloads/overview
f format https://docs.opencellid.org/docs/downloads/database-format
f daily https://docs.opencellid.org/docs/downloads/daily-changes
f faq https://docs.opencellid.org/docs/help/troubleshooting
f glossary https://docs.opencellid.org/docs/help/glossary
f errors https://docs.opencellid.org/docs/api/errors
f downloads https://opencellid.org/downloads.php
f stats https://opencellid.org/stats.php
f register https://my.opencellid.org/register
cat > "$D/v.py" <<'PY'
# Outils communs aux sondes de contre-verification (cv-*). Aucun acces reseau ici.
import re, html, os, sys

INLINE = "a|span|strong|em|b|i|code|sup|sub|abbr|kbd|mark|small|u|s|q|cite|time|wbr|var|samp|del|ins"
TRANS = str.maketrans({"‘": "'", "’": "'", "“": '"', "”": '"', "–": "-",
                       "—": "-", "‑": "-", "‐": "-", "«": '"', "»": '"'})


def lire(chemin):
    try:
        with open(chemin, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def to_text(raw):
    s = re.sub(r"<(script|style|svg|noscript|template)\b.*?</\1\s*>", " ", raw, flags=re.S | re.I)
    s = re.sub(r"<!--.*?-->", " ", s, flags=re.S)
    s = re.sub(r"<br\s*/?>", "\n", s, flags=re.I)
    s = re.sub(r"</?(?:%s)\b[^>]*>" % INLINE, "", s, flags=re.I)
    s = re.sub(r"<[^>]+>", "\n", s)
    s = html.unescape(s).replace(" ", " ").replace("​", "").replace(" ", " ")
    s = re.sub(r"[ \t\r\f\v]+", " ", s)
    s = re.sub(r" ?\n[\n ]*", "\n", s)
    return s.strip()


def flat(s):
    return re.sub(r"\s+", " ", s).strip()


def titre(raw):
    m = re.search(r"<title[^>]*>(.*?)</title>", raw, flags=re.S | re.I)
    return flat(html.unescape(m.group(1)))[:150] if m else "(pas de titre)"


def nonascii(s):
    return " ".join(sorted({"%s=U+%04X" % (c, ord(c)) for c in s if ord(c) > 127}))


def chercher(hay, phrase):
    p = flat(phrase)
    i = hay.find(p)
    if i >= 0:
        return "EXACT", i, i + len(p)
    h2, p2 = hay.translate(TRANS), p.translate(TRANS)
    i = h2.find(p2)
    if i >= 0:
        return "GUILLEMETS-OU-TIRETS", i, i + len(p2)
    i = h2.lower().find(p2.lower())
    if i >= 0 and len(h2.lower()) == len(h2):
        return "CASSE", i, i + len(p2)
    idx = [k for k, c in enumerate(h2) if c != " "]
    hs = "".join(h2[k] for k in idx).lower()
    ps = p2.replace(" ", "").lower()
    i = hs.find(ps) if ps else -1
    if i >= 0 and len(hs) == len(idx):
        return "ESPACES", idx[i], idx[i + len(ps) - 1] + 1
    return None, -1, -1


def meilleur_debut(hay, phrase):
    mots = flat(phrase).translate(TRANS).split(" ")
    h2 = hay.translate(TRANS).lower()
    for k in range(len(mots) - 1, 0, -1):
        j = h2.find(" ".join(mots[:k]).lower())
        if j >= 0:
            return k, len(mots), j
    return 0, len(mots), -1


def meilleure_fin(hay, phrase):
    mots = flat(phrase).translate(TRANS).split(" ")
    h2 = hay.translate(TRANS).lower()
    for k in range(len(mots) - 1, 0, -1):
        j = h2.find(" ".join(mots[-k:]).lower())
        if j >= 0:
            return k, len(mots), j
    return 0, len(mots), -1


def verifier(textes, ordre, tag, page, phrase, ctx=None):
    """textes : {page: texte plat}. Cherche d'abord dans `page`, puis dans les autres."""
    pages = [page] + [p for p in ordre if p != page]
    for pg in pages:
        hay = textes.get(pg, "")
        mode, s, e = chercher(hay, phrase)
        if mode:
            c = ctx if ctx is not None else (60 if mode == "EXACT" else 150)
            a, b = max(0, s - c), min(len(hay), e + c)
            lieu = pg if pg == page else pg + " (et non " + page + ")"
            print(f"[{tag}] {mode} dans {lieu}")
            seg = hay[a:s] + "<<" + hay[s:e] + ">>" + hay[e:b]
            print("    lu : " + seg[:900])
            na = nonascii(hay[s:e])
            if na:
                print("    caracteres non ASCII du passage : " + na)
            return mode
    hay = textes.get(page, "")
    k, n, j = meilleur_debut(hay, phrase)
    print(f"[{tag}] ABSENT de toutes les pages (attendu dans {page}) ; debut retrouve : {k}/{n} mots")
    if j >= 0 and k >= 3:
        print("    lu a partir du debut retrouve : " + hay[max(0, j - 50): j + 550])
    k2, n2, j2 = meilleure_fin(hay, phrase)
    if j2 >= 0 and k2 > k and k2 >= 3:
        print(f"    fin retrouvee : {k2}/{n2} mots : " + hay[max(0, j2 - 300): j2 + 250])
    return None


def contextes(textes, ordre, mot, n=2, w=150, pages=None):
    vus = 0
    for pg in (pages or ordre):
        hay = textes.get(pg, "")
        low = hay.lower()
        pos, k = 0, 0
        while k < n:
            i = low.find(mot.lower(), pos)
            if i < 0:
                break
            print(f"  {{{mot}}} {pg} : " + hay[max(0, i - w): i + len(mot) + w])
            pos, k, vus = i + len(mot), k + 1, vus + 1
    if not vus:
        print(f"  {{{mot}}} : aucune occurrence")


def tableaux(raw):
    out = []
    for t in re.findall(r"<table\b.*?</table>", raw, flags=re.S | re.I):
        rows = []
        for tr in re.findall(r"<tr\b.*?</tr>", t, flags=re.S | re.I):
            cells = [flat(to_text(c)) for c in re.findall(r"<t[hd]\b[^>]*>(.*?)</t[hd]>", tr, flags=re.S | re.I)]
            rows.append(cells)
        out.append(rows)
    return out
# Partie propre a la sonde cv-1 (pages OpenCelliD). Suppose commun.py deja charge.
D = sys.argv[1]
ORDRE = ["attribution", "access", "coverage", "overview", "format", "daily", "faq", "glossary", "errors",
         "downloads", "stats", "register"]
RAW = {k: lire(os.path.join(D, k + ".html")) for k in ORDRE}
TXT = {k: flat(to_text(v)) for k, v in RAW.items()}
print("## Titres des pages")
for k in ORDRE:
    print(f"  {k} : {titre(RAW[k])} ({len(TXT[k])} caracteres de texte)")

V = lambda tag, page, phrase, ctx=None: verifier(TXT, ORDRE, tag, page, phrase, ctx)

print("## Licence et attribution")
V("A1", "attribution", "OpenCellID data is licensed under CC BY-SA 4.0, including API results, dataset downloads and daily changes.")
V("A2a", "attribution", "Attribution required")
V("A2b", "attribution", "When sharing OpenCellID data under CC BY-SA 4.0, credit OpenCelliD, link to the source and license, and indicate any changes.")
V("A3", "attribution", 'If you modify the data, add a description alongside the credit, such as "Changes: coordinates rounded to two decimal places." Retain supplied notices.')
V("A4a", "attribution", "Where to place the credit")
V("A4b", "attribution", "Make the credit visible where users encounter the data", 250)
V("A4c", "attribution", "Website or map: On the page displaying the data, beside the map or visualization.")
V("A5a", "attribution", "Other license terms")
V("A5b", "attribution", "When sharing adapted material, follow the license's ShareAlike requirements. Retain supplied copyright, license and warranty notices, and do not restrict recipients' licensed rights. See the full license terms, including its database provisions.")
V("A6", "attribution", "Exceptions to the attribution requirement must be granted in writing by Unwired Labs and apply only to the agreed terms.")
V("E1", "attribution", "Cell tower data from OpenCellID, licensed under CC BY-SA 4.0.")
V("E2", "attribution", 'Cell tower data from <a href="https://opencellid.org">OpenCellID</a>, licensed under <a rel="license" href="https://creativecommons.org/licenses/by-sa/4.0/">CC BY-SA 4.0</a>.')
V("E3", "attribution", "Cell tower data from [OpenCellID](https://opencellid.org) · [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)")
liens = []
for h in re.findall(r'href="([^"]+)"', RAW["attribution"]):
    if ("creativecommons" in h or "opencellid.org" in h) and h not in liens:
        liens.append(h)
print("  liens creativecommons / opencellid.org de la page attribution : " + " ; ".join(liens[:15]))
contextes(TXT, ORDRE, "Cell tower data from", n=6, w=220, pages=["attribution"])

print("## Telechargements : formulaire, 18 mois, deux fois par jour")
for m in re.findall(r"<form\b[^>]*>", RAW["downloads"], flags=re.I)[:3]:
    print("  form : " + flat(m)[:300])
for m in re.findall(r"<input\b[^>]*>", RAW["downloads"], flags=re.I)[:6]:
    print("  input : " + re.sub(r'value="[^"]*"', 'value="(masque)"', flat(m))[:300])
V("D2", "downloads", "Enter your API access token to see download links.")
V("D3", "downloads", "Country exports, the worldwide database and daily changes are available with an API access token.")
V("D4", "downloads", "Products or services using data derived from OpenCelliD need to visibly credit OpenCelliD.")
V("D5a", "downloads", "Why do exports only include the last 18 months?")
V("D5b", "downloads", "Cell configurations change over time.", 200)
V("D6", "downloads", "Why does my country have statistics but no download? A country may have historical observations but no data within the export's 18-month window.")
V("Q1", "access", "We generate exports daily by 02:00 GMT. They include towers observed in the last 18 months. You can download each file twice per day from our download page.")
V("Q2", "access", "Each user receives 1,000 API request credits per day. This allowance is per user, not per API key.")
for mot in ["twice", "per day", "18 month", "18-month"]:
    contextes(TXT, ORDRE, mot, n=2, w=120)
for mot in ["getInArea", "km²", "km2", "square kilomet"]:
    contextes(TXT, ORDRE, mot, n=2, w=150)
V("T1", "faq", "Register for an OpenCellID account, then sign in to the dashboard and reveal your key under API Access Tokens.")
V("O1", "overview", "We provide country files, a full dataset and daily change files. Choose the smallest dataset that covers your work.")
contextes(TXT, ORDRE, "cell_towers_diff", n=2, w=150, pages=["overview", "daily"])
V("C1", "daily", "Full exports, country exports and daily change files use the same CC BY-SA 4.0 license.")

print("## Format de la base (14 colonnes)")
V("F0", "format", "cell_towers.csv and cell_towers_diff-*.csv.gz use the columns below, in the order shown.")
V("F2", "format", "Timestamps are in seconds since 1 January 1970, 00:00 UTC.")
ATT = [("radio", "string", "Radio technology, such as GSM, UMTS, LTE or CDMA."),
       ("mcc", "integer", "Mobile Country Code."),
       ("net", "integer", "Mobile Network Code (MNC), or System Identifier (SID) for CDMA."),
       ("area", "integer", "Location Area Code (LAC), Tracking Area Code (TAC) for LTE, or Network Identifier (NID) for CDMA."),
       ("cell", "integer", "Cell ID. For UMTS, the combined RNC and cell identifier; for CDMA, the Base Station Identifier (BID)."),
       ("unit", "integer", "Primary Scrambling Code (PSC) for UMTS or Physical Cell ID (PCI) for LTE. Empty for GSM and CDMA."),
       ("lon", "double", "Estimated cell longitude in degrees"),
       ("lat", "double", "Estimated cell latitude in degrees"),
       ("range", "integer", "Estimated cell range in meters."),
       ("samples", "integer", "Number of measurements assigned to the cell."),
       ("changeable", "integer", "Deprecated. Always 1."),
       ("created", "integer", "When the cell was first seen and added to the database, as a Unix timestamp."),
       ("updated", "integer", "When the cell was last seen and updated, as a Unix timestamp."),
       ("averageSignal", "integer", "Deprecated. Always 0.")]
tabs = tableaux(RAW["format"])
print(f"  {len(tabs)} tableau(x) dans la page format")
cible = [t for t in tabs if any("averageSignal" in c for r in t for c in r)]
if cible:
    t = cible[0]
    for r in t:
        print("  | " + " | ".join(r)[:400])
    noms = [r for r in t if r and any(c in [a[0] for a in ATT] for c in r)]
    lus = []
    for r in t:
        for c in r:
            if c in [a[0] for a in ATT]:
                lus.append(c)
                break
    print("  ordre lu : " + ", ".join(lus) + f" ({len(lus)} colonnes)")
    print("  ordre identique aux notes : " + str(lus == [a[0] for a in ATT]))
    for nom, typ, desc in ATT:
        r = next((r for r in t if nom in r), None)
        if r is None:
            print(f"  ECART {nom} : ligne absente")
            continue
        if typ not in r:
            print(f"  ECART {nom} : type lu {r}")
        if desc not in r:
            print(f"  ECART {nom} : description lue {r}")
    print("  (fin de la comparaison ; aucune ligne ECART = tout identique)")
else:
    print("  pas de tableau avec averageSignal ; texte apres F0 :")
    i = TXT["format"].find("in the order shown")
    print("  " + TXT["format"][i: i + 1500])
contextes(TXT, ORDRE, "header", n=3, w=150, pages=["format", "overview", "faq"])

print("## Nature des positions et des champs")
V("T2", "faq", "Use radio=LTE for 4G or radio=NR for 5G NR")
V("T3", "faq", "In downloads, the MNC is named net")
V("T4", "faq", "changeable is deprecated and always 1; averageSignal is deprecated and always 0. Do not interpret these fields as a surveyed-location flag or a current signal-strength measurement.")
V("T5", "faq", "The coordinates are estimated cell positions calculated from contributed observations. They are not surveyed mast coordinates or a device's live GPS position. Estimates can differ from the physical antenna site, especially where observations are sparse or concentrated along a road.")
V("T6", "faq", "One physical site can serve several cells, sectors and radio technologies. Several rows at nearby or identical coordinates can therefore be valid. Do not count rows as physical towers")
V("T7", "faq", "An eNB ID identifies a base station and is not a substitute for the full cell ID.")

V("G1b", "glossary", "An approximation around the estimated cell position, expressed in meters. It is not a guaranteed signal-coverage radius or an area in square meters.", 80)
V("G2", "glossary", "The number of contributed measurements assigned to a cell.")
V("V1", "coverage", "A download is not a complete inventory of all cells.")
V("V2", "coverage", "They are not a complete inventory of an operator's cells or a map of mobile signal coverage.")
V("V3", "coverage", "A missing record does not mean the cell does not exist or that the area has no mobile signal.")
st = tableaux(RAW["stats"])
if st and st[0]:
    print("  stats.php, en-tete du premier tableau : " + " | ".join(st[0][0])[:200])
PY
python3 -I "$D/v.py" "$D" 2>&1 | cut -c1-1000
echo "== fin cv-1 =="
