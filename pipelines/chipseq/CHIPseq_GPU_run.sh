#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(realpath "$PROJECT_DIR/../..")"
PROJECT_NAME="$1"
FASTQ_PATH="$2"
SAMPLESHEET="$3"

# REF_DIR and RESULTS_DIR are required and must be set by the caller
if [[ -z "$REF_DIR" ]]; then
    echo "ERROR: REF_DIR is not set."
    exit 1
fi
if [[ -z "$RESULTS_DIR" ]]; then
    echo "ERROR: RESULTS_DIR is not set."
    exit 1
fi
REF_NAME="${REF_NAME:-reference}"
REF_FASTA="$REF_NAME.fasta"

if [[ ! -f "$REF_DIR/$REF_FASTA" ]]; then
    if [[ -f "$REF_DIR/$REF_NAME.fa" ]]; then
        REF_FASTA="$REF_NAME.fa"
    else
        echo "ERROR: $REF_FASTA or $REF_NAME.fa not found in $REF_DIR"
        exit 1
    fi
fi

echo "============================================"
echo " CHIP-SEQ GPU PIPELINE"
echo "============================================"
echo " Reads     : $FASTQ_PATH"
echo " Reference : $REF_DIR"
echo " Results   : $RESULTS_DIR/$PROJECT_NAME/"
echo "============================================"
echo ""

mkdir -p "$RESULTS_DIR/$PROJECT_NAME"

cd "$PROJECT_DIR"

if [[ -n "${MAX_MEM_GB:-}" && "$MAX_MEM_GB" -gt 0 ]]; then
    MEM_GB=$MAX_MEM_GB
else
    MEM_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    MEM_GB=$(( MEM_KB / 1024 / 1024 ))
    if [ "$MEM_GB" -gt 64 ]; then MEM_GB=64; fi
fi

if [[ -n "${MAX_CPUS:-}" && "$MAX_CPUS" -gt 0 ]]; then
    CPU_COUNT=$MAX_CPUS
else
    CPU_COUNT=$(nproc)
fi

FASTQC_CPUS=$CPU_COUNT
FASTP_CPUS=$CPU_COUNT
FQ2BAM_CPUS=$CPU_COUNT
MACS2_CPUS=$CPU_COUNT

FASTQC_MEM="$(( MEM_GB * 100 / 100 ))"
[ "$FASTQC_MEM" -lt 2 ] && FASTQC_MEM=2

FASTP_MEM="$(( MEM_GB * 100 / 100 ))"
[ "$FASTP_MEM" -lt 4 ] && FASTP_MEM=4

FQ2BAM_MEM="$(( MEM_GB * 60 / 100 ))"
[ "$FQ2BAM_MEM" -lt 8 ] && FQ2BAM_MEM=8

MACS2_MEM="$(( MEM_GB * 30 / 100 ))"
[ "$MACS2_MEM" -lt 4 ] && MACS2_MEM=4

FASTQC_MEM="${FASTQC_MEM} GB"
FASTP_MEM="${FASTP_MEM} GB"
FQ2BAM_MEM="${FQ2BAM_MEM} GB"
MACS2_MEM="${MACS2_MEM} GB"

MOUNTS=(
    -v "$APP_ROOT":"$APP_ROOT"
    -v "$FASTQ_PATH":"$FASTQ_PATH"
    -v "$REF_DIR":"$REF_DIR"
    -v "$RESULTS_DIR":"$RESULTS_DIR"
)

# Determine input args (samplesheet vs reads)
if [[ -n "$SAMPLESHEET" && -f "$SAMPLESHEET" ]]; then
    echo "INFO: Using samplesheet $SAMPLESHEET"
    INPUT_ARGS="--samplesheet $SAMPLESHEET"
    MOUNTS+=(-v "$SAMPLESHEET":"$SAMPLESHEET")
else
    echo "INFO: No samplesheet provided, using raw fastq pairs"
    INPUT_ARGS="--reads $FASTQ_PATH/*_R{1,2}.fastq.gz"
fi

echo "DEBUG MOUNTS = ${MOUNTS[@]}" >&2
echo "DEBUG PROJECT_DIR = $PROJECT_DIR" >&2

docker run --rm \
    "${MOUNTS[@]}" \
    -w "$PROJECT_DIR" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -e NXF_DOCKER_LEGACY=true \
    nextflow/nextflow:26.04.3 \
    nextflow run CHIPseq_GPU.nf -c CHIPseq_GPU.config \
    -work-dir "$PROJECT_DIR/work" \
    $INPUT_ARGS \
    --reference "$REF_DIR/$REF_FASTA" \
    --outdir "$RESULTS_DIR/$PROJECT_NAME" \
    --project_name "$PROJECT_NAME" \
    --fastqc_cpus "$FASTQC_CPUS" \
    --fastqc_mem "$FASTQC_MEM" \
    --fastp_cpus "$FASTP_CPUS" \
    --fastp_mem "$FASTP_MEM" \
    --fq2bam_cpus "$FQ2BAM_CPUS" \
    --fq2bam_mem "$FQ2BAM_MEM" \
    --macs2_cpus "$MACS2_CPUS" \
    --macs2_mem "$MACS2_MEM" \
    ${LOW_MEMORY:+"--low_memory"} \
    -resume

echo ""
echo "============================================"
echo " Results"
echo "============================================"
echo "MACS2 Peak Calling (per sample):"
ls -lh "$RESULTS_DIR/$PROJECT_NAME/macs2/" 2>/dev/null || echo "  None found"

echo ""
echo "BAM files (per sample):"
ls -lh "$RESULTS_DIR/$PROJECT_NAME/bam/" 2>/dev/null || echo "  None found"

echo ""
echo "Done!"

# Remove old Nextflow work directories (>7 days old)
find "$PROJECT_DIR/work" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    -mtime +7 \
    -exec rm -rf {} +

echo "Old work directories cleaned."
