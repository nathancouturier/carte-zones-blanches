#!/usr/bin/env bash
set -u
. "$(dirname "$0")/_lib.sh"
# Contre-vérification indépendante des conditions d'usage (fonds de carte, recherche de lieux).
# Requêtes une par une, User-Agent générique de _lib.sh, sortie filtrée.
D="$T/cv-dl"; P="$T/cv-py"; rm -rf "$D" "$P"; mkdir -p "$D" "$P"
cat > "$P/cv.py" <<'PYEOF'
#!/usr/bin/env python3
# cv.py : extraction compacte pour les sondes de contre-vérification (conditions d'usage).
# Sous-commandes : cherche, tables, liens, nuxt, brut, service, couche, xmlv, dgf, titre, debut.
# « cherche FICHIER MODE » lit sur l'entrée standard une ligne par élément :
#   phrase           -> vérifie la phrase mot pour mot (EXACT, NORMALISE, MOTS-SEULS ou ABSENT)
#   ?ancre           -> montre le contexte (3 occurrences au plus)
#   re:motif         -> expression régulière, contexte (3 occurrences au plus)
#   # commentaire    -> recopié tel quel
import sys, re, html, json, difflib, unicodedata

INLINE = set('a span strong b em i u abbr code sup sub small mark q cite time bdi bdo font s del ins kbd var label nobr wbr'.split())
TR = str.maketrans({'’': "'", '‘': "'", 'ʼ': "'", '′': "'", '´': "'",
                    '“': '"', '”': '"', '„': '"', '″': '"',
                    '–': '-', '—': '-', '‐': '-', '‑': '-', '‒': '-', '−': '-'})
LIG = {'ﬀ': 'ff', 'ﬁ': 'fi', 'ﬂ': 'fl', 'ﬃ': 'ffi', 'ﬄ': 'ffl'}
WS = re.compile(r'\s+')


def lire(f):
    b = open(f, 'rb').read()
    try:
        return b.decode('utf-8')
    except UnicodeDecodeError:
        return b.decode('cp1252', errors='replace')


def collapse(s):
    return WS.sub(' ', s).strip()


def html2txt(s):
    s = re.sub(r'<!--.*?-->', ' ', s, flags=re.S)
    s = re.sub(r'<(script|style|noscript|svg)\b.*?</\1\s*>', ' ', s, flags=re.S | re.I)
    s = re.sub(r'</?([A-Za-z][A-Za-z0-9-]*)\b[^>]*>',
               lambda m: '' if m.group(1).lower() in INLINE else ' ', s)
    return html.unescape(s)


def prep(s, mode):
    if mode == 'html':
        s = html2txt(s)
    elif mode == 'text':
        for k, v in LIG.items():
            s = s.replace(k, v)
    s = unicodedata.normalize('NFC', s)
    s = re.sub('[​‌‍﻿­]', '', s)
    return collapse(s)


def loose(s):
    out, idx = [], []
    for i, c in enumerate(s):
        if c.isalnum():
            lc = c.lower()
            out.append(lc if len(lc) == 1 else c)
            idx.append(i)
    return ''.join(out), idx


def occ(h, n):
    c, i = 0, h.find(n)
    while i != -1:
        c += 1
        i = h.find(n, i + 1)
    return c


