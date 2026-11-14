#!/usr/bin/env bash
set -u
. "$(dirname "$0")/_lib.sh"
# Contre-verification independante : texte CC BY-SA 4.0, licence Copernicus (2 copies), registre AWS.
D=$T/cv2; mkdir -p "$D"
f() { # f <fichier> <url> : une requete, a la suite, avec une pause
  local w
  w=$(curl -sS -L --connect-timeout 20 -m 120 -A "$UA" -o "$D/$1" -w "%{http_code} %{size_download}o %{content_type} -> %{url_effective}" "$2" 2>&1 | head -c 300)
  echo "  $1 : $2 : $w"
  sleep 2
}
(apt-get install -y -qq poppler-utils || { apt-get update -qq && apt-get install -y -qq poppler-utils; }) >/dev/null 2>&1
command -v pdftotext >/dev/null && echo "pdftotext present" || echo "pdftotext ABSENT"
echo "## Fichiers (code HTTP, taille, type, adresse finale)"
f cc_txt.txt https://creativecommons.org/licenses/by-sa/4.0/legalcode.txt
f cc_deed.html https://creativecommons.org/licenses/by-sa/4.0/
f cop_ds.pdf https://documentation.dataspace.copernicus.eu/APIs/SentinelHub/Data/DEM/resources/license/License-COPDEM-30.pdf
f cop_eula.pdf https://copernicus-dem-30m.s3.amazonaws.com/Copernicus_DSM_COG_10_N45_00_E006_00_DEM/INFO/eula_F.pdf
f registry.html https://registry.opendata.aws/copernicus-dem/
f dataspace.html https://dataspace.copernicus.eu/explore-data/data-collections/copernicus-contributing-missions/collections-description/COP-DEM
for p in cop_ds cop_eula; do
  pdftotext -enc UTF-8 "$D/$p.pdf" "$D/$p.txt" 2>&1 | head -2
  echo "  $p.pdf : $(wc -c < "$D/$p.pdf") octets ; $(pdfinfo "$D/$p.pdf" 2>/dev/null | grep -E '^(Title|Pages|CreationDate):' | tr -s ' ' | tr '\n' ';')"
done
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
# Partie propre a la sonde cv-2 (CC BY-SA 4.0, licence Copernicus, registre AWS). Suppose commun.py charge.
import difflib
D = sys.argv[1]
ORDRE = ["cc_txt", "cc_deed", "cop_ds", "cop_eula", "registry", "dataspace"]
TXT = {}
TXT["cc_txt"] = flat(lire(os.path.join(D, "cc_txt.txt")))
TXT["cc_deed"] = flat(to_text(lire(os.path.join(D, "cc_deed.html"))))
TXT["cop_ds"] = flat(lire(os.path.join(D, "cop_ds.txt")))
TXT["cop_eula"] = flat(lire(os.path.join(D, "cop_eula.txt")))
RAWREG = lire(os.path.join(D, "registry.html"))
TXT["registry"] = flat(to_text(RAWREG))
TXT["dataspace"] = flat(to_text(lire(os.path.join(D, "dataspace.html"))))
brut = lire(os.path.join(D, "cc_txt.txt"))
print(f"## Tailles de texte : " + ", ".join(f"{k} {len(v)}" for k, v in TXT.items()) + f" ; legalcode.txt brut : {len(brut)} caracteres")
print("  titre de la page cc_deed : " + titre(lire(os.path.join(D, "cc_deed.html"))))

def V(tag, page, phrase, ctx=None, seul=False):
    return verifier(TXT, [page] if seul else ORDRE, tag, page, phrase, ctx)

print("## CC BY-SA 4.0, legalcode.txt")
V("L0", "cc_txt", "Section 3 -- License Conditions.", 0, True)
V("L1", "cc_txt", "If You Share the Licensed Material (including in modified form), You must: a. retain the following if it is supplied by the Licensor with the Licensed Material: i. identification of the creator(s)", 60, True)
V("L2", "cc_txt", "ii. a copyright notice; iii. a notice that refers to this Public License; iv. a notice that refers to the disclaimer of warranties; v. a URI or hyperlink to the Licensed Material to the extent reasonably practicable; b. indicate if You modified the Licensed Material and retain an indication of any previous modifications; and c. indicate the Licensed Material is licensed under this Public License, and include the text of, or the URI or hyperlink to, this Public License.", 30, True)
V("L3", "cc_txt", "ShareAlike. In addition to the conditions in Section 3(a), if You Share Adapted Material You produce, the following conditions also apply. 1. The Adapter's License You apply must be a Creative Commons license with the same License Elements, this version or later, or a BY-SA Compatible License. 2. You must include the text of, or the URI or hyperlink to, the Adapter's License You apply.", 40, True)
V("L4", "cc_txt", "3. You may not offer or impose any additional or different terms or conditions on, or apply any Effective Technological Measures to, Adapted Material that restrict exercise of the rights granted under the Adapter's License You apply.", 30, True)
V("L5a", "cc_txt", "Section 4 -- Sui Generis Database Rights.", 0, True)
V("L5", "cc_txt", "b. if You include all or a substantial portion of the database contents in a database in which You have Sui Generis Database Rights, then the database in which You have Sui Generis Database Rights (but not its individual contents) is Adapted Material, including for purposes of Section 3(b)", 30, True)

