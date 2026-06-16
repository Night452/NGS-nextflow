#!/usr/bin/env bash
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================"
echo " BIOINFORMATICS APPLICATION"
echo " Global Installation"
echo "============================================"
echo

echo "[1/4] Creating directories..."

mkdir -p "$PROJECT/Data/Raw"
mkdir -p "$PROJECT/Data/Ref"
mkdir -p "$PROJECT/results"
mkdir -p "$PROJECT/work"
mkdir -p "$PROJECT/logs"

echo "Done."
echo

echo "[2/4] Making scripts executable..."

find "$PROJECT/pipelines" \
-type f \
-name "*.sh" \
-exec chmod +x {} \;

chmod +x "$PROJECT/install.sh"
chmod +x "$PROJECT/cleanup.sh"

echo "Done."
echo

echo "[3/4] Verifying Docker..."

docker info >/dev/null

echo "Docker OK."
echo

echo "[4/4] Pulling container images..."

docker pull nextflow/nextflow:26.04.3
docker pull biocontainers/fastqc:v0.11.9_cv8
docker pull biocontainers/bwa:v0.7.17_cv1
docker pull broadinstitute/gatk:4.6.2.0
docker pull staphb/bcftools:1.20
echo "Note: NVIDIA Parabricks image (nvcr.io/nvidia/clara/clara-parabricks:4.7.0-1) is large and is omitted from the default pull, but will be downloaded automatically during GPU pipeline execution."

echo
echo "Installation complete."
echo
echo "Host requirements:"
echo "  - Docker"
echo "  - WSL2 (Windows only)"
echo
echo "All tools are containerized."
