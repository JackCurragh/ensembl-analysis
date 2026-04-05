#!/usr/bin/env bash
# =============================================================================
# Local end-to-end test: load_assembly + refseq_import
#
# These two pipelines only need network access (NCBI FTP) — no pre-existing
# data files required, so they're the ones we can run in full locally.
#
# Everything else (repeat_masking, rnaseq, best_targeted, projection, ab_initio,
# igtr, long_read, genblast_homology, short_ncrna, consolidate) needs sequencing
# data, protein databases, Rfam.cm etc. that live on the HPC.  See the HPC
# section at the bottom of this script for the FullAnnotation_conf invocation.
#
# Usage:
#   chmod +x run_local_test.sh
#   ./run_local_test.sh 2>&1 | tee /tmp/genebuild_test/run.log
# =============================================================================

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────

ASSEMBLY_ACCESSION="GCA_000001405.29"
ASSEMBLY_NAME="GRCh38.p14"
REFSEQ_ACCESSION="GCF_000001405.40"

OUTDIR="/tmp/genebuild_test"
NF_WORK_ROOT="/tmp/genebuild_test/nf_work"
NF_BASE_DIR="$HOME/projects/ensembl-genebuild/ensembl-genes-nf/pipelines"
ANALYSIS_DIR="$HOME/projects/ensembl-analysis"

NEXTFLOW_BIN="$HOME/.local/bin/nextflow"
NEXTFLOW_PROFILE="conda"
JAVA_HOME_PATH="/opt/homebrew/Cellar/openjdk@21/21.0.10/libexec/openjdk.jdk/Contents/Home"
NEXTFLOW_PATH_EXTRA="/opt/homebrew/bin"
MAMBA_ROOT_PREFIX_PATH="/Users/jackt/mamba"

PERL5LIB_PATH="$HOME/perl5/lib/perl5:$HOME/ensembl-hive/modules:${ANALYSIS_DIR}/modules"
HIVE_SCRIPTS="$HOME/ensembl-hive/scripts"

# ─── Helpers ──────────────────────────────────────────────────────────────────

export PERL5LIB="$PERL5LIB_PATH"

section() { echo; echo "═══════════════════════════════════════════════════════"; echo "  $*"; echo "═══════════════════════════════════════════════════════"; }

init_pipe() {
    local conf="$1" db="$2"; shift 2
    echo "→ Initialising $conf → $db"
    rm -f "$db"
    perl "$HIVE_SCRIPTS/init_pipeline.pl" \
        "Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::${conf}" \
        -pipeline_url "sqlite:///${db}" \
        -nextflow_bin          "$NEXTFLOW_BIN" \
        -nextflow_profile      "$NEXTFLOW_PROFILE" \
        -java_home             "$JAVA_HOME_PATH" \
        -nextflow_path_extra   "$NEXTFLOW_PATH_EXTRA" \
        -mamba_root_prefix     "$MAMBA_ROOT_PREFIX_PATH" \
        -nextflow_work_root    "$NF_WORK_ROOT" \
        "$@"
}

run_pipe() {
    local db="$1"
    echo "→ Running pipeline: $db"
    perl "$HIVE_SCRIPTS/beekeeper.pl" \
        -url "sqlite:///${db}" \
        -loop \
        -sleep 5 \
        -max_loops 200
}

# ─── Setup ────────────────────────────────────────────────────────────────────

section "Setup"
mkdir -p "$OUTDIR" "$NF_WORK_ROOT"
echo "Output root:  $OUTDIR"
echo "NF work root: $NF_WORK_ROOT"

# ─── Pipeline 1: LoadAssembly ─────────────────────────────────────────────────

section "Pipeline 1/2 — LoadAssembly ($ASSEMBLY_ACCESSION)"

LOAD_DB="$OUTDIR/load_assembly.db"
LOAD_OUTDIR="$OUTDIR/load_assembly"
mkdir -p "$LOAD_OUTDIR"

init_pipe LoadAssembly_conf "$LOAD_DB" \
    -assembly_accession "$ASSEMBLY_ACCESSION" \
    -assembly_name      "$ASSEMBLY_NAME" \
    -outdir             "$LOAD_OUTDIR" \
    -nf_pipeline_dir    "$NF_BASE_DIR/load_assembly"