def court(s, n=700):
    return s if len(s) <= n else s[:n // 2 + 30] + ' [...] ' + s[-(n // 2 - 50):]


class Page:
    def __init__(self, f, mode):
        self.O = prep(lire(f), mode)
        self.N = self.O.translate(TR)
        self.L, self.M = loose(self.O)


def verifie(pg, p):
    O, N, L, M = pg.O, pg.N, pg.L, pg.M
    pc = prep(p, 'raw')
    pn = pc.translate(TR)
    pl, _ = loose(pc)
    lab = pc if len(pc) <= 100 else pc[:70] + ' [...] ' + pc[-25:]
    t, k, i, j = 'ABSENT', 0, -1, -1
    if pc in O:
        t, k, i = 'EXACT', occ(O, pc), O.find(pc)
        j = i + len(pc)
    elif pn in N:
        t, k, i = 'NORMALISE', occ(N, pn), N.find(pn)
        j = i + len(pn)
    elif pl and pl in L:
        a = L.find(pl)
        t, k, i, j = 'MOTS-SEULS', occ(L, pl), M[a], M[a + len(pl) - 1] + 1
    print(f'  [{t} x{k}] {lab}')
    if t == 'ABSENT':
        diag(pg, pc)
        return
    if t == 'EXACT':
        print('     page : ...' + O[max(0, i - 120):i] + '⟦' + court(O[i:j], 240) + '⟧' + O[j:j + 120] + '...')
        return
    c = 120 if t == 'NORMALISE' else 200
    print('     page : ...' + O[max(0, i - c):i] + '⟦' + court(O[i:j]) + '⟧' + O[j:j + c] + '...')
    if t == 'MOTS-SEULS':
        src, dst = pn, O[i:j].translate(TR)
    else:
        src, dst = pc, O[i:j]
    ops = [o for o in difflib.SequenceMatcher(None, src, dst, autojunk=False).get_opcodes() if o[0] != 'equal']
    for tag, a1, a2, b1, b2 in ops[:8]:
        print(f'     ecart ({tag}) notes «{src[max(0, a1 - 12):a2 + 12]}» / page «{dst[max(0, b1 - 12):b2 + 12]}»')


def diag(pg, pc):
    O, L, M = pg.O, pg.L, pg.M
    w = pc.split(' ')

    def lp(n):
        q, _ = loose(' '.join(w[:n]))
        return not q or q in L

    def ls(n):
        q, _ = loose(' '.join(w[len(w) - n:]))
        return not q or q in L

    def bs(f):
        lo, hi = 0, len(w)
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if f(mid):
                lo = mid
            else:
                hi = mid - 1
        return lo

    a, b = bs(lp), bs(ls)
    print(f'     prefixe present : {a}/{len(w)} mots ; suffixe present : {b}/{len(w)} mots')
    if a >= 3:
        q, _ = loose(' '.join(w[:a]))
        if q:
            x = L.find(q)
            e = M[x + len(q) - 1] + 1
            print('     page, apres le prefixe : ...' + O[max(0, e - 120):e] + '‖' + O[e:e + 480] + '...')
    if 3 <= b < len(w):
        q, _ = loose(' '.join(w[len(w) - b:]))
        if q:
            x = L.find(q)
            s0 = M[x]
            print('     page, avant le suffixe : ...' + O[max(0, s0 - 480):s0] + '‖' + O[s0:s0 + 120] + '...')


def ancre(pg, a, n=3):
    an = prep(a, 'raw').translate(TR)
    ms = list(re.finditer(re.escape(an), pg.N, flags=re.I))
    print(f'  [CONTEXTE x{len(ms)}] {a}')
    for m in ms[:n]:
        i = m.start()
        print('     ...' + pg.O[max(0, i - 150):i] + '‖' + pg.O[i:i + 450] + '...')


def rgx(pg, r, n=3):
    try:
        ms = list(re.finditer(r, pg.N, flags=re.I))
    except re.error as e:
        print('  [REGEX invalide]', r, e)
        return
    print(f'  [REGEX x{len(ms)}] {r}')
    for m in ms[:n]:
        i, j = m.start(), m.end()
        print('     ...' + pg.O[max(0, i - 150):i] + '⟦' + pg.O[i:j] + '⟧' + pg.O[j:j + 300] + '...')


def cherche(f, mode):
    pg = Page(f, mode)
    print(f'   [texte : {len(pg.O)} caracteres]')
    for ln in sys.stdin.read().splitlines():
        s = ln.strip()
        if not s:
            continue
        if s.startswith('#'):
            print('  ' + s)
        elif s.startswith('?'):
            ancre(pg, s[1:].strip())
        elif s.startswith('re:'):
            rgx(pg, s[3:].strip())
        else:
            verifie(pg, s)


def cellule(c):
    c = re.sub(r'<br\s*/?>|</?(p|div|li|ul|ol)\b[^>]*>', ' ', c, flags=re.I)
    return collapse(html.unescape(re.sub(r'<[^>]+>', '', c)))


def tables(f, mot, maxl=45):
    s = lire(f)
    vu = 0
    for k, m in enumerate(re.finditer(r'<table\b.*?</table\s*>', s, flags=re.S | re.I)):
        t = m.group(0)
        if mot.lower() not in collapse(html.unescape(re.sub(r'<[^>]+>', ' ', t))).lower():
            continue
        vu += 1
        rows = re.findall(r'<tr\b.*?</tr\s*>', t, flags=re.S | re.I)
        print(f'  [TABLEAU n°{k}, {len(rows)} lignes] contient « {mot} »')
        for r in rows[:maxl]:
            cells = [cellule(c) for c in re.findall(r'<t[hd]\b[^>]*>(.*?)</t[hd]\s*>', r, flags=re.S | re.I)]
            print('     | ' + ' | '.join(cells)[:240])
        if vu >= 3:
            break
    if not vu:
        print(f'  [TABLEAU] aucun tableau HTML contenant « {mot} »')


def liens(f, motif, n=8):
    s = lire(f)
    ms = [(h, collapse(html.unescape(re.sub(r'<[^>]+>', '', t))))
          for h, t in re.findall(r'<a\b[^>]*?href="([^"]*)"[^>]*>(.*?)</a\s*>', s, flags=re.S | re.I)]
    ms = [(h, t) for h, t in ms if re.search(motif, h + ' ' + t, flags=re.I)]
    print(f'  [LIENS x{len(ms)}] {motif}')
    for h, t in ms[:n]:
        print(f'     {t[:100]!r} -> {html.unescape(h)[:160]}')


def nuxt(f, motif, n=4, av=6, ap=10):
    s = lire(f)
    m = re.search(r'<script\b[^>]*id="__NUXT_DATA__"[^>]*>(.*?)</script>', s, flags=re.S)
    if not m:
        print('  [NUXT] bloc __NUXT_DATA__ absent')
        return
    arr = json.loads(m.group(1))
    strs = [(i, x) for i, x in enumerate(arr) if isinstance(x, str)]
    hits = [k for k, (i, x) in enumerate(strs) if re.search(motif, x, flags=re.I)]
    print(f'  [NUXT] {len(arr)} elements, {len(strs)} chaines ; {len(hits)} chaine(s) pour {motif}')
    for k in hits[:n]:
        i, x = strs[k]
        if len(x) > 300:
            t = collapse(html.unescape(re.sub(r'<[^>]+>', ' | ', x)))
            mm = re.search(motif, t, flags=re.I)
            a = mm.start() if mm else 0
            print(f'     #{i} (longue) ...' + t[max(0, a - 200):a + 400] + '...')
        else:
            vois = [strs[q][1] for q in range(max(0, k - av), min(len(strs), k + ap + 1))]
            print(f'     #{i} : ' + ' ‖ '.join(collapse(v)[:120] for v in vois))


def brut(f, motif, n=3, larg=600, unesc=1):
    s = lire(f)
    if int(unesc):
        s = re.sub(r'\\u([0-9a-fA-F]{4})', lambda m: chr(int(m.group(1), 16)), s)
        s = s.replace('\\"', '"').replace('\\/', '/').replace('\\n', ' ')
        s = html.unescape(s)
    ms = list(re.finditer(motif, s, flags=re.I))
    print(f'  [BRUT x{len(ms)}] {motif}')
    larg = int(larg)
    for m in ms[:int(n)]:
        a = m.start()
        print('     ...' + collapse(s[max(0, a - larg // 4):a + 3 * larg // 4]) + '...')


def _xml(f):
    import xml.etree.ElementTree as ET
    return ET.parse(f).getroot()


def _ln(e):
    return e.tag.split('}')[-1] if isinstance(e.tag, str) else ''


def service(f):
    root = _xml(f)
    for sec in root:
        if _ln(sec) not in ('ServiceIdentification', 'ServiceProvider'):
            continue
        for c in sec.iter():
            n = _ln(c)
            if n in ('Title', 'Fees', 'AccessConstraints', 'ProviderName'):
                print(f'     {_ln(sec)}.{n} = {(c.text or "").strip()[:200]!r}')
            elif n == 'ProviderSite':
                print(f'     {_ln(sec)}.{n} = {[v for k, v in c.attrib.items() if k.endswith("href")]}')


def couche(f, ident):
    root = _xml(f)
    for el in root.iter():
        if _ln(el) != 'Layer':
            continue
        kids = list(el)
        if not any(_ln(c) == 'Identifier' and (c.text or '').strip() == ident for c in kids):
            continue
        for c in kids:
            n = _ln(c)
            if n in ('Title', 'Abstract', 'Identifier'):
                print(f'     Layer[{ident}].{n} = {(c.text or "").strip()[:300]!r}')
            elif n in ('Metadata', 'MetadataURL'):
                print(f'     Layer[{ident}].{n} = {[v for k, v in c.attrib.items() if k.endswith("href")]}')
        return
    print(f'     couche {ident} introuvable')


def xmlv(f, *noms):
    root = _xml(f)
    for nom in noms:
        found = [el for el in root.iter() if _ln(el) == nom]
        print(f'  [XML {nom}] {len(found)} element(s)')
        for el in found[:4]:
            txt = ' '.join(t.strip() for t in el.itertext() if t.strip())
            hrefs = [v for e in el.iter() for k, v in e.attrib.items() if k.split('}')[-1] in ('href', 'codeListValue')]
            print(f'     {txt[:400]!r}' + (f'  attributs={hrefs[:4]}' if hrefs else ''))


def dgf(f):
    j = json.load(open(f, encoding='utf-8'))
    data = j.get('data', [])
    print(f'  [data.gouv.fr] total={j.get("total")} ; {len(data)} fiches recues')
    for d in data:
        t = d.get('title', '') or ''
        if re.search(r'compl|g[ée]ocod|WMTS|TMS|tuil', t, flags=re.I):
            print(f'     {t[:90]!r} | rate_limiting={d.get("rate_limiting")!r} | access_type={d.get("access_type")!r} | license={d.get("license")!r}')


def titre(f):
    s = lire(f)
    m = re.search(r'<title[^>]*>(.*?)</title>', s, flags=re.S | re.I)
    if m:
        print('   titre : ' + collapse(html.unescape(m.group(1)))[:160])


def debut(f, n=400):
    print('   debut : ' + prep(lire(f), 'text')[:int(n)])


if __name__ == '__main__':
    cmd, args = sys.argv[1], sys.argv[2:]
    fn = {'cherche': cherche, 'tables': tables, 'liens': liens, 'nuxt': nuxt, 'brut': brut, 'service': service,
          'couche': couche, 'xmlv': xmlv, 'dgf': dgf, 'titre': titre, 'debut': debut}.get(cmd)
    try:
        if fn is None:
            print('  [ERREUR] sous-commande inconnue', cmd)
        else:
            fn(*args)
    except Exception as e:
        print('  [ERREUR]', cmd, type(e).__name__, str(e)[:200])
PYEOF
py() { python3 -I "$P/cv.py" "$@"; }
page() { # page NOM URL : télécharge (redirections suivies), affiche code, adresse finale, chaîne de redirections, titre
  local nom="$1" url="$2" r ch
  r=$(curl -sS -L -m 90 --compressed -A "$UA" -o "$D/$nom" -D "$D/$nom.h" -w '%{http_code} %{url_effective} redirs=%{num_redirects} %{size_download}o %{content_type}' "$url" 2>&1)
  echo "== $nom : $url"
  echo "   -> $r"
  ch=$(grep -aiE '^(HTTP/|location:)' "$D/$nom.h" 2>/dev/null | tr -d '\r' | paste -sd' ' - | cut -c1-400)
  [ -n "$ch" ] && echo "   chaine : $ch"
  py titre "$D/$nom"
  sleep 1
}
entetes() { # entetes URL MOTIF : en-têtes choisis d'une réponse, corps jeté
  echo "== en-tetes : $1"
  curl -sS -m 60 --compressed -A "$UA" -o /dev/null -D - "$1" 2>&1 | tr -d '\r' | grep -aiE "^(HTTP/|$2)" | cut -c1-200 | sed 's/^/   /'
  sleep 1
}
pdfoutils() { # installe pdftotext et pdfinfo si besoin
  command -v pdftotext >/dev/null 2>&1 && return
  apt-get update -qq >/dev/null 2>&1 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq poppler-utils >/dev/null 2>&1
  command -v pdftotext >/dev/null 2>&1 && echo "   (poppler-utils installe)" || echo "   (poppler-utils indisponible)"
}
echo "User-Agent des requetes : $UA"

pdfoutils

echo "######## 1. Geoplateforme IGN : CGU (adresse citee https://cartes.gouv.fr/cgu/, atteinte depuis https://geoservices.ign.fr/cgu-licences)"
page cgu.html "https://geoservices.ign.fr/cgu-licences"
py cherche "$D/cgu.html" html <<'X'
Version du 15 octobre 2024
Sur la Géoplateforme, l'utilisation des géodonnées et géoservices est gratuite (sauf licence spécifique).
Les données contenues dans les API sont soumises à la licence choisie et renseignée par le Fournisseur de données, accessible depuis les métadonnées de données de l'API. Vous vous engagez à respecter les termes de la licence attachée à ces données
A défaut, la Licence Ouverte / Open Licence - Etalab s'applique sur ce jeu de données.
?Licence Ouverte
Article 3.2 : Limite d'usage (Fair use)
Pour certaines API, une limite d'usage fixée en nombre de requêtes par seconde et par IP est mise en place.
Au-delà de cette limite, une erreur HTML 429 (Too Many Requests) est envoyée en réponse à toute requête.
intervient pour une durée de 5 secondes et il ne concerne que l'API dont la limite d'usage a été franchie
Limite en nombre de requêtes par seconde et par IP
En cas de manquement aux CGU, d'usage abusif d'une ou plusieurs API ou mettant en péril le bon fonctionnement de la Géoplateforme, l'IGN peut limiter ou bloquer l'accès et l'utilisation de l'API et/ou retirer les données mises à disposition à partir d'une API de façon temporaire ou définitive.
re:(Autocompl[ée]tion|G[ée]ocodage)\W{0,6}\d+ ?requ
re:\bcache\b|hors[ -]ligne|hors connexion|aspir|robot|paternit
X
py tables "$D/cgu.html" "Autocomplétion"
py liens "$D/cgu.html" 'licen|etalab'

echo "######## 2. Guide Limites d'usage des API (adresse citee)"
page guide.html "https://cartes.gouv.fr/aide/fr/guides-utilisateur/utiliser-les-services-de-la-geoplateforme/limites-d-usage/"
py cherche "$D/guide.html" html <<'X'
?Modifié le
Ce mécanisme, dit de « rate limiting », concerne la plupart des API de la Géoplateforme à l'exception notable de l'API « Diffusion d'images tuilées WMTS » et son pendant « Diffusion de tuiles vectorielles TMS ».
Il a pour objectif de garantir les engagements de disponibilité des API, en bloquant les usages individuels les plus massifs qui seraient susceptibles de mettre à mal l'infrastructure.
La durée du blocage est indiquée dans un header « retry-after », avec une durée initialisée à 5 secondes et qui décroît à partir du moment où la sur-sollicitation cesse.
re:compl[ée]tion|g[ée]ocodage
X
py tables "$D/guide.html" "requ"

echo "######## 3. Licence Ouverte 2.0 (adresse citee https://raw.githubusercontent.com/etalab/licence-ouverte/master/LO.md)"
page lo.md "https://raw.githubusercontent.com/etalab/licence-ouverte/master/LO.md"
py debut "$D/lo.md" 160
py cherche "$D/lo.md" text <<'X'
LICENCE OUVERTE 2.0/OPEN LICENCE 2.0
de la communiquer, la reproduire, la copier
de la diffuser, la redistribuer, la publier et la transmettre, de l'exploiter à titre commercial
mentionner la paternité de l'«Information» : sa source (a minima le nom du « Concédant ») et la date de la dernière mise à jour de l'« Information » réutilisée.
Le « Réutilisateur » peut notamment s'acquitter de cette condition en indiquant l'adresse (URL) renvoyant vers « l'Information » et assurant une mention effective de sa paternité.
X

echo "######## 4. Licence des couches : CSW de la Geoplateforme, puis PDF de licence vers lequel pointe la fiche"
for id in IGNF_PLAN-IGN IGNF_BD-ORTHO; do
  page "csw-$id.xml" "https://data.geopf.fr/csw?REQUEST=GetRecordById&SERVICE=CSW&VERSION=2.0.2&OUTPUTSCHEMA=http://standards.iso.org/iso/19115/-3/mdb/2.0&elementSetName=full&ID=$id"
  py xmlv "$D/csw-$id.xml" otherConstraints useLimitation accessConstraints
done
page etalab.pdf "https://www.etalab.gouv.fr/wp-content/uploads/2018/11/open-licence.pdf"
if command -v pdfinfo >/dev/null 2>&1; then
  pdfinfo "$D/etalab.pdf" 2>/dev/null | grep -aE '^(Title|CreationDate|ModDate|Pages):' | sed 's/^/   /'
  pdftotext -enc UTF-8 "$D/etalab.pdf" "$D/etalab.txt" 2>/dev/null && py debut "$D/etalab.txt" 300
fi

echo "######## 5. Fiches data.gouv.fr des API de l'IGN (champ rate_limiting)"
page dgf.json "https://www.data.gouv.fr/api/1/dataservices/?organization=534fff80a3a7292c64a77e41&page_size=50"
py dgf "$D/dgf.json"

echo "######## 6. En-tetes de limite renvoyes par data.geopf.fr (une requete par service)"
entetes "https://data.geopf.fr/geocodage/completion?text=lautaret&type=PositionOfInterest&maximumResponses=1" 'ratelimit|x-ratelimit|retry-after'
entetes "https://data.geopf.fr/tms/1.0.0/PLAN.IGN/0/0/0.pbf" 'ratelimit|x-ratelimit|retry-after|cache-control'
entetes "https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2&STYLE=normal&FORMAT=image/png&TILEMATRIXSET=PM&TILEMATRIX=0&TILEROW=0&TILECOL=0" 'ratelimit|x-ratelimit|retry-after|cache-control'
echo "######## fin"
