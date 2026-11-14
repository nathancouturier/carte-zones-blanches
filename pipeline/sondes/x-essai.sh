#!/usr/bin/env bash
# Essai du lancement d'une sonde à la main, et présence du secret OpenCelliD.
set -u
. "$(dirname "$0")/_lib.sh"
if [ -n "${OPENCELLID_TOKEN:-}" ]; then echo "secret OPENCELLID_TOKEN : présent (longueur ${#OPENCELLID_TOKEN})"; else echo "secret OPENCELLID_TOKEN : absent"; fi
echo "FIN"
