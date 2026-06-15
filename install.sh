#!/bin/bash
set -e

echo "============================================"
echo " BIOINFORMATICS APPLICATION"
echo " Global Installation"
echo "============================================"
echo ""

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[1/5] Creating application directories..."

mkdir -p "$PROJECT"

mkdir -p "$PROJECT/data/raw"
mkdir -p "$PROJECT/data/ref"

mkdir -p "$PROJECT/results"
mkdir -p "$PROJECT/work"
mkdir -p "$PROJECT/logs"

mkdir -p "$PROJECT/pipelines"

mkdir -p "$PROJECT/pipelines/germline_gpu"
mkdir -p "$PROJECT/pipelines/germline_cpu"
mkdir -p "$PROJECT/pipelines/rnaseq"
mkdir -p "$PROJECT/pipelines/chipseq"

echo "Done."
echo ""

echo "[2/5] Making shell scripts executable..."

find "$PROJECT" 
-type f 
-name "*.sh" 
-exec chmod +x {} ; 2>/dev/null || true

echo "Done."
echo ""

echo "[3/5] Checking Docker..."

if ! command -v docker >/dev/null 2>&1; then
echo "ERROR: Docker not found."
exit 1
fi

docker --version

echo ""
echo "Docker OK."
echo ""

echo "[4/5] Pulling common images..."

docker pull nextflow/nextflow:26.04.3

echo ""
echo "Common images installed."
echo ""

echo "[5/5] Running pipeline installers..."

export PROJECT

PIPELINE_INSTALLERS=$(find "$PROJECT/pipelines" 
-type f 
-name "*_install.sh" 2>/dev/null || true)

if [[ -z "$PIPELINE_INSTALLERS" ]]; then
echo "No pipeline installers found."
else
while read -r installer
do
[[ -z "$installer" ]] && continue

```
    echo ""
    echo "--------------------------------------------"
    echo "Running:"
    echo "  $installer"
    echo "--------------------------------------------"

    bash "$installer"
done <<< "$PIPELINE_INSTALLERS"
```

fi

echo ""
echo "============================================"
echo " INSTALLATION COMPLETE"
echo "============================================"
echo ""

echo "Application root:"
echo "  $PROJECT"
echo ""

echo "Directory layout:"
echo "  $PROJECT/data"
echo "  $PROJECT/results"
echo "  $PROJECT/work"
echo "  $PROJECT/logs"
echo "  $PROJECT/pipelines"
echo ""

echo "Next steps:"
echo "  1. Copy pipeline folders into:"
echo "     $PROJECT/pipelines/"
echo ""
echo "  2. Place reference genomes in:"
echo "     $PROJECT/data/ref/"
echo ""
echo "  3. Place FASTQs wherever desired"
echo ""
echo "  4. Run the desired pipeline menu script"
echo ""
echo "Done."
