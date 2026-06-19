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
echo " GERMLINE VARIANT CALLING PIPELINE"
echo "============================================"
echo " Reads     : $FASTQ_PATH"
echo " Reference : $REF_DIR"
echo " Results   : $RESULTS_DIR/$COHORT_NAME/"
echo "============================================"
echo ""

# Pre-flight GPU checks
if ! command -v nvidia-smi &> /dev/null; then
    echo "ERROR: nvidia-smi not found. This pipeline requires an NVIDIA GPU."
    echo "If you do not have an NVIDIA GPU, please use the CPU version of this pipeline."
    exit 1
fi

if ! docker info 2>/dev/null | grep -iq "Runtimes.*nvidia"; then
    echo "ERROR: NVIDIA Container Toolkit is not installed or configured in Docker."
    echo "Please install 'nvidia-container-toolkit' so Docker can access your GPU."
    exit 1
fi

# Auto-detect VRAM to prevent Out-Of-Memory (OOM) crashes
VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 || echo "")
if [[ "$VRAM_MB" =~ ^[0-9]+$ ]] && [ "$VRAM_MB" -lt 16000 ]; then
    echo "WARNING: GPU VRAM is less than 16GB (${VRAM_MB} MB detected)."
    echo "Automatically forcing Low Memory Mode to prevent crashes."
    export LOW_MEMORY="1"
elif [[ ! "$VRAM_MB" =~ ^[0-9]+$ ]]; then
    echo "WARNING: Could not detect GPU VRAM. Assuming standard capacity."
fi

# Auto-detect total host GPUs for accurate Nextflow scheduling
NUM_GPUS=$(nvidia-smi -L 2>/dev/null | wc -l || echo "1")
if ! [[ "$NUM_GPUS" =~ ^[0-9]+$ ]] || [ "$NUM_GPUS" -lt 1 ]; then
    NUM_GPUS=1
fi

# Parabricks Auto Mode requires ~50GB of System RAM per concurrent fq2bam process.
# We must cap NUM_GPUS to physical RAM capacity to prevent OOM crashes on multi-GPU systems.
if command -v awk &> /dev/null && [ -f /proc/meminfo ]; then
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_GB=$(( TOTAL_RAM_KB / 1024 / 1024 ))
    ALLOWED_GPUS=$(( TOTAL_RAM_GB / 50 ))
    [ "$ALLOWED_GPUS" -lt 1 ] && ALLOWED_GPUS=1
    
    if [ "$NUM_GPUS" -gt "$ALLOWED_GPUS" ]; then
        echo "WARNING: System RAM (${TOTAL_RAM_GB}GB) is insufficient to run ${NUM_GPUS} concurrent Parabricks tasks."
        echo "Capping concurrent GPUs to ${ALLOWED_GPUS} to prevent System OOM crashes."
        NUM_GPUS=$ALLOWED_GPUS
    fi
fi

mkdir -p "$RESULTS_DIR/$COHORT_NAME"

APP_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
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


MOUNTS=(
    -v "$APP_ROOT":"$APP_ROOT"
    -v "$FASTQ_PATH":"$FASTQ_PATH"
    -v "$REF_DIR":"$REF_DIR"
    -v "$RESULTS_DIR":"$RESULTS_DIR"
)

echo "DEBUG MOUNTS = ${MOUNTS[@]}" >&2
echo "DEBUG PROJECT_DIR = $PROJECT_DIR" >&2
ls -la "$PROJECT_DIR/Germline_pipeline.nf" >&2
docker run --rm \
    "${MOUNTS[@]}" \
    -w "$PROJECT_DIR" \
    --gpus all \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -e NXF_DOCKER_LEGACY=true \
    nextflow/nextflow:26.04.3 \
    nextflow run Germline_pipeline.nf -c Germline_pipeline.config \
    -work-dir "$RESULTS_DIR/$COHORT_NAME/work" \
    --reads "${FASTQ_PATH}/*_R{1,2}.fastq.gz" \
    --reference "$REF_DIR/$REF_FASTA" \
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
    --num_gpus "$NUM_GPUS" \
    ${LOW_MEMORY:+"--low_memory"} \
    -resume

# Restore ownership of output files from root to the host user
echo "Restoring file permissions..."
docker run --rm -v "$RESULTS_DIR":"$RESULTS_DIR" alpine chown -R $(id -u):$(id -g) "$RESULTS_DIR/$COHORT_NAME"

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
find "$RESULTS_DIR/$COHORT_NAME/work" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    -mtime +7 \
    -exec rm -rf {} +

echo "Old work directories cleaned."

echo ""
echo "Done!"
