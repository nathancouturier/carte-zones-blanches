#!/usr/bin/env bash
# Contre-vérification « Frontières et masques de pays », sonde frontieres-v2 (requêtes HTTP seulement).
# Relit à la source les textes de licence (swisstopo, ISTAT, IGN España, OpenStreetMap, Geofabrik), les métadonnées
# des relations OSM utilisées (9407, 36990, 1124039) et les surfaces de référence (Wikidata, projet ouvert CC0).
set -u
. "$(dirname "$0")/_lib.sh"
# Client générique : aucun identifiant personnel dans les requêtes vers des services tiers.
UA="sonde-verification/1.0"
cd "$T"
mkdir -p lic osm wd py

cat > py/phrases.py <<'PY'
# phrases.py <fichier html ou texte> <expression régulière> [nombre max] [longueur max]
# Affiche les phrases du document qui contiennent le motif (texte brut, espaces compactés).
import html, re, sys
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
motif = re.compile(sys.argv[2], re.I)
maxi = int(sys.argv[3]) if len(sys.argv) > 3 else 8
lmax = int(sys.argv[4]) if len(sys.argv) > 4 else 420
if "<" in s[:2000]:
    s = re.sub(r"<(script|style|svg|noscript)\b.*?</\1>", " ", s, flags=re.S | re.I)
    s = re.sub(r"<br\s*/?>|</(p|div|li|tr|h[1-6]|td|th|dd|dt)>", "\n", s, flags=re.I)
    s = html.unescape(re.sub(r"<[^>]+>", " ", s))
s = re.sub(r"[ \t\r\f\v ]+", " ", s)
vus, n = set(), 0
for bloc in s.split("\n"):
    for ph in re.split(r"(?<=[.!?:;])\s+(?=[A-ZÀ-Ý«\"(])", bloc.strip()):
        ph = ph.strip()
        if len(ph) < 8 or not motif.search(ph) or ph in vus:
            continue
        vus.add(ph)
        n += 1
        print("   | " + (ph if len(ph) <= lmax else ph[: lmax - 3] + "..."))
        if n >= maxi:
            sys.exit(0)
if n == 0:
    print("   | (aucune phrase ne contient le motif %s ; %d caracteres de texte)" % (sys.argv[2], len(s)))
PY
phrases() { python3 -I py/phrases.py "$@"; }

