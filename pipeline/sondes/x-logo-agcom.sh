#!/usr/bin/env bash
# Récupère le logo que la licence de l'AGCOM (CC BY 4.0) demande d'afficher dans toute œuvre dérivée.
. "$(dirname "$0")/_lib.sh"
url='https://www.agcom.it/sites/default/files/inline-images/licenza%20uso%20mappatura%20reti.jpg'
curl -sS -L -m 60 -A "$UA" -o "$T/logo.jpg" -w 'code=%{http_code} type=%{content_type} octets=%{size_download}\n' "$url"
file "$T/logo.jpg" 2>/dev/null || true
python3 - "$T/logo.jpg" <<'PY'
import sys, base64, hashlib
data = open(sys.argv[1], 'rb').read()
print('sha256', hashlib.sha256(data).hexdigest(), len(data), 'octets', 'JPEG' if data[:3] == b'\xff\xd8\xff' else 'PAS UN JPEG')
print('=====DEBUT agcom-bbmap.jpg=====')
text = base64.b64encode(data).decode()
for i in range(0, len(text), 120):
    print(text[i:i + 120])
print('=====FIN agcom-bbmap.jpg=====')
PY
