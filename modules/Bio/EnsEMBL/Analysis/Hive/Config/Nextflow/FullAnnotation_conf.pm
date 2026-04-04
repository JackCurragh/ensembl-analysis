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
  LoadAssembly
       │ genome_fasta, metadata
       ▼
  RepeatMasking
       │ softmasked_fasta
       ├──────────────────────────────────────────────┐
       ▼                                              ▼
  [Parallel annotation layers]               ShortNcrna
  RnaSeq / BestTargeted / Projection /
  AbInitio / RefseqImport / Igtr /
  LongRead / GenblastHomology
       │ GFF3 files
       └─────────────┐
                     ▼
               Consolidate
                     │
                     ▼
             ConsumeConsolidated

All Nextflow subpipelines are launched by HiveRunNextflow.  Each pipeline
writes output_manifest.json; dataflow on channel 2 passes file paths to the
next stage.

Usage:

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::FullAnnotation_conf \
    -pipeline_db               "-host localhost -port 3306 -user ensrw -pass XXX -dbname full_annotation" \
    -assembly_accession        GCA_000001405.29 \
    -assembly_name             GRCh38.p14 \
    -assembly_refseq_accession GCF_000001405.40 \
    -sample_sheet              /data/rnaseq/samples.csv \
    -cdna_fasta                /data/sequences/cdna.fa \
    -protein_fasta             /data/sequences/proteins.fa \
    -uniprot_fasta             /data/proteins/mammals_basic.fa \
    -igtr_proteins             /data/imgt/imgt_proteins.fa \
    -long_read_sample_sheet    /data/isoseq/samples.tsv \
    -protein_db                /data/uniprot/uniprot_db \
    -rfam_cm                   /data/rfam/Rfam.cm \
    -source_fasta              /data/source_genome/genome_softmasked.fa \
    -source_gff3               /data/source_genome/annotation.gff3 \
    -outdir                    /data/output/grch38 \
    -nextflow_work_root        /data/nf_work \
    -nf_base_dir               /path/to/ensembl-genes-nf/pipelines

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::FullAnnotation_conf;

use strict;
use warnings;
use File::Spec::Functions qw(catdir catfile);

use parent ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');


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
        # Output root
        # ----------------------------------------------------------------
        outdir                      => undef,

        # ----------------------------------------------------------------
        # Nextflow infrastructure
        # ----------------------------------------------------------------
        nextflow_work_root          => undef,
        nf_base_dir                 => undef,   # parent of all pipelines/ dirs
        nextflow_bin                => 'nextflow',
        nextflow_profile            => 'local',
        java_home                   => '/opt/homebrew/Cellar/openjdk@21/21.0.10/libexec/openjdk.jdk/Contents/Home',

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


# Shared JAVA_HOME prefix — used by every HiveRunNextflow analysis
sub _nf_binary {
    my ($self) = @_;
    return 'JAVA_HOME=' . $self->o('java_home')
        . ' PATH=' . $self->o('java_home') . '/bin:$PATH '
        . $self->o('nextflow_bin');
}

# Resolve a pipeline directory under nf_base_dir
sub _pipeline_dir {
    my ($self, $name) = @_;
    return catdir($self->o('nf_base_dir'), $name);
}

# Resolve per-pipeline outdir
sub _outdir {
    my ($self, $name) = @_;
    return catdir($self->o('outdir'), $name);
}


