#!/usr/bin/env nextflow

/*
 * Germline Variant Calling Pipeline — NVIDIA Parabricks (GPU-accelerated)
 * Supports single-sample and cohort calling
 * Steps: FastQC → fq2bam → HaplotypeCaller (GVCF) → GenotypeGVCFs → Filtered VCF → PASS VCF
 */

nextflow.enable.dsl = 2

// ── Parameters ───────────────────────────────────────────────────────────────
// No default paths. --reads, --reference and --outdir are REQUIRED and must
// be supplied relative to the current working directory (run_pipeline.sh
// prompts for these and passes them in). This keeps the pipeline portable —
// no machine-specific paths are baked in anywhere.
params.cohort_name      = "cohort"
params.reads            = null
params.reference        = null
params.outdir           = null
params.parabricks_image = "nvcr.io/nvidia/clara/clara-parabricks:4.7.0-1"

// ── Process 1: FastQC ─────────────────────────────────────────────────────────
process FASTQC {
    tag "$sample_id"
    publishDir "${params.outdir}/fastqc", mode: 'copy'
    container 'biocontainers/fastqc:v0.11.9_cv8'
    errorStrategy 'retry'
    maxRetries 2

    input:
    tuple val(sample_id), path(reads)

    output:
    tuple val(sample_id), path("*.html"), emit: html
    tuple val(sample_id), path("*.zip"),  emit: zip

    script:
    """
    echo "INFO: Running FastQC for ${sample_id}"
    fastqc ${reads[0]} ${reads[1]} \\
        --threads ${task.cpus} \\
        --outdir .
    """
}

// ── Process 2: fq2bam (GPU) ───────────────────────────────────────────────────
process FQ2BAM {
    tag "$sample_id"
    publishDir "${params.outdir}/bam", mode: 'copy'
    container params.parabricks_image
    accelerator 1, type: 'nvidia.com/gpu'
    errorStrategy 'retry'
    maxRetries 1

    input:
    tuple val(sample_id), path(reads)
    path reference
    path ref_fai
    path ref_dict

    output:
    tuple val(sample_id),
          path("${sample_id}.bam"),
          path("${sample_id}.bam.bai"), emit: bam_bai

    script:
    def rg = "@RG\\tID:${sample_id}\\tSM:${sample_id}\\tPL:ILLUMINA\\tLB:lib1\\tPU:unit1"
    """
    echo "INFO: fq2bam for ${sample_id}"

    pbrun fq2bam \\
        --ref ${reference} \\
        --in-fq ${reads[0]} ${reads[1]} "${rg}" \\
        --out-bam ${sample_id}.bam \\
        --num-gpus 1

    [ -s "${sample_id}.bam" ] || { echo "ERROR: empty BAM for ${sample_id}"; exit 1; }
    """
}

// ── Process 3: HaplotypeCaller (GPU) — per-sample GVCF ───────────────────────
process HAPLOTYPE_CALLER {
    tag "$sample_id"
    publishDir "${params.outdir}/gvcf", mode: 'copy'
    container params.parabricks_image
    accelerator 1, type: 'nvidia.com/gpu'
    errorStrategy 'retry'
    maxRetries 1

    input:
    tuple val(sample_id), path(bam), path(bai)
    path reference
    path ref_fai
    path ref_dict

    output:
    tuple val(sample_id), path("${sample_id}.g.vcf"), emit: gvcf

    script:
    """
    echo "INFO: HaplotypeCaller for ${sample_id}"

    cat > main_chroms.bed << 'EOF'
chr1\t0\t248956422
chr2\t0\t242193529
chr3\t0\t198295559
chr4\t0\t190214555
chr5\t0\t181538259
chr6\t0\t170805979
chr7\t0\t159345973
chr8\t0\t145138636
chr9\t0\t138394717
chr10\t0\t133797422
chr11\t0\t135086622
chr12\t0\t133275309
chr13\t0\t114364328
chr14\t0\t107043718
chr15\t0\t101991189
chr16\t0\t90338345
chr17\t0\t83257441
chr18\t0\t80373285
chr19\t0\t58617616
chr20\t0\t64444167
chr21\t0\t46709983
chr22\t0\t50818468
chrX\t0\t156040895
chrY\t0\t57227415
chrM\t0\t16569
EOF

    pbrun haplotypecaller \\
        --ref ${reference} \\
        --in-bam ${bam} \\
        --out-variants ${sample_id}.g.vcf \\
        --gvcf \\
        --num-gpus 1 \\
        --interval-file main_chroms.bed

    [ -s "${sample_id}.g.vcf" ] || { echo "ERROR: empty GVCF for ${sample_id}"; exit 1; }
    """
}

