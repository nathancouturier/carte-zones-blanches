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
    for h, t in ms[:int(n)]:
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
    for k in hits[:int(n)]:
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


def hrefs(f, ident):
    root = _xml(f)
    for el in root.iter():
        if _ln(el) != 'Layer':
            continue
        kids = list(el)
        if not any(_ln(c) == 'Identifier' and (c.text or '').strip() == ident for c in kids):
            continue
        for c in kids:
            if _ln(c) in ('Metadata', 'MetadataURL'):
                for e in c.iter():
                    for k, v in e.attrib.items():
                        if k.endswith('href'):
                            print(v.strip())
                    if _ln(e) in ('OnlineResource', 'URL') and (e.text or '').strip().startswith('http'):
                        print(e.text.strip())
        return


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
          'couche': couche, 'hrefs': hrefs, 'xmlv': xmlv, 'dgf': dgf, 'titre': titre, 'debut': debut}.get(cmd)
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

echo "######## 1. IGN Espana : GetCapabilities du WMTS mapa-raster (adresse citee)"
page caps-es.xml "https://www.ign.es/wmts/mapa-raster?request=GetCapabilities&service=WMTS"
py service "$D/caps-es.xml"
py couche "$D/caps-es.xml" MTN

echo "######## 2. IGN Espana : licence d'usage (adresse citee https://www.ign.es/resources/licencia/Condiciones_licenciaUso_IGN.pdf)"
page lic-es.pdf "https://www.ign.es/resources/licencia/Condiciones_licenciaUso_IGN.pdf"
if command -v pdfinfo >/dev/null 2>&1; then
  pdfinfo "$D/lic-es.pdf" 2>/dev/null | grep -aE '^(Creator|CreationDate|ModDate|Pages):' | sed 's/^/   /'
  pdftotext -enc UTF-8 "$D/lic-es.pdf" "$D/lic-es.txt" 2>/dev/null
  py debut "$D/lic-es.txt" 300
  py cherche "$D/lic-es.txt" text <<'X'
El uso de los productos de datos geográficos digitales mencionados en el Artículo 2 tendrá carácter libre y gratuito, siempre que se mencione el origen y propiedad de los datos, con el alcance y forma que autorice la licencia de uso correspondiente
el uso de los productos y servicios de información geográfica del IGN definidos en el ámbito de la Orden FOM/2807/2015 conlleva la aceptación por el usuario de una licencia CC-BY 4.0
«<identificador del producto> <fecha> CC-BY 4.0 <atribución de productores>»
BTN25 2014-2015 CC-BY 4.0 ign.es
Esta mención de atribución obligatoria se mostrará visible junto con los datos, de forma legible y a pie de mapa, imagen, presentación o ventana de visualización. En caso de imposibilidad manifiesta y justificable se podrá incluir en listados de capas o servicios, leyendas, tablas de contenidos o créditos, siempre de manera que quede claro el origen y propiedad del IGN de España.
2. Para los servicios, en el caso de que se use el servicio sin modificar, se utilizará la fórmula de reconocimiento establecida para los datos acoplados, utilizados en cada caso y, si no hay datos acoplados, la fórmula que esté incluida en la autodescripción del servicio original, en la etiqueta <AccessConstraints>.
En todo caso, cuando sea factible, el texto será un hiperenlace a la dirección web correspondiente.
Cuarto.- Se podrá utilizar como fórmula alternativa abreviada y por razones justificables de espacio o diseño, la expresión general «CC-BY 4.0 <atribución productores> <fecha>».
re:CNIG
X
fi

echo "######## 3. OpenTopoMap : page about (adresse citee https://opentopomap.org/about)"
page otm-about.html "https://opentopomap.org/about"
py cherche "$D/otm-about.html" html <<'X'
OpenTopoMap steht unter der Lizenz CC-BY-SA. Das bedeutet, dass die Karte kostenlos und frei verwendet werden darf, solange stets Namensnennung erfolgt und die Weitergabe unter gleichen Bedingungen möglich ist.
Als Lizenztext sollte Folgendes deutlich sichtbar sein: Kartendaten: © OpenStreetMap-Mitwirkende, SRTM | Kartendarstellung: © OpenTopoMap (CC-BY-SA)
Dies ist jederzeit gerne möglich, sofern unser Server z.B. durch Massendownloads nicht zu stark beansprucht wird. Außerdem kann keinerlei Ausfallsicherheit garantiert werden. Wir würden uns generell über eine kurze Information über die Verwendung freuen.
We updated our render server to a smaller vServer on 05.01.2026. If there are performance issues, you can select the backup server tiles.
Die Kacheln können unter folgendem Pfad abgerufen werden:
re:Massendownload|Bulk|offline|Cache
X
py brut "$D/otm-about.html" 'Kartendaten' 2 760 0

echo "######## 4. OpenTopoMap : mentions definies dans la page d'accueil"
page otm-home.html "https://opentopomap.org/"
py brut "$D/otm-home.html" 'var topoAttribution2? ?=' 2 520 0
py brut "$D/otm-home.html" 'backup\.opentopomap\.org' 1 300 0

echo "######## 5. Politique des tuiles OSM (adresse citee https://operations.osmfoundation.org/policies/tiles/)"
page osm-tiles.html "https://operations.osmfoundation.org/policies/tiles/"
py cherche "$D/osm-tiles.html" html <<'X'
Offline use is not permitted on tile.openstreetmap.org.
Features such as “Download city/country for offline use” or “Save area for later” rely on prefetch/bulk downloading and are therefore prohibited.
Bulk download (“scrape”) tiles or offer prefetch features.
Bulk downloading is any pre-emptive fetching of tiles other than those a user is actively viewing.
Prohibited: bulk downloading (“scraping”) and offline use
Show OpenStreetMap licence attribution clearly on the map (typically bottom-right).
Typically: © OpenStreetMap contributors
Do not hide attribution beneath UI, behind toggles, or off-screen.
Note: If you require offline maps, use self-hosted tiles or a provider that explicitly allows offline/prefetching.
re:last (updated|modified|revised|edited)|updated on|effective
X

echo "######## 6. Photon (adresse citee https://photon.komoot.io/)"
page photon.html "https://photon.komoot.io/"
py cherche "$D/photon.html" html <<'X'
You can use the API for your project, but please be fair - extensive usage will be throttled. We do not guarantee for the availability and usage might be subject of change in the future.
?Terms of Use
re:ODbL|OpenStreetMap contributors
X
echo "######## fin"
