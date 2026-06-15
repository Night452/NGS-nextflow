#!/bin/bash
set -e

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================"
echo " BIOINFORMATICS APPLICATION"
echo " Cleanup"
echo "============================================"
echo ""

echo "[1/4] Removing Nextflow work directory..."

if [[ -d "$APP_ROOT/work" ]]; then
rm -rf "$APP_ROOT/work"
fi

mkdir -p "$APP_ROOT/work"

echo "Done."
echo ""

echo "[2/4] Removing old log files (>30 days)..."

if [[ -d "$APP_ROOT/logs" ]]; then
find "$APP_ROOT/logs" 
-type f 
-mtime +30 
-delete
fi

echo "Done."
echo ""

echo "[3/4] Cleaning Nextflow cache..."

if command -v nextflow >/dev/null 2>&1; then
nextflow clean -f 2>/dev/null || true
fi

echo "Done."
echo ""

echo "[4/4] Removing unused Docker images..."

docker image prune -f

echo "Done."
echo ""

echo "============================================"
echo " Cleanup Complete"
echo "============================================"
echo ""
echo "Preserved:"
echo "  data/"
echo "  results/"
echo "  reference genomes"
echo ""
echo "Removed:"
echo "  work/"
echo "  old logs"
echo "  unused Docker images"
echo ""
