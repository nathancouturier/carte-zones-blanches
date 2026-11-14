#!/usr/bin/env bash
# Contre-vérification « Andorre et Monaco », sonde 4 : faits secondaires. Bulletin de l'UIT, registre de la CNMC,
# fichier du MIMIT, fiches de l'IDE Andorra qui parlent de licence, pages de la Secretaria d'Estat andorrane chargée
# des télécommunications, licence d'OpenCelliD. Pages et registres seulement.
set -u
. "$(dirname "$0")/_lib.sh"
UA="sonde-sources-ouvertes/1.0"   # User-Agent générique (pas de nom de projet ni de compte envoyé à des tiers)
export UA
cd "$T" || exit 1
g() { # g <fichier> <url> : un seul essai, délais courts ; affiche code, taille, type, adresse finale
  local f="$1" u="$2" r
  r=$(curl -sS -L --connect-timeout 12 -m 120 -A "$UA" -o "$f" -D "$f.hdr" -w "%{http_code} %{size_download}o %{content_type} final=%{url_effective}" "$u" 2>&1)
  echo "  -> $r | $u" | cut -c1-260
}
(apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq poppler-utils) >/dev/null 2>&1

echo "### A. UIT : dernier bulletin d'exploitation et liste E.212 de référence"
last=""
for n in 1351 1352 1353 1354 1355; do
  r=$(curl -sS -I --connect-timeout 12 -m 40 -A "$UA" -o /dev/null -w "%{http_code} %{content_type}" "https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-OB.$n-2026-OAS-PDF-E.pdf" 2>&1)
  echo "  bulletin $n : $r"
  case "$r" in 200*) last=$n ;; esac
done
if [ -n "$last" ]; then
  g ob.pdf "https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-OB.$last-2026-OAS-PDF-E.pdf"
  pdftotext -layout ob.pdf ob.txt 2>&1 | head -2
  python3 - "$last" <<'PY'
import re, sys
L = open("ob.txt", encoding="utf-8", errors="replace").read().splitlines()
print("  bulletin", sys.argv[1], ":", len(L), "lignes")
for l in L[:40]:
    if re.search(r"No\.\s*\d{4}|\d{1,2}\.[IVX]+\.20\d\d", l):
        print("  en-tête :", re.sub(r"\s+", " ", l.strip())[:150]); break
for i, l in enumerate(L):
    if re.search(r"Mobile Network Codes? \(MNC\)", l):
        print("  ligne %d :" % (i + 1), re.sub(r"\s+", " ", " ".join(x.strip() for x in L[i:i + 4]))[:300])
n = [i for i, l in enumerate(L) if re.search(r"\b(Andorra|Monaco)\b", l)]
print("  lignes citant Andorra ou Monaco :", len(n), [re.sub(r"\s+", " ", L[i].strip())[:110] for i in n[:5]])
PY
fi

echo "### B. Espagne : registre de numérotation de la CNMC"
g bd.zip "https://numeracionyoperadores.cnmc.es/bd-num.zip"
grep -i -E '^(last-modified|content-length):' bd.zip.hdr | tr -d '\r' | head -3
python3 - <<'PY'
import zipfile
try:
    z = zipfile.ZipFile("bd.zip")
except Exception as e:
    print("  archive illisible :", e); raise SystemExit
infos = z.infolist()
print("  fichiers :", len(infos), "|", ", ".join("%s (%04d-%02d-%02d, %d o)" % ((i.filename,) + i.date_time[:3] + (i.file_size,)) for i in infos if i.filename.lower().startswith(("irm", "tetra"))))
raw = z.read([i.filename for i in infos if i.filename.lower() == "irm.txt"][0])
try:
    txt = raw.decode("utf-8"); enc = "utf-8"
except UnicodeDecodeError:
    txt = raw.decode("cp1252"); enc = "cp1252"
lines = [l for l in txt.splitlines() if l.strip()]
print("  irm.txt :", len(lines), "lignes | encodage", enc, "| champs de la 1re ligne :", len(lines[0].split("#")))
for l in lines:
    f = l.split("#")
    if len(f) > 1 and f[0] == "214" and f[1] in ("01", "03", "04", "07", "08", "16", "17", "22"):
        print("    ", l[:120])
PY