print("## Licence Copernicus, copie Copernicus Data Space (cop_ds), puis copie du bucket (cop_eula)")
K = [("K0a", "Licence for Copernicus DEM instance COP-DEM-GLO-30-F Global 30m Full, Free & Open"),
     ("K0b", "Licence for the use of the Copernicus WorldDEM-30"),
     ("K3", "The rights granted under this Licence are worldwide and without limitation in time."),
     ("K4", "The Licensor grants to the User the following non-exclusive rights of use regarding the Copernicus WorldDEM-30: (a) reproduction; (b) distribution; (c) communication to the General Public; (d) adaptation, modification and combination with other data and information."),
     ("K5", "The use rights granted under this licence are free of charge to the User."),
     ("K6a", "When communicating to the General Public or distributing the Copernicus WorldDEM-30, the User shall inform the General Public of the source by using the following notice: © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved."),
     ("K6b", 'Where the Copernicus WorldDEM-30 data have been adapted or modified, the User shall provide the following notice: "produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved".'),
     ("K6c", "The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30"),
     ("K6d", "User shall make sure not to convey the impression to the General Public that the user's activities are officially endorsed by the Provider"),
     ("K6e", "Where the user grants to any Subsequent User the rights to distribute or communicate to the General Public the Copernicus WorldDEM-30, modified or not, he shall ensure that its Subsequent Users are bound by the above obligations.")]
for tag, ph in K:
    V(tag + "-ds", "cop_ds", ph, 25, True)
for tag, ph in K:
    mode = chercher(TXT["cop_eula"], ph)[0]
    print(f"  {tag}-eula : {mode or 'ABSENT'}")
ds_raw = lire(os.path.join(D, "cop_ds.txt"))
print("  articles (cop_ds) : " + " ; ".join(flat(m) for m in re.findall(r"^\f?Article \d+\.[^\n]{0,40}", ds_raw, flags=re.M)))
a, b = TXT["cop_ds"], TXT["cop_eula"]
sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
print(f"  similarite cop_ds / cop_eula : {sm.ratio():.4f}")
n = 0
for op, i1, i2, j1, j2 in sm.get_opcodes():
    if op != "equal" and n < 8:
        print(f"    {op} : ds[{a[max(0, i1 - 30):i2 + 30][:160]!r}] eula[{b[max(0, j1 - 30):j2 + 30][:160]!r}]")
        n += 1

print("## Registre AWS et page Copernicus Data Space")
V("R1", "registry", "GLO-30 Public and GLO-90 are available on a free basis for the general public under the terms and conditions of the Licence found on here.", 80, True)
V("R2", "registry", "AWS CLI Access (No AWS account required)", 120, True)
V("R3", "registry", "aws s3 ls --no-sign-request s3://copernicus-dem-30m/", 60, True)
V("R4", "registry", "arn:aws:s3:::copernicus-dem-30m", 60, True)
contextes(TXT, ORDRE, "eu-central-1", n=1, w=80, pages=["registry"])
V("R6", "registry", "comes from Copernicus DEM 2021 release", 120, True)
V("R7", "registry", "None, except GLO-30 Public can be updated if the public tile list changes.", 60, True)
V("R8", "registry", "The Copernicus DEM is a Digital Surface Model (DSM) which represents the surface of the Earth including buildings, infrastructure and vegetation.", 30, True)
print("  liens du registre vers une licence ou un pdf : " + " ; ".join(sorted({h for h in re.findall(r'href="([^"]+)"', RAWREG) if "licen" in h.lower() or h.lower().endswith(".pdf")}))[:600])
V("P1", "dataspace", "The GLO-30 and GLO-90 datasets are available worldwide with a free license.", 80, True)
contextes(TXT, ORDRE, "EGM2008", n=1, w=120, pages=["dataspace"])
PY
python3 -I "$D/v.py" "$D" 2>&1 | cut -c1-1000
echo "== fin cv-2 =="
