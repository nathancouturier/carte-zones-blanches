#!/usr/bin/env bash
# Italie, sonde 6 : définitions officielles de la cartographie mobile de l'AGCOM (page « Mappatura delle reti di
# accesso ad Internet », outil « visura », spécification des données d'entrée de la Broadband Map, annexe de la
# délibération 205/25/CONS). But : sens de n_infrastrutture_totali et critère de couverture.
set -u
. "$(dirname "$0")/_lib.sh"
export UA T
apt-get install -y -qq poppler-utils >/dev/null 2>&1
python3 - <<'PY'
import re, os, subprocess, html, traceback

T = os.environ["T"]; UA = os.environ["UA"]

def fetch(url, out, maxtime=180):
    r = subprocess.run(["curl", "-sS", "-L", "-m", str(maxtime), "-A", UA, "-o", out, "-w", "%{http_code} %{size_download}o %{content_type}", url], capture_output=True, text=True)
    return (r.stdout or r.stderr).strip()

def read(path):
    try:
        return open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return ""

def show(s, maxc=1500, width=250, indent="    "):
    s = re.sub(r"\s+", " ", s).strip()
    cut = s[:maxc]
    for k in range(0, len(cut), width):
        print(indent + cut[k:k + width])
    if len(s) > maxc:
        print(indent + f"[... tronqué, {len(s)} caractères au total]")

def text_of(s):
    s = re.sub(r"<(script|style|svg|noscript)\b.*?</\1>", " ", s, flags=re.S | re.I)
    s = re.sub(r"<!--.*?-->", " ", s, flags=re.S)
    return html.unescape(re.sub(r"<[^>]+>", " ", s))

def guarded(fn):
    try:
        fn()
    except Exception:
        print("    ECHEC :", traceback.format_exc()[-700:])

def pdf_text(url, name):
    out = f"{T}/{name}.pdf"
    st = fetch(url, out)
    print("  ->", st, url)
    if not st.startswith("200") or "pdf" not in st.lower():
        show(text_of(read(out)), 250)
        return ""
    subprocess.run(["pdftotext", "-layout", out, out + ".txt"])
    info = subprocess.run(["pdfinfo", out], capture_output=True, text=True).stdout
    print("    ", " | ".join(l.strip() for l in info.splitlines() if re.search(r"^(Title|Pages|CreationDate|ModDate)", l))[:300])
    return read(out + ".txt")

def grep(txt, rx, cap, skip=0):
    k = 0
    for i, line in enumerate(txt.splitlines()):
        if i < skip:
            continue
        if re.search(rx, line, re.I):
            print(f"     {i:5d} | " + re.sub(r"\s+", " ", line).strip()[:230]); k += 1
            if k >= cap:
                print("     (plafond atteint)"); break

def window(txt, rx, size, after=0.0, label=""):
    start = int(len(txt) * after)
    m = re.search(rx, txt[start:], flags=re.I)
    if not m:
        print(f"    (motif absent : {label or rx})"); return
    a = start + m.start()
    print(f"    --- extrait à partir de « {txt[a:a + 60].strip()} » (position {a} sur {len(txt)})")
    show(txt[a: a + size], size)

print("##### 1. Page officielle « Mappatura delle reti di accesso ad Internet »")
def s1():
    u = "https://www.agcom.it/mappatura-delle-reti-di-accesso-ad-internet"
    print("  ->", fetch(u, f"{T}/map.html"), u)
    page = read(f"{T}/map.html")
    txt = re.sub(r"\s+", " ", text_of(page))
    i = txt.find("Percorso")
    show(txt[i if i >= 0 else 0:], 3200)
    for m in re.finditer(r'<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>', page, flags=re.S | re.I):
        href = html.unescape(m.group(1)); label = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", m.group(2))).strip()
        if re.search(r"\.pdf|specific|open ?data|maps\.agcom|geo\d?\.agcom|delibera|mobil|termini", href + " " + label, re.I):
            print("    lien :", href[:200], "|", label[:90])
guarded(s1)

print("##### 2. Outil « visura » (geo.agcom.it/visura)")
def s2():
    u = "https://geo.agcom.it/visura/"
    print("  ->", fetch(u, f"{T}/vis.html"), u)
    page = read(f"{T}/vis.html")
    show(text_of(page), 1500)
    srcs = re.findall(r'<script\b[^>]*\bsrc="([^"]+)"', page, flags=re.I)
    print("    scripts :", [s[:90] for s in srcs][:14])
    k = 0
    blob = page
    for s in srcs:
        if re.search(r"^https?://", s) and "geo.agcom.it" not in s:
            continue
        if re.search(r"jquery|bootstrap|leaflet|vendor|\.min\.js", s, re.I):
            continue
        su = s if s.startswith("http") else "https://geo.agcom.it/visura/" + s.lstrip("./")
        st = fetch(su, f"{T}/vis{k}.js"); k += 1
        print("  ->", st, su[:160])
        blob += "\n" + read(f"{T}/vis{k - 1}.js")
        if k >= 5:
            break
    seen = set(); c = 0
    for m in re.finditer(r"[^\n;{}]{0,200}(?:infrastruttur|n_infra|4G|mobile)[^\n;{}]{0,200}", blob, flags=re.I):
        line = re.sub(r"\s+", " ", m.group(0)).strip()[:300]
        if line[:80] in seen:
            continue
        seen.add(line[:80]); print("     |", line); c += 1
        if c >= 22:
            break
guarded(s2)

print("##### 3. Spécification des données d'entrée de la Broadband Map (version 2.1)")
def s3():
    txt = pdf_text("https://maps.agcom.it/risorse/specifiche/spec_2_1.pdf", "spec21")
    if not txt:
        return
    print("    caractères :", len(txt), "| lignes :", txt.count("\n"))
    show(txt, 1300)
    print("    --- lignes sur le mobile, la grille et les seuils")
    grep(txt, r"mobil|radiomobil|grigliat|cella |celle |100 ?m|soglia|dBm|RSRP|outdoor|indoor|\b[2345]G\b|LTE|infrastruttur", 70)
    window(txt, r"\n[^\n]{0,40}(reti|rete|copertur\w+)[^\n]{0,30}(radio)?mobil", 3800, after=0.12, label="section mobile")
guarded(s3)

print("##### 4. Annexe de la délibération 205/25/CONS (Document I, technologies d'accès)")
def s4():
    txt = pdf_text("https://www.agcom.it/sites/default/files/media/allegato/2025/04_205-25-CONS_Doc%20I_Tecnologie%20accesso.pdf", "doc205")
    if not txt:
        return
    print("    caractères :", len(txt))
    show(txt, 700)
    grep(txt, r"mobil|grigliat|100 ?m|soglia|dBm|RSRP|outdoor|indoor|\b[45]G\b|infrastruttur", 30)
guarded(s4)
print("FIN")
PY
