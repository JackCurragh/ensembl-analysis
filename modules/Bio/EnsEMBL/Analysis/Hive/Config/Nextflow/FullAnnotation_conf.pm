=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

=head1 NAME

Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::FullAnnotation_conf

=head1 DESCRIPTION

End-to-end genome annotation eHive pipeline using the Nextflow subpipelines.

Dependency graph:

  Seed
   │
   ▼
  RunLoadAssembly          (downloads FASTA + synonyms TSV)
   │ channel 1
   ▼
  RunRepeatMasking          (softmasks genome)
   │ channel 1
   ▼
  FanAnnotationLayers  ─── semaphore group A ────────────────────┐
   │ 1->A                                                         │
   ├── RunRnaSeq                                                  │
   ├── RunBestTargeted                                            │
   ├── RunProjection                                              │
   ├── RunAbInitio                                                │
   ├── RunIgtr                                                    │
   ├── RunLongRead                                                │
   ├── RunGenblastHomology                                        │
   ├── RunShortNcrna                                              │
   └── RunRefseqImport                                            │
   │ A->1 (triggered when ALL 9 annotation layers complete)       │
   ▼ ◄─────────────────────────────────────────────────────────────┘
  RunConsolidate            (scans outdir/**/*.gff3 for all GFF3s)
   │ channel 2
   ▼
  ConsumeConsolidatedOutput

All input paths (genome_fasta, softmasked_fasta, synonyms_tsv) are computed
from the assembly_accession + assembly_name at init time using the known
publishDir conventions of each Nextflow pipeline.  This avoids relying on
eHive channel-2 dataflow for sequential path-passing, which would require
per-output type filtering.

Usage (HPC production — MySQL + SLURM + Singularity):

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::FullAnnotation_conf \
    -pipeline_db               "-host mysql-ens-genebuild-prod -port 4527 -user ensrw -pass XXX -dbname jack_grch38_annotation" \
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

  # Then run workers — eHive manages SLURM submission for Nextflow launcher jobs:
  beekeeper.pl -url "$EHIVE_URL" -loop

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::FullAnnotation_conf;

use strict;
use warnings;
use File::Spec::Functions qw(catdir catfile);

use parent ('Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::NfPipelineBase_conf');


sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },

        # ----------------------------------------------------------------
        # Assembly identity
        # ----------------------------------------------------------------
        assembly_accession          => undef,   # GCA accession for load_assembly
        assembly_name               => undef,
        assembly_refseq_accession   => undef,   # GCF accession for refseq_import

        # ----------------------------------------------------------------
        # Evidence inputs  (set those relevant to the species)
        # ----------------------------------------------------------------
        sample_sheet                => undef,   # RNA-seq CSV: id,fastq_1,...
        cdna_fasta                  => undef,
        protein_fasta               => undef,   # species-specific proteins (best_targeted)
        uniprot_fasta               => undef,   # clade UniProt set (genblast_homology)
        igtr_proteins               => undef,   # IMGT IG/TR FASTA
        long_read_sample_sheet      => undef,   # TSV: id, fastq path
        protein_db                  => undef,   # UniProt BLAST DB (long_read classify)
        rfam_cm                     => undef,   # Rfam.cm
        source_fasta                => undef,   # softmasked source genome (projection)
        source_gff3                 => undef,   # source annotation (projection)

        # ----------------------------------------------------------------
        # Nextflow infrastructure (nf_base_dir is the parent of all
        # pipelines/ subdirs in ensembl-genes-nf)
        # ----------------------------------------------------------------
        nf_base_dir                 => undef,   # e.g. /nfs/production/.../ensembl-genes-nf/pipelines

        # ----------------------------------------------------------------
        # Repeat masking options
        # ----------------------------------------------------------------
        repbase_library             => undef,
        custom_repeat_library       => undef,
        repeat_species              => 'mammals',
    };
}


sub pipeline_wide_parameters {
    my ($self) = @_;
    return {
        %{ $self->SUPER::pipeline_wide_parameters() },
        pipeline_name => 'full_annotation',
    };
}


