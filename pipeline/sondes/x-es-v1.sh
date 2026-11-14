#!/usr/bin/env bash
set -u
. "$(dirname "$0")/_lib.sh"
# Contre-vérification « Espagne : ministère et régions », sonde es-v1.
# Client générique : aucun identifiant du projet ni de personne dans les requêtes vers des services tiers.
UA="sonde-verification/1.0"
export UA T
apt-get update -qq >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends poppler-utils >/dev/null 2>&1
if command -v pdftotext >/dev/null 2>&1; then echo "pdftotext : présent"; else echo "pdftotext : absent"; fi
python3 - <<'PY_FIN_SONDE'
# Fonctions communes aux sondes de contre-vérification « Espagne : ministère et régions ».
# Ce fichier est recopié en tête de chaque sonde (voir assembler.sh) : il n'est pas importé.
import collections, gzip, html, json, os, re, sys, time, traceback
import urllib.error, urllib.parse, urllib.request, urllib.robotparser

UA = os.environ.get("UA", "sonde-verification/1.0")
T = os.environ.get("T", "/tmp/sonde")
os.makedirs(T, exist_ok=True)
REQ = collections.Counter()
OCTETS = collections.Counter()
LAST = {}
ROBOTS = {}
PAUSE = 0.6


def P(s="", n=300):
    for line in str(s).split("\n"):
        print(line[:n])
    sys.stdout.flush()