echo "### C. Italie : fichier du MIMIT (hôte du ministère, puis copie d'Internet Archive)"
r=$(curl -sS -I --connect-timeout 12 -m 25 -A "$UA" -o /dev/null -w "%{http_code}" "https://www.mimit.gov.it/it/comunicazioni/telefonia/risorse-di-numerazione" 2>&1)
echo "  hôte du ministère : $r" | cut -c1-160
g mimit.xlsx "https://web.archive.org/web/20260917232911id_/https://www.mimit.gov.it/images/stories/digitale/numerazione/File_assegnati_2.xlsx"
python3 - <<'PY'
import zipfile, re, xml.etree.ElementTree as ET
N = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main", "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships", "p": "http://schemas.openxmlformats.org/package/2006/relationships"}
try:
    z = zipfile.ZipFile("mimit.xlsx")
except Exception as e:
    print("  classeur illisible :", e); raise SystemExit
wb = ET.fromstring(z.read("xl/workbook.xml"))
rels = {r.get("Id"): r.get("Target") for r in ET.fromstring(z.read("xl/_rels/workbook.xml.rels")).findall("p:Relationship", N)}
sheets = [(s.get("name"), rels.get(s.get("{%s}id" % N["r"]))) for s in wb.findall("m:sheets/m:sheet", N)]
print("  feuilles :", len(sheets), "| celles qui parlent de MNC :", [n for n, t in sheets if re.search(r"MNC|MCC", n or "", re.I)])
ss = []
if "xl/sharedStrings.xml" in z.namelist():
    for si in ET.fromstring(z.read("xl/sharedStrings.xml")).findall("m:si", N):
        ss.append("".join(t.text or "" for t in si.iter("{%s}t" % N["m"])))
target = [t for n, t in sheets if re.search(r"MCC", n or "", re.I)]
if not target:
    print("  pas de feuille MCC"); raise SystemExit
path = "xl/" + target[0].lstrip("/").replace("xl/", "", 1)
rows = []
for row in ET.fromstring(z.read(path)).iter("{%s}row" % N["m"]):
    cells = []
    for c in row.findall("m:c", N):
        v = c.find("m:v", N)
        if c.get("t") == "s" and v is not None:
            val = ss[int(v.text)]
        elif c.get("t") == "inlineStr":
            val = "".join(t.text or "" for t in c.iter("{%s}t" % N["m"]))
        else:
            val = v.text if v is not None else ""
        cells.append(re.sub(r"\s+", " ", (val or "").strip()))
    if any(cells):
        rows.append([x for x in cells if x])
print("  lignes non vides :", len(rows), "| lignes portant le MCC 222 :", sum(1 for r in rows if "222" in r))
for r in rows[:6]:
    print("     en-tête :", " ; ".join(r)[:170])
for r in rows:
    if re.search(r"^(TIM|VODAFONE|WIND|Iliad|FASTWEB)", r[0], re.I):
        print("    ", " ; ".join(r)[:150])
PY

echo "### D. IDE Andorra : que disent les fiches qui contiennent « llicència » ?"
python3 - <<'PY'
import re, html, os, urllib.request
UA = os.environ.get("UA", "sonde-sources-ouvertes/1.0")
body = ('<?xml version="1.0" encoding="UTF-8"?><csw:GetRecords xmlns:csw="http://www.opengis.net/cat/csw/2.0.2" xmlns:ogc="http://www.opengis.net/ogc" '
        'xmlns:gmd="http://www.isotc211.org/2005/gmd" service="CSW" version="2.0.2" resultType="results" startPosition="1" maxRecords="2" outputSchema="http://www.isotc211.org/2005/gmd">'
        '<csw:Query typeNames="gmd:MD_Metadata"><csw:ElementSetName>full</csw:ElementSetName><csw:Constraint version="1.1.0"><ogc:Filter>'
        '<ogc:PropertyIsLike wildCard="%" singleChar="_" escapeChar="\\"><ogc:PropertyName>AnyText</ogc:PropertyName><ogc:Literal>%llicència%</ogc:Literal></ogc:PropertyIsLike>'
        '</ogc:Filter></csw:Constraint></csw:Query></csw:GetRecords>')
