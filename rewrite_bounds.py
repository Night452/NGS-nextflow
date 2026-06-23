import os
import re

def process_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()
        
    # We want to replace the resource bounding block.
    # From 'if [[ -n "${MAX_MEM_GB:-}"' to 'MOUNTS=('
    
    match = re.search(r'(if \[\[ -n "\$\{MAX_MEM_GB:-\}" && "\$MAX_MEM_GB" -gt 0 \]\]; then.*?)\n(MOUNTS=\()', content, re.DOTALL)
    if not match:
        print(f"Could not find block in {filepath}")
        return
        
    block = match.group(1)
    
    # Analyze all variables
    # Format of block: 
    # FASTQC_CPUS=$(( CPU_COUNT * 25 / 100 ))
    # [ "$FASTQC_CPUS" -lt 2 ] && FASTQC_CPUS=2
    
    # FQ2BAM_MEM="$(( MEM_GB * 60 / 100 ))"
    # [ "$FQ2BAM_MEM" -lt 8 ] && FQ2BAM_MEM=8
    
    new_block = """if [[ -n "${MAX_MEM_GB:-}" && "$MAX_MEM_GB" -gt 0 ]]; then
    MEM_GB=$MAX_MEM_GB
else
    MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    MEM_GB=$(( MEM_KB / 1024 / 1024 ))
    if [ "$MEM_GB" -gt 64 ]; then MEM_GB=64; fi
fi

if [[ -n "${MAX_CPUS:-}" && "$MAX_CPUS" -gt 0 ]]; then
    CPU_COUNT=$MAX_CPUS
else
    CPU_COUNT=$(nproc)
fi

clamp_cpu() {
    local val=$1
    local min=$2
    [ "$val" -lt "$min" ] && val=$min
    [ "$val" -gt "$CPU_COUNT" ] && val=$CPU_COUNT
    echo "$val"
}

clamp_mem() {
    local val=$1
    local min=$2
    [ "$val" -lt "$min" ] && val=$min
    [ "$val" -gt "$MEM_GB" ] && val=$MEM_GB
    echo "$val"
}

"""
    lines = block.split('\n')
    
    # Process line by line to extract definitions
    # Actually, the logic in the GPU pipeline is: FASTQC_CPUS=$CPU_COUNT
    # CPU pipelines have $(((CPU_COUNT * 25 / 100)))
    
    for i in range(len(lines)):
        line = lines[i].strip()
        if not line: continue
        
        # Match CPU assignment
        m = re.match(r'^([A-Z0-9_]+_CPUS)=(.*)$', line)
        if m:
            var = m.group(1)
            val = m.group(2)
            
            # Look ahead for min value
            min_val = "1"
            if i + 1 < len(lines):
                m_min = re.search(fr'\[ "\${var}" -lt (\d+) \]', lines[i+1])
                if m_min:
                    min_val = m_min.group(1)
                    lines[i+1] = "" # Blank it out
            
            # Now output the clamped version
            if val == "$CPU_COUNT":
                new_block += f"{var}=$(clamp_cpu $CPU_COUNT {min_val})\n"
            else:
                new_block += f"{var}=$(clamp_cpu {val} {min_val})\n"
            continue
            
        # Match MEM assignment (ignoring the " GB" string additions at the end)
        m = re.match(r'^([A-Z0-9_]+_MEM)="\$\(\( MEM_GB \* (\d+) / 100 \)\)"$', line)
        if m:
            var = m.group(1)
            pct = m.group(2)
            
            min_val = "1"
            if i + 1 < len(lines):
                m_min = re.search(fr'\[ "\${var}" -lt (\d+) \]', lines[i+1])
                if m_min:
                    min_val = m_min.group(1)
                    lines[i+1] = ""
                    
            new_block += f"{var}=$(clamp_mem $(( MEM_GB * {pct} / 100 )) {min_val})\n"
            continue
            
        # Handle string appends
        if re.match(r'^[A-Z0-9_]+_MEM="\$\{[A-Z0-9_]+_MEM\} GB"$', line):
            new_block += f"{line}\n"
            continue
            
    # Write back
    content = content.replace(block, new_block)
    with open(filepath, 'w') as f:
        f.write(content)
        
    print(f"Processed {filepath}")

base_dir = "/mnt/1E0E3E6E0E3E3ED9/NextFlow/NGS-nextflow/pipelines"
files = [
    "germline_cpu/Germline_CPU_run.sh",
    "germline_gpu/Germline_pipeline_run.sh",
    "chipseq/CHIPseq_GPU_run.sh",
    "chipseq_cpu/CHIPseq_CPU_run.sh"
]

for file in files:
    process_file(os.path.join(base_dir, file))