run_pipe "$LOAD_DB"

GENOME_FASTA="$LOAD_OUTDIR/genome/${ASSEMBLY_ACCESSION}_${ASSEMBLY_NAME}_genomic.fna"
SYNONYMS_TSV="$LOAD_OUTDIR/genome/${ASSEMBLY_ACCESSION}_${ASSEMBLY_NAME}.synonyms.tsv"

echo
echo "✔ LoadAssembly complete"
echo "  Genome FASTA : $GENOME_FASTA"
echo "  Synonyms TSV : $SYNONYMS_TSV"
cat "$LOAD_OUTDIR/output_manifest.json"

# ─── Pipeline 2: RefseqImport ─────────────────────────────────────────────────

section "Pipeline 2/2 — RefseqImport ($REFSEQ_ACCESSION)"

REFSEQ_DB="$OUTDIR/refseq_import.db"
REFSEQ_OUTDIR="$OUTDIR/refseq_import"
mkdir -p "$REFSEQ_OUTDIR"

init_pipe RefseqImport_conf "$REFSEQ_DB" \
    -assembly_refseq_accession "$REFSEQ_ACCESSION" \
    -assembly_name             "$ASSEMBLY_NAME" \
    -synonyms_tsv              "$SYNONYMS_TSV" \
    -outdir                    "$REFSEQ_OUTDIR" \
    -nf_pipeline_dir           "$NF_BASE_DIR/refseq_import"

run_pipe "$REFSEQ_DB"

echo
echo "✔ RefseqImport complete"
cat "$REFSEQ_OUTDIR/output_manifest.json"

# ─── Summary ──────────────────────────────────────────────────────────────────

section "Local test COMPLETE"
echo "Outputs in $OUTDIR:"
find "$OUTDIR" -name "output_manifest.json" | while read m; do
    echo
    echo "  $m:"
    python3 -c "import json,sys; d=json.load(open('$m')); [print('    '+o['type']+': '+o['path']) for o in d.get('outputs',[])]"
done

echo
echo "═══════════════════════════════════════════════════════"
echo "  HPC PRODUCTION — FullAnnotation_conf"
echo "═══════════════════════════════════════════════════════"
cat <<'HPC_CMD'

On the HPC (MySQL + SLURM + Singularity), after loading the required modules:

  module load nextflow java

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::FullAnnotation_conf \
    -pipeline_db "-host mysql-ens-genebuild-prod -port 4527 -user ensrw -pass XXX \
                  -dbname ${USER}_grch38_full_annotation" \
    -assembly_accession        GCA_000001405.29 \
    -assembly_name             GRCh38.p14 \
    -assembly_refseq_accession GCF_000001405.40 \
    -sample_sheet              /hps/nobackup/.../rnaseq/samples.csv \
    -cdna_fasta                /hps/nobackup/.../sequences/cdna.fa \
    -protein_fasta             /hps/nobackup/.../sequences/proteins.fa \
    -uniprot_fasta             /hps/nobackup/.../proteins/mammals_basic.fa \
    -igtr_proteins             /hps/nobackup/.../imgt/imgt_proteins.fa \
    -long_read_sample_sheet    /hps/nobackup/.../isoseq/samples.tsv \
    -protein_db                /hps/nobackup/.../uniprot/uniprot_db \
    -rfam_cm                   /hps/nobackup/.../rfam/Rfam.cm \
    -source_fasta              /hps/nobackup/.../source_genome/genome_softmasked.fa \
    -source_gff3               /hps/nobackup/.../source_genome/annotation.gff3 \
    -outdir                    /hps/scratch/flicek/ensembl/genebuild/grch38 \
    -nextflow_work_root        /hps/scratch/flicek/ensembl/genebuild/grch38/nf_work \
    -nf_base_dir               /nfs/production/flicek/ensembl/genebuild/ensembl-genes-nf/pipelines

  # beekeeper submits HiveRunNextflow launcher jobs to SLURM;
  # each launcher then submits Nextflow tasks to SLURM via -profile slurm
  beekeeper.pl -url "$EHIVE_URL" -loop

HPC_CMD
