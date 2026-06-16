# Germline Variant Calling Pipeline (CPU)

CPU-only germline variant calling pipeline using Nextflow DSL2, BWA, and
GATK. Supports single-sample and multi-sample cohort calling.

```
FastQC -> BWA-MEM -> Sort -> MarkDuplicates -> Index -> HaplotypeCaller -> GenotypeGVCFs -> FilterVCF -> PASS VCF
```

## Requirements

- Linux or WSL2 with Docker installed
- Internet access to pull Docker images
- A reference genome (UCSC hg38 naming: chr1, chr2, ... chrM):
  - `reference.fasta`

  The following are built automatically on first run if missing:
  - `reference.fasta.fai`
  - `reference.dict`
  - `reference.fasta.bwt` / `.amb` / `.ann` / `.pac` / `.sa`

## Files

| File | Purpose |
|---|---|
| `Germline_CPU.nf` | Nextflow DSL2 pipeline definition |
| `Germline_CPU.config` | Docker + resource configuration |
| `Germline_CPU_run.sh` | Core launcher — runs Nextflow inside Docker |
| `Germline_CPU_menu.sh` | Interactive menu (cohort name, FASTQ folder, validation) |
| `Germline_CPU_install.sh` | One-time setup — pulls Docker images |

## Installation

```bash
# 1. Run the installer (pulls Docker images)
bash Germline_CPU_install.sh

# 2. Copy pipeline files into the project directory
cp Germline_CPU.nf Germline_CPU.config Germline_CPU_run.sh Germline_CPU_menu.sh ~/nextflow-project-cpu/

# 3. Place reference genome
cp /path/to/reference.fasta ~/nextflow-project-cpu/data/ref/

# 4. Place FASTQ files (any folder you like)
cp /path/to/*_R1.fastq.gz /path/to/*_R2.fastq.gz ~/nextflow-project-cpu/data/raw/
```

## Running

```bash
cd ~/nextflow-project-cpu
bash Germline_CPU_menu.sh
```

You'll be prompted for:
1. Cohort name (used to label output files and folders)
2. Reference folder path
3. FASTQ folder path

If `reference.fasta.fai`, `reference.dict`, or the BWA index files are
missing from the reference folder, they will be built automatically before
the pipeline runs.

Results are written to `~/nextflow-project-cpu/results/<cohort_name>/`:
- `fastqc/` — QC reports
- `bam/` — aligned, sorted, deduplicated BAMs
- `gvcf/` — per-sample GVCFs
- `vcf/` — `<cohort_name>.vcf.gz`, `<cohort_name>.filtered.vcf.gz`, and `<cohort_name>.pass.vcf.gz`

## Custom data locations

To use a reference or output folder outside the project directory:

```bash
REF_DIR=/mnt/d/NextFlow/data/ref \
RESULTS_DIR=/mnt/d/NextFlow/results \
bash Germline_CPU_run.sh my_cohort /mnt/d/NextFlow/data/raw
```

## Clearing cache

If a run fails partway through and `-resume` keeps reusing broken results:

```bash
sudo rm -rf ~/nextflow-project-cpu/work
```