# Resolve a pipeline directory under nf_base_dir
sub _pipeline_dir {
    my ($self, $name) = @_;
    return catdir($self->o('nf_base_dir'), $name);
}

# Resolve per-pipeline output subdirectory
sub _outdir {
    my ($self, $name) = @_;
    return catdir($self->o('outdir'), $name);
}


sub pipeline_analyses {
    my ($self) = @_;

    # ----------------------------------------------------------------
    # Precompute stable file paths from known publishDir conventions.
    #
    # These paths are deterministic given assembly_accession + assembly_name
    # and the per-pipeline outdir.  Using hardcoded paths avoids having to
    # filter channel-2 dataflow outputs by type when passing files between
    # sequential pipeline stages.
    #
    # Conventions:
    #   load_assembly   → outdir/load_assembly/genome/<acc>_<name>_genomic.fna
    #                     outdir/load_assembly/genome/<acc>_<name>.synonyms.tsv
    #   repeat_masking  → outdir/repeat_masking/genome/<acc>_<name>_genomic.softmasked.fa
    # ----------------------------------------------------------------
    my $assembly_id = $self->o('assembly_accession') . '_' . $self->o('assembly_name');

    my $genome_fasta = catfile(
        $self->_outdir('load_assembly'), 'genome', "${assembly_id}_genomic.fna"
    );
    my $synonyms_tsv = catfile(
        $self->_outdir('load_assembly'), 'genome', "${assembly_id}.synonyms.tsv"
    );
    my $softmasked_fasta = catfile(
        $self->_outdir('repeat_masking'), 'genome', "${assembly_id}_genomic.softmasked.fa"
    );

    return [

        # ================================================================
        # Stage 0: Seed
        # ================================================================
        {
            -logic_name  => 'Seed',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -input_ids   => [{}],
            -flow_into   => { 1 => 'RunLoadAssembly' },
            -meadow_type => 'LOCAL',
        },

        # ================================================================
        # Stage 1: Load genome assembly (downloads FASTA + synonyms TSV)
        # Runs sequentially before repeat masking.
        # nextflow_dataflow_outputs => 0: downstream paths are hardcoded.
        # ================================================================
        {
            -logic_name  => 'RunLoadAssembly',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir     => $self->_pipeline_dir('load_assembly'),
                nextflow_pipeline_name    => 'load_assembly',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('load_assembly'),
                nextflow_resume_mode      => 'attempt',
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_params           => {
                    assembly_accession => $self->o('assembly_accession'),
                    assembly_name      => $self->o('assembly_name'),
                    outdir             => $self->_outdir('load_assembly'),
                },
                nextflow_dataflow_outputs => 0,
                nextflow_binary           => $self->_nf_binary(),
            },
            -rc_name         => 'small_long',
            -flow_into       => { 1 => 'RunRepeatMasking' },
            -max_retry_count => 1,
        },

        # ================================================================
        # Stage 2: Repeat masking (uses genome FASTA from stage 1)
        # Runs sequentially before the annotation fan.
        # BEDTOOLS_MASKFASTA publishes softmasked.fa → outdir/genome/
        # nextflow_dataflow_outputs => 0: downstream path is hardcoded.
        # ================================================================
        {
            -logic_name  => 'RunRepeatMasking',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir     => $self->_pipeline_dir('repeat_masking'),
                nextflow_pipeline_name    => 'repeat_masking',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('repeat_masking'),
                nextflow_resume_mode      => 'attempt',
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_params           => {
                    genome_fasta       => $genome_fasta,
                    repbase_library    => $self->o('repbase_library'),
                    custom_library     => $self->o('custom_repeat_library'),
                    species            => $self->o('repeat_species'),
                    skip_repeatmodeler => 1,
                    outdir             => $self->_outdir('repeat_masking'),
                },
                nextflow_dataflow_outputs => 0,
                nextflow_binary           => $self->_nf_binary(),
            },
            -rc_name         => 'large_long',
            -flow_into       => { 1 => 'FanAnnotationLayers' },
            -max_retry_count => 1,
        },

        # ================================================================
        # Stage 3: Fan to all 9 annotation pipelines in parallel.
        #
        # The 1->A / A->1 eHive semaphore pattern ensures RunConsolidate
        # is only triggered after ALL annotation layers complete.  Each
        # RunXxx receives nextflow_dataflow_outputs => 0 so there are no
        # channel-2 descendants that could race with the consolidation.
        # ================================================================
        {
            -logic_name  => 'FanAnnotationLayers',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -flow_into   => {
                '1->A' => [
                    'RunRnaSeq',
                    'RunBestTargeted',
                    'RunProjection',
                    'RunAbInitio',
                    'RunIgtr',
                    'RunLongRead',
                    'RunGenblastHomology',
                    'RunShortNcrna',
                    'RunRefseqImport',
                ],
                'A->1' => ['RunConsolidate'],
            },
            -meadow_type => 'LOCAL',
        },

        # ----------------------------------------------------------------
        # Stage 3 analyses — all use the softmasked genome from stage 2.
        # RefseqImport uses the synonyms TSV from stage 1.
        # ----------------------------------------------------------------

        {
            -logic_name  => 'RunRnaSeq',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir     => $self->_pipeline_dir('rnaseq'),
                nextflow_pipeline_name    => 'rnaseq',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('rnaseq'),
                nextflow_resume_mode      => 'attempt',
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_params           => {
                    genome_fasta => $softmasked_fasta,
                    sample_sheet => $self->o('sample_sheet'),
                    outdir       => $self->_outdir('rnaseq'),
                },
                nextflow_dataflow_outputs => 0,
                nextflow_binary           => $self->_nf_binary(),
            },
            -rc_name         => 'medium_long',
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'RunBestTargeted',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir     => $self->_pipeline_dir('best_targeted'),
                nextflow_pipeline_name    => 'best_targeted',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('best_targeted'),
                nextflow_resume_mode      => 'attempt',
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_params           => {
                    genome_fasta  => $softmasked_fasta,
                    cdna_fasta    => $self->o('cdna_fasta'),
                    protein_fasta => $self->o('protein_fasta'),
                    outdir        => $self->_outdir('best_targeted'),
                },
                nextflow_dataflow_outputs => 0,
                nextflow_binary           => $self->_nf_binary(),
            },
            -rc_name         => 'medium_long',
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'RunProjection',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir     => $self->_pipeline_dir('projection'),
                nextflow_pipeline_name    => 'projection',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('projection'),
                nextflow_resume_mode      => 'attempt',
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_params           => {
                    query_fasta  => $softmasked_fasta,
                    source_fasta => $self->o('source_fasta'),
                    source_gff3  => $self->o('source_gff3'),
                    outdir       => $self->_outdir('projection'),
                },
                nextflow_dataflow_outputs => 0,
                nextflow_binary           => $self->_nf_binary(),
            },
            -rc_name         => 'medium_long',
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'RunAbInitio',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir     => $self->_pipeline_dir('ab_initio'),
                nextflow_pipeline_name    => 'ab_initio',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('ab_initio'),
                nextflow_resume_mode      => 'attempt',
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_params           => {
                    genome_fasta => $softmasked_fasta,
                    species      => $self->o('assembly_name'),
                    outdir       => $self->_outdir('ab_initio'),
                },
                nextflow_dataflow_outputs => 0,
                nextflow_binary           => $self->_nf_binary(),
            },
            -rc_name         => 'medium_long',
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'RunIgtr',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir     => $self->_pipeline_dir('igtr'),
                nextflow_pipeline_name    => 'igtr',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('igtr'),
                nextflow_resume_mode      => 'attempt',
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_params           => {
                    genome_fasta  => $softmasked_fasta,
                    igtr_proteins => $self->o('igtr_proteins'),
                    outdir        => $self->_outdir('igtr'),
                },
                nextflow_dataflow_outputs => 0,
                nextflow_binary           => $self->_nf_binary(),
            },
            -rc_name         => 'large_long',
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'RunLongRead',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir     => $self->_pipeline_dir('long_read'),
                nextflow_pipeline_name    => 'long_read',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('long_read'),
                nextflow_resume_mode      => 'attempt',
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_params           => {
                    genome_fasta => $softmasked_fasta,
                    sample_sheet => $self->o('long_read_sample_sheet'),
                    protein_db   => $self->o('protein_db'),
                    outdir       => $self->_outdir('long_read'),
                },
                nextflow_dataflow_outputs => 0,
                nextflow_binary           => $self->_nf_binary(),
            },
            -rc_name         => 'large_long',
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'RunGenblastHomology',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir     => $self->_pipeline_dir('genblast_homology'),
                nextflow_pipeline_name    => 'genblast_homology',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('genblast_homology'),
                nextflow_resume_mode      => 'attempt',
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_params           => {
                    genome_fasta  => $softmasked_fasta,
                    uniprot_fasta => $self->o('uniprot_fasta'),
                    outdir        => $self->_outdir('genblast_homology'),
                },
                nextflow_dataflow_outputs => 0,
                nextflow_binary           => $self->_nf_binary(),
            },
            -rc_name         => 'medium_long',
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'RunShortNcrna',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir     => $self->_pipeline_dir('short_ncrna'),
                nextflow_pipeline_name    => 'short_ncrna',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('short_ncrna'),
                nextflow_resume_mode      => 'attempt',
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_params           => {
                    genome_fasta => $softmasked_fasta,
                    rfam_cm      => $self->o('rfam_cm'),
                    outdir       => $self->_outdir('short_ncrna'),
                },
                nextflow_dataflow_outputs => 0,
                nextflow_binary           => $self->_nf_binary(),
            },
            -rc_name         => 'medium_long',
            -max_retry_count => 1,
        },

        {
            # RefseqImport doesn't need the softmasked genome; it runs in
            # parallel with the other annotation layers using the synonyms TSV
            # produced by LoadAssembly (load_assembly/genome/<acc>_<name>.synonyms.tsv).
            -logic_name  => 'RunRefseqImport',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir     => $self->_pipeline_dir('refseq_import'),
                nextflow_pipeline_name    => 'refseq_import',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('refseq_import'),
                nextflow_resume_mode      => 'attempt',
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_params           => {
                    assembly_refseq_accession => $self->o('assembly_refseq_accession'),
                    assembly_name             => $self->o('assembly_name'),
                    synonyms_tsv              => $synonyms_tsv,
                    outdir                    => $self->_outdir('refseq_import'),
                },
                nextflow_dataflow_outputs => 0,
                nextflow_binary           => $self->_nf_binary(),
            },
            -rc_name         => 'small_long',
            -max_retry_count => 1,
        },

        # ================================================================
        # Stage 4: Consolidate
        # Triggered by the semaphore after ALL 9 annotation layers complete.
        # Recursively scans outdir/**/*.gff3 — each annotation pipeline
        # publishes its GFF3 under its own subdirectory.  Repeat GFF3s are
        # NOT published so they won't be included.
        # ================================================================
        {
            -logic_name  => 'RunConsolidate',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir     => $self->_pipeline_dir('consolidate'),
                nextflow_pipeline_name    => 'consolidate',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('consolidate'),
                nextflow_resume_mode      => 'attempt',
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_params           => {
                    gff3_dir => $self->o('outdir'),
                    outdir   => $self->_outdir('consolidate'),
                },
                nextflow_dataflow_outputs => 1,
                nextflow_binary           => $self->_nf_binary(),
            },
            -rc_name         => 'medium_long',
            -flow_into       => { 2 => 'ConsumeConsolidatedOutput' },
            -max_retry_count => 1,
        },

        # ================================================================
        # Stage 5: Final consumer (replace with DB loading analysis)
        # ================================================================
        {
            -logic_name  => 'ConsumeConsolidatedOutput',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => {
                cmd => 'echo "Final annotation ready: type=#type# path=#path#"',
            },
            -meadow_type => 'LOCAL',
        },

    ];
}


1;
