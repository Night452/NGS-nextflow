#!/bin/bash
set -e

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================"
echo " BIOINFORMATICS APPLICATION"
echo " Cleanup"
echo "============================================"
echo ""

echo "[1/5] Removing Nextflow work directories..."

if [[ -d "$APP_ROOT/work" ]]; then
rm -rf "$APP_ROOT/work"
fi

# Also clean the individual pipeline work folders
for pipeline_dir in "$APP_ROOT/pipelines"/*; do
    if [[ -d "$pipeline_dir/work" ]]; then
        rm -rf "$pipeline_dir/work"
    fi
    if [[ -d "$pipeline_dir/.nextflow" ]]; then
        rm -rf "$pipeline_dir/.nextflow"
    fi
done

mkdir -p "$APP_ROOT/work"

echo "Done."
echo ""

echo "[2/5] Removing old log files (>30 days)..."

if [[ -d "$APP_ROOT/logs" ]]; then
find "$APP_ROOT/logs" 
-type f 
-mtime +30 
-delete
fi

echo "Done."
echo ""

echo "[3/5] Cleaning Nextflow cache..."

if command -v nextflow >/dev/null 2>&1; then
nextflow clean -f 2>/dev/null || true
fi

echo "Done."
echo ""

echo "[4/5] Aggressively removing unused Docker images and volumes..."

# This forces Docker to delete all dangling images, stopped containers, and hidden volumes inside the VHDX
docker system prune -a -f --volumes

echo "Done."
echo ""

echo "[5/5] Deep cleaning internal WSL/Linux system caches..."

# Remove Nextflow global cache that builds up in the Linux home directory VHDX
rm -rf ~/.nextflow/assets
rm -rf ~/.nextflow/cache
rm -rf ~/.nextflow/history

# Clear temporary Nextflow garbage left in the Linux /tmp folder
rm -rf /tmp/nextflow*

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
echo "  unused Docker images & volumes"
echo "  WSL internal caches (~/.nextflow, /tmp)"
echo ""