def sans_courriel(s):
    """Retire les adresses électroniques avant affichage (pas de données de personnes dans les logs)."""
    return re.sub(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+", "<courriel retiré>", s)


def fetch(url, data=None, timeout=150, tries=2, headers=None):
    """Requête HTTP polie : pause entre deux requêtes vers le même hôte, pas de nouvel essai sur une erreur HTTP."""
    host = urllib.parse.urlsplit(url).netloc
    wait = PAUSE - (time.time() - LAST.get(host, 0))
    if wait > 0:
        time.sleep(wait)
    err = None
    hd = {"User-Agent": UA, "Accept-Encoding": "gzip"}
    hd.update(headers or {})
    for _ in range(tries):
        req = urllib.request.Request(url, data=data, headers=hd)
        REQ[host] += 1
        t0 = time.time()
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                raw = r.read()
                body = raw
                if (r.headers.get("Content-Encoding") or "").lower() == "gzip":
                    body = gzip.decompress(raw)
                LAST[host] = time.time()
                OCTETS[host] += len(raw)
                h = dict(r.headers)
                h["_recu"] = len(raw)
                h["_duree"] = round(time.time() - t0, 1)
                return r.status, h, body, r.geturl()
        except urllib.error.HTTPError as e:
            body = e.read() or b""
            try:
                if (e.headers.get("Content-Encoding") or "").lower() == "gzip":
                    body = gzip.decompress(body)
            except Exception:
                pass
            LAST[host] = time.time()
            h = dict(e.headers or {})
            h["_recu"] = len(body)
            h["_duree"] = round(time.time() - t0, 1)
            return e.code, h, body, e.geturl()
        except Exception as e:  # réseau, délai dépassé
            err = e
            LAST[host] = time.time()
            time.sleep(3)
    return 0, {"_recu": 0, "_duree": 0}, repr(err).encode(), url


def robots_de(host):
    """Lit robots.txt une fois par hôte. Sans fichier robots valable, rien n'est déclaré : tout est permis."""
    if host in ROBOTS:
        return ROBOTS[host]
    st, hd, body, _ = fetch("https://%s/robots.txt" % host, timeout=40)
    txt = body.decode("utf-8", "replace")
    ok = st == 200 and "<html" not in txt[:600].lower() and re.search(r"(?im)^\s*(user-agent|disallow|allow|sitemap)\s*:", txt) is not None
    rp = urllib.robotparser.RobotFileParser()
    rp.parse(txt.splitlines() if ok else [])
    ROBOTS[host] = (rp, st, ok, txt)
    return ROBOTS[host]


def permis(url):
    return robots_de(urllib.parse.urlsplit(url).netloc)[0].can_fetch(UA, url)


def get(url, quiet=False, **kw):
    """Requête soumise à robots.txt : une adresse interdite aux robots n'est pas demandée (code -1)."""
    if not permis(url):
        P("  [SAUT : interdit par robots.txt] %s" % url[:230])
        return -1, {"_recu": 0, "_duree": 0}, b"", url
    st, hd, body, final = fetch(url, **kw)
    if not quiet:
        extra = "" if final == url else " (final : %s)" % final[:140]
        P("  -> %s %so %s en %ss  %s%s" % (st, len(body), (hd.get("Content-Type") or "")[:38], hd.get("_duree"), url[:230], extra))
    return st, hd, body, final


def get_json(url, quiet=True, **kw):
    st, hd, body, _ = get(url, quiet=quiet, **kw)
    if st == -1:
        return None
    try:
        d = json.loads(body.decode("utf-8", "replace"))
    except Exception:
        P("  [réponse non JSON, code %s] %s : %s" % (st, url[:170], body[:160].decode("utf-8", "replace").replace("\n", " ")))
        return None
    if isinstance(d, dict) and "error" in d and len(d) == 1:
        P("  [erreur de l'API] %s : %s" % (url[:200], json.dumps(d["error"], ensure_ascii=False)[:230]))
    return d


def query(layer_url, quiet=True, **params):
    params.setdefault("f", "json")
    return get_json(layer_url + "/query?" + urllib.parse.urlencode(params), quiet=quiet)


def to_text(s):
    s = re.sub(r"(?is)<(script|style|svg|noscript)\b.*?</\1>", " ", s)
    s = re.sub(r"(?i)<br\s*/?>|</(p|div|li|tr|h[1-6]|td|th)>", "\n", s)
    s = html.unescape(re.sub(r"<[^>]+>", " ", s))
    s = re.sub(r"[ \t\r\f\v\xa0]+", " ", s)
    return re.sub(r"\n\s*\n+", "\n", s).strip()


def plat(s):
    """Texte sur une seule ligne, espaces compactés."""
    return re.sub(r"\s+", " ", s).strip()


def jour(ms):
    try:
        return time.strftime("%Y-%m-%d", time.gmtime(int(ms) / 1000))
    except Exception:
        return str(ms)


def bloc(titre, fn):
    P("")
    P("##### " + titre)
    try:
        fn()
    except Exception as e:
        tb = traceback.extract_tb(sys.exc_info()[2])[-1]
        P("  [ECHEC DU BLOC] %s : %s (ligne %s)" % (type(e).__name__, str(e)[:240], tb.lineno))


def bilan():
    P("")
    P("##### Bilan des requêtes")
    for h in sorted(REQ):
        P("  %-46s %3d requêtes, %9d octets reçus" % (h, REQ[h], OCTETS[h]))
    P("  total : %d requêtes" % sum(REQ.values()))


# Identifiant fiscal d'une personne morale espagnole (CIF) : une lettre de société, 7 chiffres, un caractère de contrôle.
CIF_MORALE = re.compile(r"^[ABCDEFGHJNPQRSUVW]\d{7}[0-9A-J]$")


def cif_affichable(s):
    """N'affiche que les identifiants de personnes morales ; tout autre identifiant est masqué."""
    s = (s or "").strip()
    return s if CIF_MORALE.match(s) else ("<identifiant masqué, %d caractères>" % len(s) if s else "")

# Sonde es-v1 : conditions de réutilisation relues à la source, et règles robots.txt des hôtes concernés.
# Aucune donnée de couverture n'est demandée ici.
import subprocess

ORG = "3LqdsBPalJaUFvo1"
EXP = "ef9f55c81f304e5185fcdd7cecf98e7f"
A_EVALUER = [
    "https://experience.arcgis.com/experience/" + EXP,
    "https://www.arcgis.com/sharing/rest/content/items/%s?f=json" % EXP,
    "https://www.arcgis.com/sharing/rest/content/items/%s/data?f=json" % EXP,
    "https://www.arcgis.com/sharing/rest/search?q=owner:coberturaBA_eu&f=json",
    "https://services-eu1.arcgis.com/%s/arcgis/rest/services/InfoCob4G_2024/FeatureServer/0?f=json" % ORG,
    "https://services-eu1.arcgis.com/%s/arcgis/rest/services/InfoCob4G_2024/FeatureServer/0/query?where=1%%3D1&f=json" % ORG,
    "https://services-eu1.arcgis.com/%s/arcgis/rest/services/InfoCob4G_2024/FeatureServer/createReplica" % ORG,
    "https://services-eu1.arcgis.com/%s/arcgis/rest/services/Datos_Operadores_BA/FeatureServer/9/query?where=1%%3D1&f=json" % ORG,
    "https://tiledimageservices-eu1.arcgis.com/%s/arcgis/rest/services/Cob4G_2024/ImageServer?f=json" % ORG,
    "https://tiledimageservices-eu1.arcgis.com/%s/arcgis/rest/services/Cob4G_2024/ImageServer/tile/7/534/2038" % ORG,
    "https://services9.arcgis.com/b5sc9d51LIwFoyfR/arcgis/rest/services/InfoCob4G_2024/FeatureServer/0?f=json",
    "https://tiledimageservices9.arcgis.com/b5sc9d51LIwFoyfR/arcgis/rest/services/Cob4G_2024/ImageServer?f=json",
]
CITATIONS = [
    "Las presentes condiciones generales permiten la reutilización de los documentos sometidos a ellas para fines comerciales y no comerciales",
    "la copia, difusión, modificación, adaptación, extracción, reordenación y combinación de la información",
    "incluyendo, en consecuencia, también los datos en sus niveles más desagregados o \"en bruto\"",
    "Está prohibido desnaturalizar el sentido de la información",
    "Debe citarse la fuente de los documentos objeto de la reutilización",
    "Origen de los datos: Ministerio para la Transformación Digital y de la Función Pública",
    "Debe mencionarse la fecha de la última actualización de los documentos objeto de la reutilización",
    "vincularán a cualquier agente reutilizador por el mero hecho de hacer uso de los documentos sometidos a ellas",
]


def norm(s):
    s = s.replace("“", '"').replace("”", '"').replace("«", '"').replace("»", '"').replace("’", "'")
    return re.sub(r"\s+", " ", s).strip()


def page_texte(url, **kw):
    st, hd, body, final = get(url, **kw)
    if st != 200:
        return ""
    raw = body.decode("utf-8", "replace")
    m = re.search(r"(?is)<title[^>]*>(.*?)</title>", raw)
    P("     titre de la page : %s" % plat(html.unescape(m.group(1)))[:160] if m else "     (pas de titre)")
    return raw


def phrases(t, motif, maxi=8, avant=140, apres=260, deja=None):
    n = 0
    vus = deja if deja is not None else []
    for m in re.finditer(motif, t):
        a, b = max(0, m.start() - avant), min(len(t), m.end() + apres)
        if any(abs(a - v) < 250 for v in vus):
            continue
        vus.append(a)
        P("     … %s …" % sans_courriel(t[a:b]), avant + apres + 60)
        n += 1
        if n >= maxi:
            break
    return n


def A():
    hotes = []
    for u in A_EVALUER + ["https://digital.gob.es/nota-legal", "https://conectemos.digital.gob.es/es/aviso-legal",
                          "https://datos.gob.es/es/aviso-legal", "https://www.boe.es/buscar/act.php?id=BOE-A-2007-19814"]:
        h = urllib.parse.urlsplit(u).netloc
        if h not in hotes:
            hotes.append(h)
    for h in hotes:
        rp, st, ok, txt = robots_de(h)
        regles = [plat(l) for l in txt.splitlines() if re.match(r"(?i)\s*(user-agent|disallow|allow|crawl-delay)\s*:", l)] if ok else []
        P("  %s/robots.txt -> code %s, %d octets, fichier robots valable : %s, %d règles" % (h, st, len(txt), ok, len(regles)))
        if regles:
            P("     " + " | ".join(regles[:26]), 900)
    P("  adresses du rapport, autorisées aux robots (User-agent générique) ?")
    for u in A_EVALUER:
        P("     %-5s %s" % ("oui" if permis(u) else "NON", u[:200]))


def B():
    raw = page_texte("https://digital.gob.es/nota-legal")
    if not raw:
        return
    tit = [plat(to_text(x)) for x in re.findall(r"(?is)<h[1-4][^>]*>(.*?)</h[1-4]>", raw)]
    P("  intertitres (h1 à h4) : " + " | ".join(x for x in tit if x)[:1400], 1500)
    t = norm(to_text(raw))
    P("  texte de la page : %d caractères" % len(t))
    for c in CITATIONS:
        P("     citation présente mot pour mot : %-5s « %s »" % (norm(c) in t, c[:150]))
    i = t.find("Condiciones generales de reutilización")
    j = t.find("Derechos de propiedad intelectual e industrial")
    P("  position de « Condiciones generales de reutilización » : %d ; de « Derechos de propiedad intelectual e industrial » : %d" % (i, j))
    if j >= 0:
        P("  section propriété intellectuelle (suite du texte, 1700 caractères) :")
        P("     " + sans_courriel(t[j:j + 1700]), 1800)
    k = t.find("Aviso legal")
    deb = t[:i] if i > 0 else t
    P("  avant les conditions de réutilisation, phrases contenant « reutiliz », « propiedad intelectual », « terceros », « salvo », « excep », « licencia » :")
    n = phrases(deb, r"(?i)reutiliz|propiedad intelectual|de terceros|salvo |excep|licencia", maxi=8)
    P("     (%d extrait(s)) ; « reutiliz » : %d occurrence(s) dans toute la page ; « datos.gob.es/aviso-legal » cité : %s" % (
        n, len(re.findall(r"(?i)reutiliz", t)), "datos.gob.es/aviso-legal" in t.replace(" ", "")))
    P("  champ d'application : phrases contenant « documentos sometidos », « sitio web », « portal » dans la section réutilisation :")
    sec = t[i:j] if 0 <= i < j else ""
    phrases(sec, r"(?i)sometidos a ellas|este portal|sitio web|sede electr", maxi=4, avant=120, apres=200)


def C():
    for u in ("https://datos.gob.es/es/aviso-legal", "https://datos.gob.es/aviso-legal"):
        raw = page_texte(u)
        if raw:
            break
    if not raw:
        return
    t = norm(to_text(raw))
    P("  texte : %d caractères" % len(t))
    for c in CITATIONS[:2] + CITATIONS[3:5]:
        P("     même phrase présente : %-5s « %s »" % (norm(c) in t, c[:120]))
    P("  phrases sur le champ d'application et les exclusions :")
    phrases(t, r"(?i)sometidos a ellas|no ser[áa] de aplicaci|salvo que|excep|de terceros|modalidad general", maxi=7, avant=160, apres=300)


def D():
    raw = page_texte("https://conectemos.digital.gob.es/es/aviso-legal")
    if raw:
        t = norm(to_text(raw))
        P("  texte : %d caractères ; occurrences : reutiliz=%d, licencia=%d, propiedad intelectual=%d, datos abiertos=%d, reproduc=%d" % (
            len(t), len(re.findall(r"(?i)reutiliz", t)), len(re.findall(r"(?i)licencia", t)), len(re.findall(r"(?i)propiedad intelectual", t)),
            len(re.findall(r"(?i)datos abiertos", t)), len(re.findall(r"(?i)reproduc", t))))
        phrases(t, r"(?i)propiedad intelectual|reproduc|prohib|autoriza", maxi=5, avant=160, apres=420)
    raw = page_texte("https://conectemos.digital.gob.es/es/areas-de-interes/banda-ancha/informacion-de-cobertura")
    if raw:
        t = norm(to_text(raw))
        P("  page « información de cobertura » : %d caractères ; phrases contenant « reutiliz », « descarg », « mapa », « 30 de junio » :" % len(t))
        phrases(t, r"(?i)reutiliz|descargable|mapas? de servicios|30 de junio", maxi=7, avant=120, apres=240)
        for m in re.finditer(r'href="([^"]+\.(?:xlsx|zip|csv|gpkg|shp|json)[^"]*)"', raw):
            P("     fichier lié : %s" % html.unescape(m.group(1))[:220])


def E():
    u = ("https://conectemos.digital.gob.es/content/dam/seteleco-portal-connect/resources/pdf/icba2025/"
         "Metodolog%C3%ADa_Informe_Cobertura-BA-2025.pdf")
    st, hd, body, _ = get(u, timeout=240)
    if st != 200 or body[:4] != b"%PDF":
        P("  pas de PDF (code %s, début %r)" % (st, body[:20]))
        return
    path = os.path.join(T, "metodologia2025.pdf")
    open(path, "wb").write(body)
    r = subprocess.run(["pdftotext", "-layout", path, "-"], capture_output=True, timeout=180)
    t = norm(r.stdout.decode("utf-8", "replace"))
    P("  pdftotext : code %s, %d caractères" % (r.returncode, len(t)))
    for nom, motif, maxi in (("confidentialité", r"(?i)confidencial", 4), ("réutilisation", r"(?i)reutiliz", 4), ("propriété intellectuelle", r"(?i)propiedad intelectual|propiedad industrial", 3),
                             ("carte de services", r"(?i)mapas? de servicios", 4), ("article 22", r"(?i)art[íi]culo 22", 2), ("résolution", r"(?i)\b(?:50|100)\s?x\s?(?:50|100)\s?m", 4),
                             ("seuils", r"RSRP", 3), ("date de référence", r"(?i)30 de junio de 20\d\d", 3), ("opérateurs de réseau", r"(?i)operadores m[óo]viles de red|operador(?:es)? de red", 3)):
        k = len(re.findall(motif, t))
        P("  [%s] %d occurrence(s)" % (nom, k))
        phrases(t, motif, maxi=maxi, avant=170, apres=330)


def loi(url, nom, motifs, maxi=2, debut=None, fin=None, largeur=9000):
    """Affiche les passages d'un texte légal du BOE. debut et fin : expressions régulières qui bornent un article."""
    raw = page_texte(url, timeout=240)
    if not raw:
        return
    t = norm(to_text(raw))
    if debut:
        m = re.search(debut, t)
        if m:
            f = re.search(fin, t[m.end():]) if fin else None
            b = m.end() + f.start() if f else m.start() + largeur
            P("  %s : article borné, positions %d à %d ; intitulé : %s" % (nom, m.start(), b, t[m.start():m.start() + 110]))
            t = t[m.start():b]
        else:
            P("  %s : borne de début introuvable (%s), analyse du texte entier" % (nom, debut))
    P("  %s : %d caractères analysés" % (nom, len(t)))
    deja = []
    for motif in motifs:
        k = len(re.findall(motif, t))
        P("  [%s] %d occurrence(s)" % (motif[:60], k))
        phrases(t, motif, maxi=maxi, avant=280, apres=560, deja=deja)


def F():
    loi("https://www.boe.es/buscar/act.php?id=BOE-A-2007-19814", "Ley 37/2007 (texte consolidé)",
        [r"(?i)propiedad intelectual o industrial por parte de terceros", r"(?i)sin sujeci[óo]n a condiciones", r"(?i)ser[áa]n reutilizables"], maxi=2)
    loi("https://www.boe.es/buscar/act.php?id=BOE-A-2011-17560", "Real Decreto 1495/2011 (texte consolidé)",
        [r"(?i)modalidad general", r"(?i)aviso legal"], maxi=2)
    loi("https://www.boe.es/buscar/doc.php?id=DOUE-L-2018-82068", "Directive (UE) 2018/1972, article 22",
        [r"(?i)reutiliz", r"(?i)herramientas de informaci[óo]n", r"(?i)confidencialidad comercial"], maxi=3,
        debut=r"Artículo 22\.?\s+Estudios geográficos", fin=r"Artículo 23\.?\s+[A-ZÁÉÍÓÚ]")
    loi("https://www.boe.es/buscar/act.php?id=BOE-A-2022-10757", "Ley 11/2022 General de Telecomunicaciones (texte consolidé)",
        [r"(?i)reutiliz", r"(?i)herramientas de informaci[óo]n", r"(?i)confidencial"], maxi=2,
        debut=r"Artículo \d+\.\s+Estudios geográficos", fin=r"Artículo \d+\.\s+[A-ZÁÉÍÓÚ]")


def G():
    u = "https://datos.gob.es/es/solicitud-de-datos/datos-en-abierto-de-conectividad-movil-y-antenas"
    st, hd, body, _ = get(u)
    if st != 200:
        return
    t = norm(to_text(body.decode("utf-8", "replace")))
    # Le texte libre de la demande (après « Descripción ») contient le nom du demandeur : il n'est jamais affiché.
    # Seuls des champs repérés par une liste blanche sont affichés.
    k = t.find("Descripción")
    tete = t[:k] if k > 0 else ""
    etats = sorted(set(re.findall(r"No viable|En estudio|En evaluación|Publicad[oa]|Rechazad[oa]|Aceptad[oa]|Finalizad[oa]|Viable", tete)))
    f1 = re.search(r"Fecha de la petición (\d\d/\d\d/\d{4})", tete)
    f2 = re.search(r"Fecha actualización (\d\d/\d\d/\d{4})", tete)
    org = re.search(r"Organismo responsable (Ministerio[^|]{0,90})$", tete.strip())
    P("  en-tête de la demande : états cités=%s ; date de la demande=%s ; mise à jour=%s ; organisme=%s" % (
        etats, f1.group(1) if f1 else None, f2.group(1) if f2 else None, org.group(1) if org else None))
    P("  dans toute la page : « No viable »=%d, « propiedad intelectual »=%d, « Respuesta »=%d, « confidencial »=%d" % (
        len(re.findall(r"No viable", t)), len(re.findall(r"(?i)propiedad intelectual", t)), len(re.findall(r"Respuesta", t)), len(re.findall(r"(?i)confidencial", t))))


bloc("A. robots.txt des hôtes et adresses du rapport", A)
bloc("B. Mentions légales du ministère (digital.gob.es/nota-legal)", B)
bloc("C. Conditions générales sur datos.gob.es (citées par les mentions légales)", C)
bloc("D. Portail Conectemos : mentions légales et page des données de couverture", D)
bloc("E. Méthodologie 2025 du rapport de couverture (PDF texte)", E)
bloc("F. Textes légaux au BOE : loi de réutilisation, directive (article 22), loi générale des télécommunications", F)
bloc("G. datos.gob.es : état de la demande d'ouverture des données de connectivité mobile", G)
bilan()
PY_FIN_SONDE
echo "FIN (code python : $?)"
