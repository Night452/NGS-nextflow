#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(realpath "$PROJECT_DIR/../..")"
COHORT_NAME="$1"
FASTQ_PATH="$2"

# REF_DIR and RESULTS_DIR are required and must be set by the caller
# (run_pipeline_linux.sh prompts for these). No defaults are assumed.
if [[ -z "$REF_DIR" ]]; then
    echo "ERROR: REF_DIR is not set."
    exit 1
fi
if [[ -z "$RESULTS_DIR" ]]; then
    echo "ERROR: RESULTS_DIR is not set."
    exit 1
fi
if [[ ! -f "$REF_DIR/reference.fasta" ]]; then
    echo "ERROR: reference.fasta not found in $REF_DIR"
    exit 1
fi

echo "============================================"
echo " GERMLINE VARIANT CALLING PIPELINE"
echo "============================================"
echo " Reads     : $FASTQ_PATH"
echo " Reference : $REF_DIR"
echo " Results   : $RESULTS_DIR/$COHORT_NAME/"
echo "============================================"
echo ""

mkdir -p "$RESULTS_DIR/$COHORT_NAME"

cd "$PROJECT_DIR"

MEM_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
MEM_GB=$(( MEM_KB / 1024 / 1024 ))

MAX_MEM_GB=64

if [ "$MEM_GB" -gt "$MAX_MEM_GB" ]; then
    MEM_GB=$MAX_MEM_GB
fi

CPU_COUNT=$(nproc)

FASTQC_CPUS=$CPU_COUNT
FQ2BAM_CPUS=$CPU_COUNT
HC_CPUS=$CPU_COUNT
GENO_CPUS=$CPU_COUNT
VARFILT_CPUS=2
PASSVCF_CPUS=1

FASTQC_MEM="$(( MEM_GB * 100 / 100 ))"
[ "$FASTQC_MEM" -lt 2 ] && FASTQC_MEM=2

FQ2BAM_MEM="$(( MEM_GB * 60 / 100 ))"
[ "$FQ2BAM_MEM" -lt 8 ] && FQ2BAM_MEM=8

HC_MEM="$(( MEM_GB * 60 / 100 ))"
[ "$HC_MEM" -lt 8 ] && HC_MEM=8

GENO_MEM="$(( MEM_GB * 30 / 100 ))"
[ "$GENO_MEM" -lt 4 ] && GENO_MEM=4

VARFILT_MEM="$(( MEM_GB * 10 / 100 ))"
[ "$VARFILT_MEM" -lt 4 ] && VARFILT_MEM=4

PASSVCF_MEM="$(( MEM_GB * 5 / 100 ))"
[ "$PASSVCF_MEM" -lt 2 ] && PASSVCF_MEM=2

FASTQC_MEM="${FASTQC_MEM} GB"
FQ2BAM_MEM="${FQ2BAM_MEM} GB"
HC_MEM="${HC_MEM} GB"
GENO_MEM="${GENO_MEM} GB"
VARFILT_MEM="${VARFILT_MEM} GB"
PASSVCF_MEM="${PASSVCF_MEM} GB"


MOUNTS=()
SEEN_TOPS=()
for d in "$PROJECT_DIR" "$FASTQ_PATH" "$REF_DIR" "$RESULTS_DIR"; do
    top="/$(echo "$d" | cut -d/ -f2)"   # e.g. /mnt, /home, /data
    already_seen=0
    for s in "${SEEN_TOPS[@]}"; do
        [[ "$s" == "$top" ]] && already_seen=1 && break
    done
    if [[ "$already_seen" -eq 0 ]]; then
        MOUNTS+=(-v "$top":"$top")
        SEEN_TOPS+=("$top")
    fi
done

echo "DEBUG MOUNTS = ${MOUNTS[@]}" >&2
echo "DEBUG PROJECT_DIR = $PROJECT_DIR" >&2
ls -la "$PROJECT_DIR/Germline_pipeline.nf" >&2
docker run --rm \
    "${MOUNTS[@]}" \
    -w "$PROJECT_DIR" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -e NXF_DOCKER_LEGACY=true \
    nextflow/nextflow:26.04.3 \
    nextflow run Germline_pipeline.nf -c Germline_pipeline.config \
    --reads "${FASTQ_PATH}/*_R{1,2}.fastq.gz" \
    --reference "$REF_DIR/reference.fasta" \
    --outdir "$RESULTS_DIR/$COHORT_NAME" \
    --cohort_name "$COHORT_NAME" \
    --fastqc_cpus "$FASTQC_CPUS" \
    --fastqc_mem "$FASTQC_MEM" \
    --fq2bam_cpus "$FQ2BAM_CPUS" \
    --fq2bam_mem "$FQ2BAM_MEM" \
    --hc_cpus "$HC_CPUS" \
    --hc_mem "$HC_MEM" \
    --geno_cpus "$GENO_CPUS" \
    --geno_mem "$GENO_MEM" \
    --varfilt_cpus "$VARFILT_CPUS" \
    --varfilt_mem "$VARFILT_MEM" \
    --passvcf_cpus "$PASSVCF_CPUS" \
    --passvcf_mem "$PASSVCF_MEM" \
    -resume

echo ""
echo "============================================"
echo " Results"
echo "============================================"
echo "GVCFs (per sample):"
ls -lh "$RESULTS_DIR/$COHORT_NAME/gvcf/" 2>/dev/null || echo "  None found"

echo ""
echo "VCFs (cohort):"
ls -lh "$RESULTS_DIR/$COHORT_NAME/vcf/" 2>/dev/null || echo "  None found"

echo ""
echo "Variant counts:"
RAW=$(grep -vc "^#" "$RESULTS_DIR/$COHORT_NAME/vcf/${COHORT_NAME}.vcf" 2>/dev/null || echo "0")
PASS=$(grep -vc "^#" "$RESULTS_DIR/$COHORT_NAME/vcf/${COHORT_NAME}.pass.vcf" 2>/dev/null || echo "0")
echo "  Raw variants  : $RAW"
echo "  PASS variants : $PASS"
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

echo ""
echo "Done!"