echo "##### A. SUISSE : conditions d'utilisation des geodonnees gratuites de swisstopo"
get lic/st-en.html "https://www.swisstopo.admin.ch/en/terms-of-use-free-geodata-and-geoservices"
echo "   titre : $(grep -o -i '<title>[^<]*' lic/st-en.html | head -1 | cut -c8-200)"
phrases lic/st-en.html 'may be used|mandatory|commercial|following source|©swisstopo|© ?swisstopo|Federal Office of Topography swisstopo$|Office fédéral de topographie' 10
echo "   versions linguistiques annoncees par la page :"
grep -o -i '<link[^>]*hreflang[^>]*>' lic/st-en.html | cut -c1-260 | head -6 | sed 's/^/     /'
fr=$(grep -o -i '<link[^>]*hreflang="fr"[^>]*>' lic/st-en.html | grep -o -i 'href="[^"]*"' | head -1 | cut -d'"' -f2)
case "$fr" in /*) fr="https://www.swisstopo.admin.ch$fr" ;; esac
if [ -n "$fr" ]; then
  get lic/st-fr.html "$fr"
  echo "   titre : $(grep -o -i '<title>[^<]*' lic/st-fr.html | head -1 | cut -c8-200)"
  phrases lic/st-fr.html 'peuvent être utilis|obligatoire|commercial|indication de la source|mention de la source|©swisstopo|© ?swisstopo' 8
else
  echo "   (pas de lien hreflang=fr dans la page)"
fi
get lic/st-src.html "https://www.swisstopo.admin.ch/en/source-reference-ogd-swisstopo"
phrases lic/st-src.html 'Acceptable|Not acceptable|central location|imprint' 6
get lic/stac-coll.json "https://data.geo.admin.ch/api/stac/v0.9/collections/ch.swisstopo.swissboundaries3d"
python3 -I - lic/stac-coll.json <<'PY'
import json, sys
j = json.load(open(sys.argv[1]))
print("   STAC : id %s | title %s | license %r | updated %s | summaries %s" % (j.get("id"), j.get("title"), j.get("license"), j.get("updated"), json.dumps(j.get("summaries"))[:120]))
for l in j.get("links", []):
    if l.get("rel") in ("license", "describedby", "about"):
        print("     lien rel=%s : %s (%s)" % (l.get("rel"), l.get("href"), l.get("title")))
print("     providers : %s" % json.dumps(j.get("providers"), ensure_ascii=False)[:300])
print("     description : %s" % (j.get("description") or "")[:260])
PY

echo
echo "##### B. ITALIE : note legali de l'ISTAT et page des contours"
get lic/istat-it.html "https://www.istat.it/note-legali/"
echo "   titre : $(grep -o -i '<title>[^<]*' lic/istat-it.html | head -1 | cut -c8-200)"
phrases lic/istat-it.html 'Creative Commons|licenza|Attribuzione' 8
get lic/istat-en.html "https://www.istat.it/en/legal-notice/"
phrases lic/istat-en.html 'Creative Commons|licen[cs]e' 5
get lic/istat-confini.html "https://www.istat.it/notizia/confini-delle-unita-amministrative-a-fini-statistici-al-1-gennaio-2018-2/"
echo "   titre : $(grep -o -i '<title>[^<]*' lic/istat-confini.html | head -1 | cut -c8-200)"
phrases lic/istat-confini.html 'gennaio 2026|WGS84|generalizzat|licenza|Creative|revisionat' 8
echo "   liens vers les archives 2025 et 2026 lus dans la page :"
grep -o -i 'href="[^"]*Limiti0101202[56][^"]*"' lic/istat-confini.html | sort -u | cut -c1-220 | sed 's/^/     /'

echo
echo "##### C. ESPAGNE : licence de l'IGN (PDF) et collection de l'API"
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq poppler-utils >/dev/null 2>&1
get lic/ign.pdf "https://www.ign.es/resources/licencia/Condiciones_licenciaUso_IGN.pdf"
pdftotext -layout lic/ign.pdf lic/ign-brut.txt 2>&1 | head -2
python3 -I - lic/ign-brut.txt lic/ign.txt <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
print("   PDF : %d page(s), %d caracteres de texte" % (s.count("\f") + (0 if s.endswith("\f") else 1), len(s)))
s = re.sub(r"-\n\s*", "", s)           # césures de fin de ligne
s = re.sub(r"\s*\n\s*", " ", s)        # une seule ligne : le découpage en phrases se fait ensuite
s = re.sub(r"(?<=[.;:])\s+(?=[A-ZÁÉÍÓÚ«])", "\n", s)
open(sys.argv[2], "w", encoding="utf-8").write(s)
PY
phrases lic/ign.txt 'CC-BY|CC BY|Obra derivada|expresión general|libre y gratuito|a pie de mapa|Orden FOM' 12 520
get lic/es-coll.json "https://api-features.ign.es/collections/administrativeunit?f=json"
python3 -I - lic/es-coll.json <<'PY'
import json, sys
j = json.load(open(sys.argv[1]))
print("   collection : id %s | title %s | itemType %s" % (j.get("id"), j.get("title"), j.get("itemType")))
print("     description : %s" % (j.get("description") or "")[:260])
for l in j.get("links", []):
    if l.get("rel") in ("license", "describedby", "about", "enclosure"):
        print("     lien rel=%s : %s (%s)" % (l.get("rel"), l.get("href"), l.get("title")))
print("     crs : %s" % ", ".join(c.rsplit("/", 1)[-1] for c in j.get("crs", []))[:200])
print("     storageCrs : %s | emprise %s" % (j.get("storageCrs"), json.dumps(j.get("extent", {}).get("spatial"))[:160]))
PY
get lic/es-md.xml "https://www.idee.es/csw-inspire-idee/srv/spa/csw?SERVICE=CSW&VERSION=2.0.2&REQUEST=GetRecordById&outputSchema=http://www.isotc211.org/2005/gmd&ElementSetName=full&ID=spaignLLM"
python3 -I - lic/es-md.xml <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
def premier(motif):
    m = re.search(motif, s, re.S)
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", m.group(1))).strip()[:200] if m else None
print("   fiche de metadonnees : %d octets | titre %r | dateStamp %r" % (len(s), premier(r"<gmd:title>(.*?)</gmd:title>"), premier(r"<gmd:dateStamp>(.*?)</gmd:dateStamp>")))
for bloc in re.findall(r"<gmd:(?:otherConstraints|useLimitation)>(.*?)</gmd:(?:otherConstraints|useLimitation)>", s, re.S):
    print("     contrainte : %s" % re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", bloc)).strip()[:220])
PY

echo
echo "##### D. OPENSTREETMAP : licence, extraits Geofabrik"
get lic/osm.html "https://www.openstreetmap.org/copyright"
phrases lic/osm.html 'Open Database License|free to copy|credit OpenStreetMap|same licence|same license' 5
get lic/osmf.html "https://osmfoundation.org/wiki/Licence/Attribution_Guidelines"
phrases lic/osmf.html 'historical forms of attribution|must also make it clear|Produced Work' 5
get lic/osmf-pw.html "https://osmfoundation.org/wiki/Licence/Community_Guidelines/Produced_Work_-_Guideline"
phrases lic/osmf-pw.html 'intended for the extraction|is a Produced Work|not a Produced Work|is a database|Share-Alike|share alike' 8
get lic/gf-mc.html "https://download.geofabrik.de/europe/monaco.html"
phrases lic/gf-mc.html 'ODbL|licen[cs]e|contains all OSM data up to|last modified' 6
get lic/gf-ad.html "https://download.geofabrik.de/europe/andorra.html"
phrases lic/gf-ad.html 'ODbL|licen[cs]e|contains all OSM data up to' 4

echo
echo "##### E. RELATIONS OSM UTILISEES : etiquettes, membres, version (API OSM, sans nom de contributeur)"
for id in 36990 9407 1124039 2220322; do
  get "osm/rel-$id.json" "https://api.openstreetmap.org/api/0.6/relation/$id.json"
done
python3 -I - osm <<'PY'
import collections, json, os, sys
for rid in ("36990", "9407", "1124039", "2220322"):
    p = os.path.join(sys.argv[1], "rel-%s.json" % rid)
    try:
        e = json.load(open(p))["elements"][0]
    except Exception as exc:
        print("   relation %s : illisible (%s) : %s" % (rid, exc, open(p, errors="replace").read()[:120]))
        continue
    roles = collections.Counter("%s/%s" % (m.get("type"), m.get("role") or "(sans role)") for m in e.get("members", []))
    print("   relation %s : version %s | derniere modification %s | visible %s | %d membres : %s" % (
        rid, e.get("version"), e.get("timestamp"), e.get("visible", True), len(e.get("members", [])), dict(roles)))
    tags = e.get("tags", {})
    garde = ("type", "boundary", "admin_level", "name", "name:fr", "ISO3166-1", "land_area", "border_type", "place", "note", "wikidata")
    print("       etiquettes : " + " | ".join("%s=%s" % (k, str(tags[k])[:110]) for k in garde if k in tags))
PY
get osm/taginfo-type.json "https://taginfo.openstreetmap.org/api/4/tag/stats?key=type&value=land_area"
get osm/taginfo-boundary.json "https://taginfo.openstreetmap.org/api/4/tag/stats?key=boundary&value=land_area"
python3 -I - osm/taginfo-type.json osm/taginfo-boundary.json <<'PY'
import json, sys
for p in sys.argv[1:]:
    try:
        j = json.load(open(p))
        print("   taginfo %s : %s" % (p.rsplit("/", 1)[-1], ", ".join("%s %s" % (d.get("type"), d.get("count")) for d in j.get("data", []))))
    except Exception as exc:
        print("   taginfo %s : illisible (%s)" % (p, exc))
PY
get osm/wiki-recherche.json "https://wiki.openstreetmap.org/w/api.php?action=query&list=search&srsearch=%22land_area%22&srlimit=6&format=json"
python3 -I - osm/wiki-recherche.json <<'PY'
import html, json, re, sys
try:
    j = json.load(open(sys.argv[1]))
    for r in j.get("query", {}).get("search", []):
        print("   wiki OSM : %s : %s" % (r.get("title"), html.unescape(re.sub(r"<[^>]+>", "", r.get("snippet", "")))[:200]))
except Exception as exc:
    print("   recherche wiki illisible : %s" % exc)
PY
for titre in "Tag:type%3Dland_area" "Relation:land_area" "Tag:boundary%3Dland_area"; do
  get osm/wiki-page.txt "https://wiki.openstreetmap.org/w/index.php?title=$titre&action=raw"
  head -c 900 osm/wiki-page.txt | tr '\n' ' ' | cut -c1-700; echo
done

echo
echo "##### F. SURFACES DE REFERENCE (Wikidata, propriete P2046 « superficie »)"
get wd/labels.json "https://www.wikidata.org/w/api.php?action=wbgetentities&ids=Q39%7CQ1216%7CQ1222%7CQ1256%7CQ5705%7CQ4040%7CQ4018%7CQ3995%7CQ228%7CQ235&props=labels%7Cdescriptions&languages=fr&format=json"
for q in Q39 Q1216 Q1222 Q1256 Q5705 Q4040 Q4018 Q3995 Q228 Q235; do
  curl -sS -L -m 60 -A "$UA" -o "wd/$q.json" "https://www.wikidata.org/w/api.php?action=wbgetclaims&entity=$q&property=P2046&format=json"
  sleep 1
done
python3 -I - wd <<'PY'
import json, os, sys
d = sys.argv[1]
UNITES = {"Q712226": "km2", "Q35852": "ha", "Q25343": "m2", "Q232291": "mi2"}
try:
    ent = json.load(open(os.path.join(d, "labels.json"))).get("entities", {})
except Exception as exc:
    ent = {}
    print("   libelles illisibles : %s" % exc)
for q in ("Q39", "Q1216", "Q1222", "Q1256", "Q5705", "Q4040", "Q4018", "Q3995", "Q228", "Q235"):
    e = ent.get(q, {})
    lib = e.get("labels", {}).get("fr", {}).get("value")
    desc = e.get("descriptions", {}).get("fr", {}).get("value")
    try:
        claims = json.load(open(os.path.join(d, q + ".json"))).get("claims", {}).get("P2046", [])
    except Exception as exc:
        print("   %s (%s) : illisible (%s)" % (q, lib, exc))
        continue
    vals = []
    for cl in claims:
        v = cl.get("mainsnak", {}).get("datavalue", {}).get("value", {})
        unite = UNITES.get(str(v.get("unit", "")).rsplit("/", 1)[-1], str(v.get("unit", "")).rsplit("/", 1)[-1])
        quali = cl.get("qualifiers", {})
        date = ""
        if "P585" in quali:
            date = " (" + quali["P585"][0].get("datavalue", {}).get("value", {}).get("time", "")[1:11] + ")"
        autres = [k for k in quali if k != "P585"]
        refs = []
        for r in cl.get("references", []):
            for prop, snaks in r.get("snaks", {}).items():
                if prop in ("P854", "P248"):
                    val = snaks[0].get("datavalue", {}).get("value")
                    refs.append(val if isinstance(val, str) else val.get("id"))
        vals.append("%s %s%s [rang %s%s%s]" % (v.get("amount", "").lstrip("+"), unite, date, cl.get("rank"),
                    ", qualificatifs " + ",".join(autres) if autres else "", ", ref " + " ".join(str(x)[:70] for x in refs[:2]) if refs else ""))
    print("   %s = %s (%s)" % (q, lib, (desc or "")[:50]))
    for v in vals[:6]:
        print("        " + v[:240])
PY
echo "FIN"
