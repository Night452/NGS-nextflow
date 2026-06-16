#!/bin/bash
set -e

REFERENCE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"

if [[ ! -f "$REFERENCE" ]]; then
    echo "ERROR: reference not found"
    exit 1
fi

REF_DIR="$(dirname "$REFERENCE")"
REF_NAME="$(basename "$REFERENCE")"


echo ""
echo "Reference:"
echo "$REFERENCE"
echo ""

docker run --rm \
    -u "$(id -u):$(id -g)" \
    -v "$REF_DIR":"$REF_DIR" \
    -w "$REF_DIR" \
    biocontainers/bwa:v0.7.17_cv1 \
    bwa index "$REF_NAME"

docker run --rm \
    -u $(id -u):$(id -g) \
    -v "$REF_DIR":"$REF_DIR" \
    -w "$REF_DIR" \
    broadinstitute/gatk:4.6.2.0 \
    samtools faidx "$REF_NAME"

DICT_NAME="${REF_NAME%.*}.dict"

docker run --rm \
    -u $(id -u):$(id -g) \
    -v "$REF_DIR":"$REF_DIR" \
    -w "$REF_DIR" \
    broadinstitute/gatk:4.6.2.0 \
    gatk CreateSequenceDictionary \
        -R "$REF_NAME" \
        -O "$DICT_NAME"

echo ""
echo "Reference indexing complete."
echo ""


touch "${REFERENCE}.cpu_index_complete"