try:
    req = urllib.request.Request("https://www.ideandorra.ad/Cataleg/srv/cat/csw", data=body.encode("utf-8"), headers={"User-Agent": UA, "Content-Type": "application/xml"})
    with urllib.request.urlopen(req, timeout=90) as r:
        x = r.read().decode("utf-8", "replace")
except Exception as e:
    print("  échec :", str(e)[:160]); raise SystemExit
m = re.search(r'numberOfRecordsMatched="(\d+)"', x)
print("  fiches trouvées :", m.group(1) if m else None)
def clean(t):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", t))).strip()
for rec in re.findall(r"<gmd:MD_Metadata\b.*?</gmd:MD_Metadata>", x, re.S)[:2]:
    t = [clean(v) for v in re.findall(r"<gmd:title>(.*?)</gmd:title>", rec, re.S)[:1]]
    ul = sorted({clean(v)[:260] for v in re.findall(r"<gmd:useLimitation>(.*?)</gmd:useLimitation>", rec, re.S)})
    oc = sorted({clean(v)[:260] for v in re.findall(r"<gmd:otherConstraints>(.*?)</gmd:otherConstraints>", rec, re.S)})
    codes = sorted(set(re.findall(r'<gmd:MD_RestrictionCode[^>]*codeListValue="([^"]*)"', rec)))
    ds = re.findall(r"<gmd:dateStamp>(.*?)</gmd:dateStamp>", rec, re.S)
    print("   fiche", t, "| date :", clean(ds[0]) if ds else None, "| codes :", codes)
    print("     useLimitation :", ul)
    print("     otherConstraints :", oc)
    flat = clean(rec)
    for q in [m.start() for m in re.finditer(r"llic[eè]nci", flat, re.I)][:2]:
        print("     contexte : «" + flat[max(0, q - 200): q + 260] + "»")
PY

echo "### E. Andorre : pages de la Secretaria d'Estat de Transformació Digital i Telecomunicacions"
B="https://www.govern.ad/ca/ministeris-i-secretaries-d-estat/secretaria-d-estat-de-transformacio-digital-i-telecomunicacions"
for u in "$B" "$B/andorra-digital" "$B/objectius-estrategics-per-al-2030"; do
  rm -f se.html; g se.html "$u"
  [ -s se.html ] && python3 - <<'PY'
import re, html
s = open("se.html", encoding="utf-8", errors="replace").read()
m = re.search(r"<main\b.*?</main>", s, re.S | re.I)
part = m.group(0) if m else s
b = re.sub(r"<(script|style|svg|noscript|nav|header|footer)\b.*?</\1>", " ", part, flags=re.S | re.I)
b = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", b))).strip()
print("     texte utile :", len(b), "caractères", "(balise main)" if m else "(page entière)")
for w in (r"cobertura", r"dades obertes|open data", r"antenes?\b", r"\b5G\b", r"mapa", r"registre", r"radioel|emissions", r"regulador|autoritat"):
    ms = [x.start() for x in re.finditer(w, b, re.I)]
    if ms:
        print("     motif « %s » : %d | «%s»" % (w, len(ms), b[max(0, ms[0] - 130): ms[0] + 190]))
PY
done
r=$(curl -sS -L --connect-timeout 10 -m 20 -A "$UA" -o /dev/null -w "%{http_code} final=%{url_effective}" "http://opendata.ad/" 2>&1)
echo "  http://opendata.ad/ : $r" | cut -c1-200

echo "### F. OpenCelliD : texte de licence à la source"
for u in "https://docs.opencellid.org/docs/attribution" "https://opencellid.org/"; do
  rm -f ocl.html; g ocl.html "$u"
  [ -s ocl.html ] && python3 - <<'PY'
import re, html
s = open("ocl.html", encoding="utf-8", errors="replace").read()
b = re.sub(r"<(script|style|svg|noscript)\b.*?</\1>", " ", s, flags=re.S | re.I)
b = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", b))).strip()
ms = [m.start() for m in re.finditer(r"CC[ -]BY[ -]SA|Creative Commons", b, re.I)]
print("     mentions de la licence dans le texte :", len(ms), "| dans le code :", len(re.findall(r"CC[ -]BY[ -]SA|Creative Commons|creativecommons\.org", s, re.I)))
for q in ms[:2]:
    print("     «" + b[max(0, q - 140): q + 240] + "»")
PY
done
echo "### fin"
