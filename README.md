# Nextflow Germline Variant Calling Pipeline

This project provides a containerized, Nextflow-based bioinformatics pipeline for **Germline Variant Calling**. It is designed to take raw paired-end FASTQ reads and process them through to a filtered, high-quality cohort VCF. 

The pipeline supports two execution modes:
1. **CPU-only execution**: Utilizes standard open-source tools (BWA, GATK, FastQC, BCFtools).
2. **GPU-accelerated execution**: Utilizes NVIDIA Clara Parabricks for significantly faster processing.

All dependencies are containerized via Docker, ensuring reproducibility and easy deployment.

---

## 🗺️ System Map & Script Interactions

The following map illustrates how the various shell scripts and Nextflow scripts interact with one another across the project.

```mermaid
graph TD
    User([User])

    subgraph "Setup & Maintenance"
        install[install.sh]
        cleanup[cleanup.sh]
    end

    subgraph "CPU Pipeline (pipelines/germline_cpu)"
        cpu_run[Germline_CPU_run.sh]
        cpu_nf[Germline_CPU.nf]
        cpu_config[Germline_CPU.config]
        cpu_menu[Germline_CPU_menu.sh]
    end

    subgraph "GPU Pipeline (pipelines/germline_gpu)"
        gpu_run[Germline_pipeline_run.sh]
        gpu_nf[Germline_pipeline.nf]
        gpu_config[Germline_pipeline.config]
        gpu_menu[Germline_pipeline_menu.sh]
    end

    %% Interactions
    User -->|Runs| install
    User -->|Runs| cleanup
    
    User -->|Runs| cpu_menu
    cpu_menu -->|Invokes| cpu_run
    User -->|Runs| cpu_run
    cpu_run -->|Executes| cpu_nf
    cpu_nf -.->|Uses| cpu_config
    
    User -->|Runs| gpu_menu
    gpu_menu -->|Invokes| gpu_run
    User -->|Runs| gpu_run
    gpu_run -->|Executes| gpu_nf
    gpu_nf -.->|Uses| gpu_config

    %% Descriptions
    classDef default fill:#808080,stroke:#333,stroke-width:2px,color:#ffffff,font-weight:bold;
    classDef script fill:#808080,stroke:#333,stroke-width:2px,color:#ffffff,font-weight:bold;
    classDef nf fill:#808080,stroke:#333,stroke-width:2px,color:#ffffff,font-weight:bold;
    
    class install,cleanup,cpu_run,gpu_run,cpu_menu,gpu_menu script;
    class cpu_nf,gpu_nf,cpu_config,gpu_config nf;
```

## 📁 Project Structure

```text
Nextflow/
├── README.md                 # Project documentation
├── install.sh                # Installation script
├── cleanup.sh                # Cleanup utility script
├── Data/                     # Default data directory
│   ├── Raw/                  # FastQ files go here
│   └── Ref/                  # Reference genomes go here
├── interface/                # Graphical & Terminal Interfaces
│   ├── gui.py                # PySide6 Desktop GUI
│   ├── main_menu.sh          # Terminal Wizard interface
│   └── requirements.txt      # GUI Python dependencies
├── pipelines/                
│   ├── germline_cpu/         # CPU-only (BWA/GATK) pipeline scripts
│   │   ├── Germline_CPU.config
│   │   ├── Germline_CPU.nf
│   │   ├── Germline_CPU_menu.sh
│   │   ├── Germline_CPU_reference_builder.sh
│   │   └── Germline_CPU_run.sh
│   └── germline_gpu/         # GPU-accelerated (Parabricks) pipeline scripts
│       ├── Germline_pipeline.config
│       ├── Germline_pipeline.nf
│       ├── Germline_pipeline_menu.sh
│       └── Germline_pipeline_run.sh
├── results/                  # Pipeline outputs (BAMs, VCFs)
└── work/                     # Nextflow intermediate working directory
```

### Script Directory

- **`install.sh`**: Global installation script. Creates required directories (`Data/`, `results/`, `work/`, `logs/`), makes scripts executable, and pulls required Docker container images.
- **`cleanup.sh`**: Maintenance utility to remove old Nextflow work directories, cached data, old logs, and dangling Docker images.
- **`Germline_CPU_run.sh` / `Germline_pipeline_run.sh`**: The core launcher scripts. They validate inputs (FASTQ, reference directories), index references if necessary (CPU only), calculate optimal CPU and memory limits dynamically based on the host system, map the correct Docker volume mounts, and execute the respective Nextflow `.nf` file.
- **`Germline_CPU.nf` / `Germline_pipeline.nf`**: The Nextflow DSL2 workflows orchestrating the bioinformatics tools.

---

## ⚙️ Pipeline Flowcharts

These flowcharts break down exactly what each Nextflow script (`.nf`) does under the hood to process the bioinformatics pipeline.