sub pipeline_analyses {
    my ($self) = @_;

    return [

        # ================================================================
        # Stage 0: seed
        # ================================================================
        {
            -logic_name  => 'Seed',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -input_ids   => [{}],
            -flow_into   => { 1 => ['RunLoadAssembly', 'RunRefseqImport'] },
            -meadow_type => 'LOCAL',
        },

        # ================================================================
        # Stage 1a: load genome assembly from NCBI
        # ================================================================
        {
            -logic_name  => 'RunLoadAssembly',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir  => $self->_pipeline_dir('load_assembly'),
                nextflow_pipeline_name => 'load_assembly',
                nextflow_work_root     => $self->o('nextflow_work_root'),
                nextflow_output_dir    => $self->_outdir('load_assembly'),
                nextflow_resume_mode   => 'attempt',
                nextflow_profile       => $self->o('nextflow_profile'),
                nextflow_params        => {
                    assembly_accession => $self->o('assembly_accession'),
                    assembly_name      => $self->o('assembly_name'),
                    outdir             => $self->_outdir('load_assembly'),
                },
                nextflow_dataflow_outputs => 1,
                nextflow_binary => $self->_nf_binary(),
            },
            -rc_name         => 'small_long',
            -flow_into       => { 2 => 'CollectAssemblyOutputs' },
            -max_retry_count => 1,
        },

        # Accumulate load_assembly outputs (genome_fasta) before repeat masking
        {
            -logic_name        => 'CollectAssemblyOutputs',
            -module            => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -flow_into         => { 1 => 'RunRepeatMasking' },
            -meadow_type       => 'LOCAL',
        },

        # ================================================================
        # Stage 1b: RepeatMasking (waits for genome FASTA from LoadAssembly)
        # ================================================================
        {
            -logic_name  => 'RunRepeatMasking',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir  => $self->_pipeline_dir('repeat_masking'),
                nextflow_pipeline_name => 'repeat_masking',
                nextflow_work_root     => $self->o('nextflow_work_root'),
                nextflow_output_dir    => $self->_outdir('repeat_masking'),
                nextflow_resume_mode   => 'attempt',
                nextflow_profile       => $self->o('nextflow_profile'),
                nextflow_params        => {
                    # genome_fasta will be set from the #path# dataflow param
                    # when load_assembly outputs a softmasked_fasta type.
                    # For now bind directly; replace with '#path#' when
                    # load_assembly→RepeatMasking wiring is validated.
                    genome_fasta       => '#path#',
                    species            => $self->o('repeat_species'),
                    skip_repeatmodeler => 1,
                    outdir             => $self->_outdir('repeat_masking'),
                },
                nextflow_dataflow_outputs => 1,
                nextflow_binary => $self->_nf_binary(),
            },
            -rc_name         => 'large_long',
            # Fan out to all parallel annotation stages
            -flow_into       => {
                2 => [
                    'FanAnnotationLayers',
                ],
            },
            -max_retry_count => 1,
        },

        # After repeat masking, start all annotation layers in parallel
        {
            -logic_name  => 'FanAnnotationLayers',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -flow_into   => {
                1 => [
                    'RunRnaSeq',
                    'RunBestTargeted',
                    'RunProjection',
                    'RunAbInitio',
                    'RunIgtr',
                    'RunLongRead',
                    'RunGenblastHomology',
                    'RunShortNcrna',
                ],
            },
            -meadow_type => 'LOCAL',
        },

        # ================================================================
        # Stage 1b parallel: RefSeq import (independent of repeat masking)
        # ================================================================
        {
            -logic_name  => 'RunRefseqImport',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir  => $self->_pipeline_dir('refseq_import'),
                nextflow_pipeline_name => 'refseq_import',
                nextflow_work_root     => $self->o('nextflow_work_root'),
                nextflow_output_dir    => $self->_outdir('refseq_import'),
                nextflow_resume_mode   => 'attempt',
                nextflow_profile       => $self->o('nextflow_profile'),
                nextflow_params        => {
                    assembly_refseq_accession => $self->o('assembly_refseq_accession'),
                    assembly_name             => $self->o('assembly_name'),
                    outdir                    => $self->_outdir('refseq_import'),
                },
                nextflow_dataflow_outputs => 1,
                nextflow_binary => $self->_nf_binary(),
            },
            -rc_name         => 'small_long',
            -flow_into       => { 2 => 'CollectLayerOutputs' },
            -max_retry_count => 1,
        },

        # ================================================================
        # Stage 2: Parallel annotation layers (all receive softmasked genome path)
        # ================================================================
        {
            -logic_name  => 'RunRnaSeq',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir  => $self->_pipeline_dir('rnaseq'),
                nextflow_pipeline_name => 'rnaseq',
                nextflow_work_root     => $self->o('nextflow_work_root'),
                nextflow_output_dir    => $self->_outdir('rnaseq'),
                nextflow_resume_mode   => 'attempt',
                nextflow_profile       => $self->o('nextflow_profile'),
                nextflow_params        => {
                    genome_fasta => '#path#',
                    sample_sheet => $self->o('sample_sheet'),
                    outdir       => $self->_outdir('rnaseq'),
                },
                nextflow_dataflow_outputs => 1,
                nextflow_binary => $self->_nf_binary(),
            },
            -rc_name         => 'medium_long',
            -flow_into       => { 2 => 'CollectLayerOutputs' },
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'RunBestTargeted',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir  => $self->_pipeline_dir('best_targeted'),
                nextflow_pipeline_name => 'best_targeted',
                nextflow_work_root     => $self->o('nextflow_work_root'),
                nextflow_output_dir    => $self->_outdir('best_targeted'),
                nextflow_resume_mode   => 'attempt',
                nextflow_profile       => $self->o('nextflow_profile'),
                nextflow_params        => {
                    genome_fasta   => '#path#',
                    cdna_fasta     => $self->o('cdna_fasta'),
                    protein_fasta  => $self->o('protein_fasta'),
                    outdir         => $self->_outdir('best_targeted'),
                },
                nextflow_dataflow_outputs => 1,
                nextflow_binary => $self->_nf_binary(),
            },
            -rc_name         => 'medium_long',
            -flow_into       => { 2 => 'CollectLayerOutputs' },
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'RunProjection',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir  => $self->_pipeline_dir('projection'),
                nextflow_pipeline_name => 'projection',
                nextflow_work_root     => $self->o('nextflow_work_root'),
                nextflow_output_dir    => $self->_outdir('projection'),
                nextflow_resume_mode   => 'attempt',
                nextflow_profile       => $self->o('nextflow_profile'),
                nextflow_params        => {
                    query_fasta  => '#path#',
                    source_fasta => $self->o('source_fasta'),
                    source_gff3  => $self->o('source_gff3'),
                    outdir       => $self->_outdir('projection'),
                },
                nextflow_dataflow_outputs => 1,
                nextflow_binary => $self->_nf_binary(),
            },
            -rc_name         => 'medium_long',
            -flow_into       => { 2 => 'CollectLayerOutputs' },
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'RunAbInitio',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir  => $self->_pipeline_dir('ab_initio'),
                nextflow_pipeline_name => 'ab_initio',
                nextflow_work_root     => $self->o('nextflow_work_root'),
                nextflow_output_dir    => $self->_outdir('ab_initio'),
                nextflow_resume_mode   => 'attempt',
                nextflow_profile       => $self->o('nextflow_profile'),
                nextflow_params        => {
                    genome_fasta => '#path#',
                    species      => $self->o('assembly_name'),
                    outdir       => $self->_outdir('ab_initio'),
                },
                nextflow_dataflow_outputs => 1,
                nextflow_binary => $self->_nf_binary(),
            },
            -rc_name         => 'medium_long',
            -flow_into       => { 2 => 'CollectLayerOutputs' },
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'RunIgtr',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir  => $self->_pipeline_dir('igtr'),
                nextflow_pipeline_name => 'igtr',
                nextflow_work_root     => $self->o('nextflow_work_root'),
                nextflow_output_dir    => $self->_outdir('igtr'),
                nextflow_resume_mode   => 'attempt',
                nextflow_profile       => $self->o('nextflow_profile'),
                nextflow_params        => {
                    genome_fasta  => '#path#',
                    igtr_proteins => $self->o('igtr_proteins'),
                    outdir        => $self->_outdir('igtr'),
                },
                nextflow_dataflow_outputs => 1,
                nextflow_binary => $self->_nf_binary(),
            },
            -rc_name         => 'medium_long',
            -flow_into       => { 2 => 'CollectLayerOutputs' },
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'RunLongRead',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir  => $self->_pipeline_dir('long_read'),
                nextflow_pipeline_name => 'long_read',
                nextflow_work_root     => $self->o('nextflow_work_root'),
                nextflow_output_dir    => $self->_outdir('long_read'),
                nextflow_resume_mode   => 'attempt',
                nextflow_profile       => $self->o('nextflow_profile'),
                nextflow_params        => {
                    genome_fasta => '#path#',
                    sample_sheet => $self->o('long_read_sample_sheet'),
                    protein_db   => $self->o('protein_db'),
                    outdir       => $self->_outdir('long_read'),
                },
                nextflow_dataflow_outputs => 1,
                nextflow_binary => $self->_nf_binary(),
            },
            -rc_name         => 'large_long',
            -flow_into       => { 2 => 'CollectLayerOutputs' },
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'RunGenblastHomology',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir  => $self->_pipeline_dir('genblast_homology'),
                nextflow_pipeline_name => 'genblast_homology',
                nextflow_work_root     => $self->o('nextflow_work_root'),
                nextflow_output_dir    => $self->_outdir('genblast_homology'),
                nextflow_resume_mode   => 'attempt',
                nextflow_profile       => $self->o('nextflow_profile'),
                nextflow_params        => {
                    genome_fasta  => '#path#',
                    uniprot_fasta => $self->o('uniprot_fasta'),
                    outdir        => $self->_outdir('genblast_homology'),
                },
                nextflow_dataflow_outputs => 1,
                nextflow_binary => $self->_nf_binary(),
            },
            -rc_name         => 'medium_long',
            -flow_into       => { 2 => 'CollectLayerOutputs' },
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'RunShortNcrna',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir  => $self->_pipeline_dir('short_ncrna'),
                nextflow_pipeline_name => 'short_ncrna',
                nextflow_work_root     => $self->o('nextflow_work_root'),
                nextflow_output_dir    => $self->_outdir('short_ncrna'),
                nextflow_resume_mode   => 'attempt',
                nextflow_profile       => $self->o('nextflow_profile'),
                nextflow_params        => {
                    genome_fasta => '#path#',
                    rfam_cm      => $self->o('rfam_cm'),
                    outdir       => $self->_outdir('short_ncrna'),
                },
                nextflow_dataflow_outputs => 1,
                nextflow_binary => $self->_nf_binary(),
            },
            -rc_name         => 'medium_long',
            -flow_into       => { 2 => 'CollectLayerOutputs' },
            -max_retry_count => 1,
        },

        # ================================================================
        # Stage 3: Collect all GFF3 outputs; trigger consolidation
        # ================================================================
        # All annotation layer jobs (including RefseqImport) fan into here.
        # eHive accumulates all channel-2 outputs from all RunXxx analyses.
        # When all upstream jobs are done the semaphore releases Consolidate.
        {
            -logic_name  => 'CollectLayerOutputs',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -flow_into   => { 1 => '?accu_name=gff3_paths&accu_input_variable=path&accu_address=[]' },
            -meadow_type => 'LOCAL',
        },

        {
            -logic_name  => 'RunConsolidate',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir  => $self->_pipeline_dir('consolidate'),
                nextflow_pipeline_name => 'consolidate',
                nextflow_work_root     => $self->o('nextflow_work_root'),
                nextflow_output_dir    => $self->_outdir('consolidate'),
                nextflow_resume_mode   => 'attempt',
                nextflow_profile       => $self->o('nextflow_profile'),
                nextflow_params        => {
                    gff3_files => '#gff3_paths#',
                    outdir     => $self->_outdir('consolidate'),
                },
                nextflow_dataflow_outputs => 1,
                nextflow_binary => $self->_nf_binary(),
            },
            -rc_name         => 'medium_long',
            -flow_into       => { 2 => 'ConsumeConsolidatedOutput' },
            -max_retry_count => 1,
        },

        # ================================================================
        # Stage 4: Final consumer (replace with DB loading analysis)
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


sub resource_classes {
    my ($self) = @_;
    return {
        %{ $self->SUPER::resource_classes() },
        'small_long' => {
            'LOCAL' => '',
            'LSF'   => '-q normal -M 500 -R "select[mem>500] rusage[mem=500]"',
            'SLURM' => '--partition=long --mem=500M --time=24:00:00',
        },
        'medium_long' => {
            'LOCAL' => '',
            'LSF'   => '-q normal -M 2000 -R "select[mem>2000] rusage[mem=2000]"',
            'SLURM' => '--partition=long --mem=2G --time=48:00:00',
        },
        'large_long' => {
            'LOCAL' => '',
            'LSF'   => '-q normal -M 25000 -R "select[mem>25000] rusage[mem=25000]"',
            'SLURM' => '--partition=long --mem=25G --time=120:00:00',
        },
    };
}


1;