// ── Process 4: GenotypeGVCFs (GPU) ───────────────────────────────────────────
process GENOTYPE_GVCFS {
    publishDir "${params.outdir}/vcf", mode: 'copy'
    container params.parabricks_image
    errorStrategy 'retry'
    maxRetries 1

    input:
    path gvcfs
    path reference
    path ref_fai
    path ref_dict

    output:
    path "${params.cohort_name}.vcf", emit: cohort_vcf

    script:
    def gvcf_args = (gvcfs instanceof List
        ? gvcfs.collect { "--in-gvcf ${it}" }
        : [ "--in-gvcf ${gvcfs}" ]
    ).join(" \\\n        ")
    """
    echo "INFO: GenotypeGVCFs — joint genotyping"

    pbrun genotypegvcf \\
        --ref ${reference} \\
        ${gvcf_args} \\
        --out-vcf ${params.cohort_name}.vcf

    [ -s "${params.cohort_name}.vcf" ] || { echo "ERROR: empty cohort VCF"; exit 1; }
    """
}

// ── Process 5: Variant Filtration ─────────────────────────────────────────────
process VARIANT_FILTRATION {

    publishDir "${params.outdir}/vcf", mode: 'copy'

    container 'broadinstitute/gatk:4.6.2.0'

    errorStrategy 'retry'
    maxRetries 2

    input:
    path vcf
    path reference
    path ref_fai
    path ref_dict

    output:
    path "${params.cohort_name}.filtered.vcf", emit: filtered_vcf

    script:
    """
    gatk VariantFiltration \
        -R ${reference} \
        -V ${vcf} \
        -O ${params.cohort_name}.filtered.vcf \
        --filter-expression "QD < 2.0" \
        --filter-name "LowQD" \
        --filter-expression "FS > 60.0" \
        --filter-name "StrandBias" \
        --filter-expression "MQ < 40.0" \
        --filter-name "LowMQ"

    [ -s "${params.cohort_name}.filtered.vcf" ] || {
        echo "ERROR: empty filtered VCF"
        exit 1
    }
    """
}


process PASS_VCF {

    publishDir "${params.outdir}/vcf", mode: 'copy'

    container 'biocontainers/bcftools:v1.9-1-deb_cv1'

    errorStrategy 'retry'
    maxRetries 2

    input:
    path filtered_vcf

    output:
    path "${params.cohort_name}.pass.vcf", emit: pass_vcf

    script:
    """
    bcftools view \
        -f PASS \
        ${filtered_vcf} \
        > ${params.cohort_name}.pass.vcf

    PASS_COUNT=\$(grep -vc "^#" ${params.cohort_name}.pass.vcf || true)

    echo "INFO: PASS variants = \${PASS_COUNT}"
    """
}

// ── Workflow ──────────────────────────────────────────────────────────────────
workflow {

    if (!params.reads)
        error "MISSING PARAMETER: --reads '<path>/*_R{1,2}.fastq.gz' is required"
    if (!params.reference)
        error "MISSING PARAMETER: --reference '<path>/reference.fasta' is required"
    if (!params.outdir)
        error "MISSING PARAMETER: --outdir '<path>' is required"

    // FIX: Validation now inside workflow block — DSL2 forbids top-level statements
    def ref      = file(params.reference)
    def ref_fai  = file("${params.reference}.fai")
    def ref_dict = file(
        params.reference.toString()
            .replaceAll(/\.fasta$/, ".dict")
            .replaceAll(/\.fa$/,    ".dict")
    )

    log.info """
    ============================================
     GERMLINE VARIANT CALLING PIPELINE
    ============================================
     reads      : ${params.reads}
     reference  : ${params.reference}
     outdir     : ${params.outdir}
     cohort     : ${params.cohort_name}
    ============================================
    """.stripIndent()

    Channel
        .fromFilePairs(params.reads, checkIfExists: true)
        .set { read_pairs_ch }

    // Per-sample parallel steps
    FASTQC          ( read_pairs_ch )
    FQ2BAM          ( read_pairs_ch, ref, ref_fai, ref_dict )
    HAPLOTYPE_CALLER( FQ2BAM.out.bam_bai, ref, ref_fai, ref_dict )

    // Wait for ALL GVCFs before joint genotyping
    all_gvcfs_ch = HAPLOTYPE_CALLER.out.gvcf
        .map    { sample_id, gvcf -> gvcf }
        .collect()

    // FIX: GENOTYPE_GVCFS was never invoked — added the missing call
    GENOTYPE_GVCFS( all_gvcfs_ch, ref, ref_fai, ref_dict )

   VARIANT_FILTRATION(GENOTYPE_GVCFS.out.cohort_vcf,ref,ref_fai,ref_dict)
    PASS_VCF( VARIANT_FILTRATION.out.filtered_vcf )
}