### 1. CPU Pipeline (`Germline_CPU.nf`)
This pipeline relies on traditional CPU tools: **FastQC**, **BWA**, and **GATK 4**.

```mermaid
graph TD
    %% Inputs
    Reads[/Raw FASTQ Reads/]
    Ref[/Reference Genome .fasta/]
    
    %% Processes
    FASTQC[FastQC: Quality Control]
    BWA[BWA_ALIGN: Read Alignment]
    SORT[SORT_BAM: Sort Alignments]
    MARKDUP[MARK_DUPLICATES: Tag Duplicates]
    INDEX[INDEX_BAM: Index BAM File]
    HC[HAPLOTYPE_CALLER: Call Variants per Sample]
    GENO[GENOTYPE_GVCFS: Joint Genotyping]
    FILT[VARIANT_FILTRATION: Hard Filtering]
    PASS[PASS_VCF: Extract PASS Variants]
    
    %% Outputs
    QC_OUT[/QC Reports/]
    BAM_OUT[/Processed BAMs/]
    GVCF_OUT[/Sample gVCFs/]
    VCF_OUT[/Cohort VCF/]
    FINAL_VCF[/Filtered PASS VCF/]

    %% Flow
    Reads --> FASTQC
    FASTQC --> QC_OUT
    
    Reads --> BWA
    Ref --> BWA
    BWA --> SORT
    SORT --> MARKDUP
    MARKDUP --> INDEX
    INDEX --> BAM_OUT
    
    INDEX --> HC
    Ref --> HC
    HC --> GVCF_OUT
    
    GVCF_OUT --> GENO
    Ref --> GENO
    GENO --> VCF_OUT
    
    VCF_OUT --> FILT
    Ref --> FILT
    FILT --> PASS
    PASS --> FINAL_VCF
    
    %% Styling
    classDef default fill:#808080,stroke:#333,stroke-width:2px,color:#ffffff,font-weight:bold;
    classDef process fill:#808080,stroke:#333,stroke-width:2px,color:#ffffff,font-weight:bold;
    class FASTQC,BWA,SORT,MARKDUP,INDEX,HC,GENO,FILT,PASS process;
```

### 2. GPU Pipeline (`Germline_pipeline.nf`)
This pipeline utilizes **NVIDIA Clara Parabricks** to significantly accelerate standard steps (FQ2BAM replaces BWA + Sorting + MarkDuplicates).

```mermaid
graph TD
    %% Inputs
    Reads[/Raw FASTQ Reads/]
    Ref[/Reference Genome .fasta/]
    
    %% Processes
    FASTQC[FastQC: Quality Control]
    FQ2BAM[FQ2BAM: GPU Align, Sort & MarkDup]
    HC[HAPLOTYPE_CALLER: GPU Variant Calling]
    GENO[GENOTYPE_GVCFS: GPU Joint Genotyping]
    FILT[VARIANT_FILTRATION: GATK Hard Filtering]
    PASS[PASS_VCF: bcftools Extract PASS]
    
    %% Outputs
    QC_OUT[/QC Reports/]
    BAM_OUT[/Processed BAMs/]
    GVCF_OUT[/Sample gVCFs/]
    VCF_OUT[/Cohort VCF/]
    FINAL_VCF[/Filtered PASS VCF/]

    %% Flow
    Reads --> FASTQC
    FASTQC --> QC_OUT
    
    Reads --> FQ2BAM
    Ref --> FQ2BAM
    FQ2BAM --> BAM_OUT
    
    FQ2BAM --> HC
    Ref --> HC
    HC --> GVCF_OUT
    
    GVCF_OUT --> GENO
    Ref --> GENO
    GENO --> VCF_OUT
    
    VCF_OUT --> FILT
    Ref --> FILT
    FILT --> PASS
    PASS --> FINAL_VCF
    
    %% Styling
    classDef default fill:#808080,stroke:#333,stroke-width:2px,color:#ffffff,font-weight:bold;
    classDef process fill:#808080,stroke:#333,stroke-width:2px,color:#ffffff,font-weight:bold;
    class FASTQC,FQ2BAM,HC,GENO,FILT,PASS process;
```

---

## 🚀 How to Run

1. **Install dependencies**:
   ```bash
   ./install.sh
   ```
2. **Execute a Pipeline**:
   Navigate to the respective pipeline directory and execute the run script:
   ```bash
   # CPU Pipeline
   cd pipelines/germline_cpu
   ./Germline_CPU_run.sh <cohort_name> <path_to_fastqs>

   # GPU Pipeline
   cd pipelines/germline_gpu
   ./Germline_pipeline_run.sh <cohort_name> <path_to_fastqs>
   ```
   *(Ensure `REF_DIR` and `RESULTS_DIR` environment variables are set or use the interactive menu scripts).*

3. **Cleanup**:
   ```bash
   ./cleanup.sh
   ```
