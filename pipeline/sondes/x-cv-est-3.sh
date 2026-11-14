#!/usr/bin/env bash
set -u
. "$(dirname "$0")/_lib.sh"
# Contre-verification independante : codes MCC et MNC dAndorre et de Monaco dans les listes de lUIT.
D=$T/cv3; mkdir -p "$D"
f() { # f <fichier> <url> : une requete, a la suite, avec une pause
  local w
  w=$(curl -sS -L --connect-timeout 20 -m 120 -A "$UA" -o "$D/$1" -w "%{http_code} %{size_download}o %{content_type} -> %{url_effective}" "$2" 2>&1 | head -c 300)
  echo "  $1 : $2 : $w"
  sleep 2
}
(apt-get install -y -qq poppler-utils || { apt-get update -qq && apt-get install -y -qq poppler-utils; }) >/dev/null 2>&1
command -v pdftotext >/dev/null && echo "pdftotext present" || echo "pdftotext ABSENT"
echo "## Fichiers (code HTTP, taille, type, adresse finale)"
f e212b.pdf https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-E.212B-2023-PDF-E.pdf
f e212a.pdf https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-E.212A-2017-PDF-E.pdf
f ob1351.pdf https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-OB.1351-2026-OAS-PDF-E.pdf
for p in e212b e212a ob1351; do
  pdftotext -layout -enc UTF-8 "$D/$p.pdf" "$D/$p.txt" 2>&1 | head -2
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
# Partie propre a la sonde cv-3 (UIT : MCC et MNC d'Andorre et de Monaco). Suppose commun.py charge.
D = sys.argv[1]
def lignes(nom):
    return lire(os.path.join(D, nom)).replace("\f", "\n").splitlines()
B, A, O = lignes("e212b.txt"), lignes("e212a.txt"), lignes("ob1351.txt")
def c(s):
    s = re.sub(r"\s+", " ", s).strip()
    if re.search(r"@|\bTel\b|\bT[eé]l\s*[.:]|E-mail|Contact|\bFax\b|\+\d{3}\s?\d", s, flags=re.I):
        return "(ligne masquee : coordonnees)"
    return s
print(f"## Lignes de texte : e212b {len(B)}, e212a {len(A)}, ob1351 {len(O)}")
def premiers(L, motif, n=2, apres=0, nom=""):
    k = 0
    for i, l in enumerate(L):
        if re.search(motif, l):
            bloc = " / ".join(c(x) for x in L[i:i + 1 + apres] if c(x))
            print(f"  {nom} l.{i + 1} : {bloc[:420]}")
            k += 1
            if k >= n:
                break
    if not k:
        print(f"  {nom} : aucune ligne pour {motif!r}")
print("## E.212B 2023 (liste des MNC)")
premiers(B, r"POSITION ON|Position on", 2, 0, "e212b")
premiers(B, r"Annex to ITU Operational Bulletin", 1, 1, "e212b")
premiers(B, r"According to Recommendation", 1, 0, "e212b")
premiers(B, r"^\s*Andorra\s*$", 3, 3, "e212b")
premiers(B, r"^\s*Monaco\s*$", 3, 6, "e212b")
entr = [(i, c(l)) for i, l in enumerate(B) if re.search(r"\b21[23]\s+\d{2,3}\s*$", l)]
print(f"  e212b : {len(entr)} ligne(s) se terminant par un code 212 xx ou 213 xx")
for i, l in entr[:10]:
    print(f"    l.{i + 1} : {l[:200]}")
premiers(B, r"Extra-territorial use", 2, 0, "e212b")
premiers(B, r"Monaco\s*-\s*Country B", 5, 2, "e212b")
print("## E.212A 2017 (liste des MCC)")
premiers(A, r"POSITION ON|Position on", 2, 0, "e212a")
premiers(A, r"Annex to ITU Operational Bulletin", 1, 1, "e212a")
premiers(A, r"Andorra", 3, 0, "e212a")
premiers(A, r"Monaco", 3, 0, "e212a")
premiers(A, r"^\s*21[23]\b", 4, 0, "e212a")
print("## Bulletin d'exploitation 1351")
premiers(O, r"No\.\s*1351", 1, 1, "ob1351")
premiers(O, r"\b1280\b", 3, 2, "ob1351")
premiers(O, r"\b1117\b", 3, 2, "ob1351")
premiers(O, r"Andorra", 3, 0, "ob1351")
premiers(O, r"Monaco", 3, 0, "ob1351")
PY
python3 -I "$D/v.py" "$D" 2>&1 | cut -c1-1000
echo "== fin cv-3 =="
