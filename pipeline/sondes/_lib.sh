# Fonctions communes aux sondes. À charger avec : . "$(dirname "$0")/_lib.sh"
T=/tmp/sonde; mkdir -p "$T"
UA="sonde-donnees-ouvertes/1.0 (curl)"
if ! command -v curl >/dev/null 2>&1; then
  apt-get update -qq >/dev/null 2>&1 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl >/dev/null 2>&1
fi
get() { # get <fichier> <url> : télécharge (3 essais) et affiche code HTTP, taille, type
  local code i
  for i in 1 2 3; do
    code=$(curl -sS -L -m 300 -A "$UA" -o "$1" -w "%{http_code} %{size_download}o %{content_type}" "$2" 2>&1) && break
    sleep 3
  done
  echo "  -> $code  $2"
}
# texte <fichier> [max] : affiche une page HTML en texte brut compact
texte() {
  python3 - "$1" "${2:-4000}" <<'PY'
import re, sys, html
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
s = re.sub(r"<(script|style|svg|noscript)\b.*?</\1>", " ", s, flags=re.S | re.I)
s = re.sub(r"<br\s*/?>|</(p|div|li|tr|h[1-6]|td|th)>", "\n", s, flags=re.I)
s = html.unescape(re.sub(r"<[^>]+>", " ", s))
s = re.sub(r"[ \t\r\f\v]+", " ", s)
s = re.sub(r"\n\s*\n+", "\n", s).strip()
print(s[: int(sys.argv[2])])
PY
}
