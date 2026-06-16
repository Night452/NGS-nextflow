#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COHORT_NAME="$1"
FASTQ_PATH="$2"

# REF_DIR and RESULTS_DIR are required and must be set by the caller
# (Germline_CPU_menu.sh prompts for these). No defaults are assumed.
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
echo " GERMLINE CPU VARIANT CALLING PIPELINE"
echo "============================================"
echo " Reads     : $FASTQ_PATH"
echo " Reference : $REF_DIR"
echo " Results   : $RESULTS_DIR/$COHORT_NAME/"
echo "============================================"
echo ""

mkdir -p "$RESULTS_DIR/$COHORT_NAME"

cd "$PROJECT_DIR"

# ── Build reference indexes if missing (BWA + samtools + GATK dict) ───────────
if [[ "${SKIP_INDEXING:-0}" == "1" ]]; then
    echo "Skipping index check (Pre-built indexes selected in UI)."
    NEED_INDEX=0
else
    NEED_INDEX=0
    DICT_NAME="${REF_NAME}.dict"
    for ext in fai bwt amb ann pac sa; do
        if [[ ! -f "$REF_DIR/${REF_FASTA}.$ext" && ! -f "$REF_DIR/${REF_NAME}.$ext" ]]; then
            NEED_INDEX=1
        fi
    done
    [[ ! -f "$REF_DIR/$DICT_NAME" ]] && NEED_INDEX=1
fi

if [[ "$NEED_INDEX" -eq 1 ]]; then
    echo "Reference indexes missing or incomplete — building now..."
    echo ""

    docker run --rm \
        -u "$(id -u):$(id -g)" \
        -v "$REF_DIR":"$REF_DIR" \
        -w "$REF_DIR" \
        biocontainers/bwa:v0.7.17_cv1 \
        bwa index "$REF_FASTA"

    docker run --rm \
        -u "$(id -u):$(id -g)" \
        -v "$REF_DIR":"$REF_DIR" \
        -w "$REF_DIR" \
        broadinstitute/gatk:4.6.2.0 \
        samtools faidx "$REF_FASTA"

    docker run --rm \
        -u "$(id -u):$(id -g)" \
        -v "$REF_DIR":"$REF_DIR" \
        -w "$REF_DIR" \
        broadinstitute/gatk:4.6.2.0 \
        gatk CreateSequenceDictionary \
            -R "$REF_NAME" \
            -O "$DICT_NAME"

    echo ""
    echo "Reference indexing complete."
    echo ""
fi

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

FASTQC_CPUS=$(( CPU_COUNT * 25 / 100 ))
[ "$FASTQC_CPUS" -lt 2 ] && FASTQC_CPUS=2

BWA_CPUS=$(( CPU_COUNT * 60 / 100 ))
[ "$BWA_CPUS" -lt 4 ] && BWA_CPUS=4

SORT_CPUS=$(( CPU_COUNT * 40 / 100 ))
[ "$SORT_CPUS" -lt 2 ] && SORT_CPUS=2

MARKDUP_CPUS=$SORT_CPUS

HC_CPUS=$(( CPU_COUNT * 60 / 100 ))
[ "$HC_CPUS" -lt 4 ] && HC_CPUS=4

GENO_CPUS=$(( CPU_COUNT * 25 / 100 ))
[ "$GENO_CPUS" -lt 2 ] && GENO_CPUS=2

VARFILT_CPUS=2
PASSVCF_CPUS=1

FASTQC_MEM="$(( MEM_GB * 10 / 100 ))"
[ "$FASTQC_MEM" -lt 2 ] && FASTQC_MEM=2

BWA_MEM="$(( MEM_GB * 40 / 100 ))"
[ "$BWA_MEM" -lt 8 ] && BWA_MEM=8

SORT_MEM="$(( MEM_GB * 20 / 100 ))"
[ "$SORT_MEM" -lt 4 ] && SORT_MEM=4

MARKDUP_MEM="$(( MEM_GB * 20 / 100 ))"
[ "$MARKDUP_MEM" -lt 4 ] && MARKDUP_MEM=4

HC_MEM="$(( MEM_GB * 40 / 100 ))"
[ "$HC_MEM" -lt 8 ] && HC_MEM=8

GENO_MEM="$(( MEM_GB * 20 / 100 ))"
[ "$GENO_MEM" -lt 4 ] && GENO_MEM=4

VARFILT_MEM="$(( MEM_GB * 10 / 100 ))"
[ "$VARFILT_MEM" -lt 4 ] && VARFILT_MEM=4

PASSVCF_MEM="$(( MEM_GB * 5 / 100 ))"
[ "$PASSVCF_MEM" -lt 2 ] && PASSVCF_MEM=2

FASTQC_MEM="${FASTQC_MEM} GB"
BWA_MEM="${BWA_MEM} GB"
SORT_MEM="${SORT_MEM} GB"
MARKDUP_MEM="${MARKDUP_MEM} GB"
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

docker run --rm \
    "${MOUNTS[@]}" \
    -w "$PROJECT_DIR" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -e NXF_DOCKER_LEGACY=true \
    nextflow/nextflow:26.04.3 \
    nextflow run Germline_CPU.nf -c Germline_CPU.config \
    --reads "${FASTQ_PATH}/*_R{1,2}.fastq.gz" \
    --reference "$REF_DIR/$REF_FASTA" \
    --outdir "$RESULTS_DIR/$COHORT_NAME" \
    --cohort_name "$COHORT_NAME" \
    --fastqc_cpus "$FASTQC_CPUS" \
    --fastqc_mem "$FASTQC_MEM" \
    --bwa_cpus "$BWA_CPUS" \
    --bwa_mem "$BWA_MEM" \
    --sort_cpus "$SORT_CPUS" \
    --sort_mem "$SORT_MEM" \
    --markdup_cpus "$MARKDUP_CPUS" \
    --markdup_mem "$MARKDUP_MEM" \
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
RAW=$(zgrep -vc "^#" "$RESULTS_DIR/$COHORT_NAME/vcf/${COHORT_NAME}.vcf.gz" 2>/dev/null || echo "0")
PASS=$(zgrep -vc "^#" "$RESULTS_DIR/$COHORT_NAME/vcf/${COHORT_NAME}.pass.vcf.gz" 2>/dev/null || echo "0")
echo "  Raw variants  : $RAW"
echo "  PASS variants : $PASS"
echo ""

# Remove old Nextflow work directories (>7 days old)
find "$PROJECT_DIR/../../work" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    -mtime +7 \
    -exec rm -rf {} + 2>/dev/null

echo "Old work directories cleaned."

echo ""
echo "Done!"
