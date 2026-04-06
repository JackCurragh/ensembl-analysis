=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute
Licensed under the Apache License, Version 2.0.

=head1 DESCRIPTION

Full-annotation orchestration pipeline. Chains all Nextflow sub-pipelines in
the correct order using a single eHive DAG:

  Stage 1 (sequential):
    Seed → RunLoadAssembly → RunRepeatMasking

  Stage 2 (parallel fan):
    RunRepeatMasking → FanAnnotationLayers
    FanAnnotationLayers [1->A] → RunRnaSeq, RunBestTargeted, RunProjection,
                                  RunAbInitio, RunIgtr, RunLongRead,
                                  RunGenblastHomology, RunShortNcrna,
                                  RunRefseqImport
    FanAnnotationLayers [A->1] → RunConsolidate   (semaphore funnel)

  Stage 3 (sequential):
    RunConsolidate → RunUtrAddition → RunFinaliseGeneset → ConsumeFinalGeneset

Paths between stages are hardcoded from publishDir conventions so that
LoadAssembly and RepeatMasking can use nextflow_dataflow_outputs => 0, avoiding
the triple-trigger that would result from their multi-entry manifests.

=head2 Typical init command

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::NextflowFullAnnotation_conf \
    -pipeline_db -host=<host> -pipeline_db -port=<port>                               \
    -pipeline_db -dbname=${USER}_full_annotation_nf_pipe                              \
    -nextflow_work_root   /hps/nobackup/flicek/ensembl/genebuild/nextflow_work        \
    -nextflow_output_root /hps/nobackup/flicek/ensembl/genebuild/nextflow_output      \
    -assembly_accession   GCA_000001405.29                                             \
    -assembly_name        GRCh38.p14                                                   \
    -la_pipeline_dir      /path/to/ensembl-genes-nf/pipelines/load_assembly           \
    -rm_pipeline_dir      /path/to/ensembl-genes-nf/pipelines/repeat_masking          \
    -rs_pipeline_dir      /path/to/ensembl-genes-nf/pipelines/rnaseq                  \
    -bt_pipeline_dir      /path/to/ensembl-genes-nf/pipelines/best_targeted           \
    -proj_pipeline_dir    /path/to/ensembl-genes-nf/pipelines/projection              \
    -ai_pipeline_dir      /path/to/ensembl-genes-nf/pipelines/ab_initio              \
    -igtr_pipeline_dir    /path/to/ensembl-genes-nf/pipelines/igtr                    \
    -lr_pipeline_dir      /path/to/ensembl-genes-nf/pipelines/long_read               \
    -gb_pipeline_dir      /path/to/ensembl-genes-nf/pipelines/genblast_homology       \
    -nc_pipeline_dir      /path/to/ensembl-genes-nf/pipelines/short_ncrna             \
    -ri_pipeline_dir      /path/to/ensembl-genes-nf/pipelines/refseq_import           \
    -con_pipeline_dir     /path/to/ensembl-genes-nf/pipelines/consolidate             \
    -utr_pipeline_dir     /path/to/ensembl-genes-nf/pipelines/utr_addition            \
    -fg_pipeline_dir      /path/to/ensembl-genes-nf/pipelines/finalise_geneset        \
    -rs_sample_sheet      /path/to/rnaseq.csv                                          \
    -bt_cdna_fasta        /path/to/cdna.fa                                             \
    -bt_protein_fasta     /path/to/protein.fa                                          \
    -proj_source_fasta    /path/to/source.fa                                           \
    -proj_source_gff3     /path/to/source.gff3                                         \
    -ai_species           human                                                         \
    -igtr_proteins        /path/to/imgt.fa                                             \
    -lr_sample_sheet      /path/to/long_read.tsv                                       \
    -lr_protein_db        /path/to/uniprot_blastdb/                                    \
    -gb_uniprot_fasta     /path/to/uniprot.fa                                          \
    -nc_rfam_cm           /path/to/Rfam.cm                                             \
    -ri_refseq_accession  GCF_000001405.40                                             \
    -rm_repbase_library   /path/to/RepeatMaskerLib.h5

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::NextflowFullAnnotation_conf;

use strict;
use warnings;
use feature 'say';
use File::Spec::Functions qw(catdir catfile);
use base ('Bio::EnsEMBL::Analysis::Hive::Config::NextflowPipelineBase_conf');


# ---------------------------------------------------------------------------
# Helper: output directory for a named sub-pipeline
# ---------------------------------------------------------------------------
sub _outdir {
    my ($self, $pipeline_name) = @_;
    return catdir($self->o('nextflow_output_root'), $pipeline_name);
}


sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },

        user        => $ENV{GBUSER},
        password    => $ENV{GBPASS},
        user_r      => $ENV{USER_R} || 'ensro',
        password_r  => undef,
        dna_db_name => '',

        pipeline_name        => 'nextflow_full_annotation',
        nextflow_resume_mode => 'attempt',
        nextflow_profile     => 'slurm',
        nextflow_work_root   => undef,
        nextflow_output_root => undef,

        # --- Assembly identity (used to compute hardcoded output paths) ---
        assembly_accession => undef,   # e.g. GCA_000001405.29
        assembly_name      => undef,   # e.g. GRCh38.p14

        # --- Per-pipeline Nextflow pipeline directories ---
        la_pipeline_dir   => undef,   # load_assembly
        rm_pipeline_dir   => undef,   # repeat_masking
        rs_pipeline_dir   => undef,   # rnaseq
        bt_pipeline_dir   => undef,   # best_targeted
        proj_pipeline_dir => undef,   # projection
        ai_pipeline_dir   => undef,   # ab_initio
        igtr_pipeline_dir => undef,   # igtr
        lr_pipeline_dir   => undef,   # long_read
        gb_pipeline_dir   => undef,   # genblast_homology
        nc_pipeline_dir   => undef,   # short_ncrna
        ri_pipeline_dir   => undef,   # refseq_import
        con_pipeline_dir  => undef,   # consolidate
        utr_pipeline_dir  => undef,   # utr_addition
        fg_pipeline_dir   => undef,   # finalise_geneset

        # --- load_assembly params ---
        # (assembly_accession + assembly_name used directly)

        # --- repeat_masking params ---
        rm_repbase_library    => undef,
        rm_custom_library     => undef,
        rm_species            => 'mammals',
        rm_skip_repeatmodeler => 'true',
        rm_skip_red           => 'false',
        rm_skip_trf           => 'false',
        rm_skip_dust          => 'false',
        rm_chunk_size         => 10000000,
        rm_threads            => 4,

        # --- rnaseq params ---
        rs_sample_sheet   => undef,
        rs_star_index     => undef,
        rs_annotation_gtf => undef,

        # --- best_targeted params ---
        bt_cdna_fasta    => undef,
        bt_protein_fasta => undef,

        # --- projection params ---
        proj_source_fasta => undef,
        proj_source_gff3  => undef,
        proj_chain        => undef,

        # --- ab_initio params ---
        ai_species              => undef,
        ai_augustus_config_path => undef,
        ai_extrinsic_cfg        => undef,

        # --- igtr params ---
        igtr_proteins => undef,

        # --- long_read params ---
        lr_sample_sheet       => undef,
        lr_protein_db         => undef,
        lr_genome_index       => undef,
        lr_minimap2_preset    => 'splice',
        lr_min_overlap        => 0.8,
        lr_max_intron         => 200000,
        lr_blast_evalue       => '1e-5',
        lr_skip_download      => 'false',

        # --- genblast_homology params ---
        gb_uniprot_fasta => undef,

        # --- short_ncrna params ---
        nc_rfam_cm        => undef,
        nc_mirna_fasta    => undef,
        nc_mirna_blast_db => undef,

        # --- refseq_import params ---
        ri_refseq_accession => undef,   # GCF accession

        # --- consolidate params ---
        con_layer_priorities => '{"long_read":0,"best_targeted":1,"rnaseq":2,"projection":3,"refseq":4,"ab_initio":5,"genblast":6}',

        # --- utr_addition params ---
        utr_max_5prime    => 5000,
        utr_max_3prime    => 10000,
        utr_min_exon_size => 30,

        # --- finalise_geneset params ---
        fg_selenoprotein_fasta => undef,
        fg_min_orf_aa          => 100,
        fg_min_intron_size     => 10,
        fg_max_repeat_cds_cov  => 0.80,
        fg_max_readthrough_gap => 10000,
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    # -----------------------------------------------------------------------
    # Hardcoded inter-stage paths derived from publishDir conventions.
    # LoadAssembly publishes to: outdir/load_assembly/genome/
    # RepeatMasking publishes to: outdir/repeat_masking/genome/ and repeats/
    # This lets us use nextflow_dataflow_outputs => 0 for those two stages,
    # avoiding triple-trigger from their multi-entry manifests.
    # -----------------------------------------------------------------------
    my $assembly_id = $self->o('assembly_accession') . '_' . $self->o('assembly_name');

    my $genome_fasta     = catfile($self->_outdir('load_assembly'),  'genome', "${assembly_id}_genomic.fna");
    my $synonyms_tsv     = catfile($self->_outdir('load_assembly'),  'genome', "${assembly_id}.synonyms.tsv");
    my $softmasked_fasta = catfile($self->_outdir('repeat_masking'), 'genome', "${assembly_id}_genomic.softmasked.fa");
    my $repeat_gff3_glob = catfile($self->_outdir('repeat_masking'), 'repeats', '*.repeats.gff3');

    # Donor GFF3 globs for UTR addition (priority order: long_read > best_targeted > rnaseq)
    my $donor_gff3_files = join(',', (
        catfile($self->_outdir('long_read'),      '*.classified.gff3'),
        catfile($self->_outdir('best_targeted'),  '*.best_targeted.gff3'),
        catfile($self->_outdir('rnaseq'),         '*.merged.gff3'),
    ));

    return [

        # ------------------------------------------------------------------
        # Stage 0: Seed — single entry point for the whole pipeline
        # ------------------------------------------------------------------
        {
            -logic_name  => 'Seed',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => { cmd => 'echo "Full annotation pipeline starting."' },
            -rc_name     => '1GB',
            -input_ids   => [{}],
            -flow_into   => { 1 => ['RunLoadAssembly'] },
        },

        # ------------------------------------------------------------------
        # Stage 1a: Load assembly
        # nextflow_dataflow_outputs => 0: suppress manifest fan; paths hardcoded above
        # ------------------------------------------------------------------
        {
            -logic_name      => 'RunLoadAssembly',
            -module          => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters      => {
                nextflow_binary           => $self->o('nextflow_binary'),
                nextflow_pipeline_dir     => $self->o('la_pipeline_dir'),
                nextflow_pipeline_name    => 'load_assembly',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('load_assembly'),
                nextflow_resume_mode      => $self->o('nextflow_resume_mode'),
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_extra_flags      => $self->o('nextflow_extra_flags'),
                nextflow_params           => {
                    assembly_accession => $self->o('assembly_accession'),
                    assembly_name      => $self->o('assembly_name'),
                },
                nextflow_dataflow_outputs => 0,   # suppress multi-entry manifest fan
            },
            -rc_name         => 'nextflow_launcher',
            -max_retry_count => 2,
            -flow_into       => { 1 => ['RunRepeatMasking'] },
        },

        # ------------------------------------------------------------------
        # Stage 1b: Repeat masking
        # nextflow_dataflow_outputs => 0: suppress manifest fan; paths hardcoded above
        # ------------------------------------------------------------------
        {
            -logic_name      => 'RunRepeatMasking',
            -module          => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters      => {
                nextflow_binary           => $self->o('nextflow_binary'),
                nextflow_pipeline_dir     => $self->o('rm_pipeline_dir'),
                nextflow_pipeline_name    => 'repeat_masking',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('repeat_masking'),
                nextflow_resume_mode      => $self->o('nextflow_resume_mode'),
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_extra_flags      => $self->o('nextflow_extra_flags'),
                nextflow_params           => {
                    genome_fasta       => $genome_fasta,
                    repbase_library    => $self->o('rm_repbase_library'),
                    custom_library     => $self->o('rm_custom_library'),
                    species            => $self->o('rm_species'),
                    skip_repeatmodeler => $self->o('rm_skip_repeatmodeler'),
                    skip_red           => $self->o('rm_skip_red'),
                    skip_trf           => $self->o('rm_skip_trf'),
                    skip_dust          => $self->o('rm_skip_dust'),
                    chunk_size         => $self->o('rm_chunk_size'),
                    repeatmasker_threads => $self->o('rm_threads'),
                },
                nextflow_dataflow_outputs => 0,   # suppress multi-entry manifest fan
            },
            -rc_name         => 'nextflow_launcher',
            -max_retry_count => 2,
            -flow_into       => { 1 => ['FanAnnotationLayers'] },
        },

        # ------------------------------------------------------------------
        # Stage 2: Fan all annotation layers in parallel, funnel into Consolidate
        # eHive semaphore: 1->A fans N jobs; A->1 triggers funnel once all done
        # ------------------------------------------------------------------
        {
            -logic_name  => 'FanAnnotationLayers',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => { cmd => 'echo "Fanning annotation layers."' },
            -rc_name     => '1GB',
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
        },

        # --- RNA-seq ---
        {
            -logic_name      => 'RunRnaSeq',
            -module          => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters      => {
                nextflow_binary           => $self->o('nextflow_binary'),
                nextflow_pipeline_dir     => $self->o('rs_pipeline_dir'),
                nextflow_pipeline_name    => 'rnaseq',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('rnaseq'),
                nextflow_resume_mode      => $self->o('nextflow_resume_mode'),
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_extra_flags      => $self->o('nextflow_extra_flags'),
                nextflow_params           => {
                    genome_fasta   => $softmasked_fasta,
                    sample_sheet   => $self->o('rs_sample_sheet'),
                    star_index     => $self->o('rs_star_index'),
                    annotation_gtf => $self->o('rs_annotation_gtf'),
                },
                nextflow_dataflow_outputs => 0,
            },
            -rc_name         => 'nextflow_launcher_himem',
            -max_retry_count => 2,
        },

        # --- Best-targeted ---
        {
            -logic_name      => 'RunBestTargeted',
            -module          => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters      => {
                nextflow_binary           => $self->o('nextflow_binary'),
                nextflow_pipeline_dir     => $self->o('bt_pipeline_dir'),
                nextflow_pipeline_name    => 'best_targeted',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('best_targeted'),
                nextflow_resume_mode      => $self->o('nextflow_resume_mode'),
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_extra_flags      => $self->o('nextflow_extra_flags'),
                nextflow_params           => {
                    genome_fasta  => $softmasked_fasta,
                    cdna_fasta    => $self->o('bt_cdna_fasta'),
                    protein_fasta => $self->o('bt_protein_fasta'),
                },
                nextflow_dataflow_outputs => 0,
            },
            -rc_name         => 'nextflow_launcher',
            -max_retry_count => 2,
        },

        # --- Projection ---
        {
            -logic_name      => 'RunProjection',
            -module          => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters      => {
                nextflow_binary           => $self->o('nextflow_binary'),
                nextflow_pipeline_dir     => $self->o('proj_pipeline_dir'),
                nextflow_pipeline_name    => 'projection',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('projection'),
                nextflow_resume_mode      => $self->o('nextflow_resume_mode'),
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_extra_flags      => $self->o('nextflow_extra_flags'),
                nextflow_params           => {
                    source_fasta => $self->o('proj_source_fasta'),
                    query_fasta  => $softmasked_fasta,
                    source_gff3  => $self->o('proj_source_gff3'),
                    chain        => $self->o('proj_chain'),
                },
                nextflow_dataflow_outputs => 0,
            },
            -rc_name         => 'nextflow_launcher',
            -max_retry_count => 2,
        },

        # --- Ab initio ---
        {
            -logic_name      => 'RunAbInitio',
            -module          => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters      => {
                nextflow_binary           => $self->o('nextflow_binary'),
                nextflow_pipeline_dir     => $self->o('ai_pipeline_dir'),
                nextflow_pipeline_name    => 'ab_initio',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('ab_initio'),
                nextflow_resume_mode      => $self->o('nextflow_resume_mode'),
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_extra_flags      => $self->o('nextflow_extra_flags'),
                nextflow_params           => {
                    genome_fasta         => $softmasked_fasta,
                    species              => $self->o('ai_species'),
                    augustus_config_path => $self->o('ai_augustus_config_path'),
                    extrinsic_cfg        => $self->o('ai_extrinsic_cfg'),
                },
                nextflow_dataflow_outputs => 0,
            },
            -rc_name         => 'nextflow_launcher',
            -max_retry_count => 2,
        },

        # --- IGTR ---
        {
            -logic_name      => 'RunIgtr',
            -module          => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters      => {
                nextflow_binary           => $self->o('nextflow_binary'),
                nextflow_pipeline_dir     => $self->o('igtr_pipeline_dir'),
                nextflow_pipeline_name    => 'igtr',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('igtr'),
                nextflow_resume_mode      => $self->o('nextflow_resume_mode'),
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_extra_flags      => $self->o('nextflow_extra_flags'),
                nextflow_params           => {
                    genome_fasta  => $genome_fasta,
                    igtr_proteins => $self->o('igtr_proteins'),
                },
                nextflow_dataflow_outputs => 0,
            },
            -rc_name         => 'nextflow_launcher',
            -max_retry_count => 2,
        },

        # --- Long-read ---
        {
            -logic_name      => 'RunLongRead',
            -module          => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters      => {
                nextflow_binary           => $self->o('nextflow_binary'),
                nextflow_pipeline_dir     => $self->o('lr_pipeline_dir'),
                nextflow_pipeline_name    => 'long_read',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('long_read'),
                nextflow_resume_mode      => $self->o('nextflow_resume_mode'),
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_extra_flags      => $self->o('nextflow_extra_flags'),
                nextflow_params           => {
                    sample_sheet         => $self->o('lr_sample_sheet'),
                    genome_fasta         => $genome_fasta,
                    protein_db           => $self->o('lr_protein_db'),
                    genome_index         => $self->o('lr_genome_index'),
                    minimap2_preset      => $self->o('lr_minimap2_preset'),
                    collapse_min_overlap => $self->o('lr_min_overlap'),
                    max_intron_size      => $self->o('lr_max_intron'),
                    blast_evalue         => $self->o('lr_blast_evalue'),
                    skip_download        => $self->o('lr_skip_download'),
                },
                nextflow_dataflow_outputs => 0,
            },
            -rc_name         => 'nextflow_launcher',
            -max_retry_count => 2,
        },

        # --- GenBlast homology ---
        {
            -logic_name      => 'RunGenblastHomology',
            -module          => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters      => {
                nextflow_binary           => $self->o('nextflow_binary'),
                nextflow_pipeline_dir     => $self->o('gb_pipeline_dir'),
                nextflow_pipeline_name    => 'genblast_homology',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('genblast_homology'),
                nextflow_resume_mode      => $self->o('nextflow_resume_mode'),
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_extra_flags      => $self->o('nextflow_extra_flags'),
                nextflow_params           => {
                    genome_fasta  => $softmasked_fasta,
                    uniprot_fasta => $self->o('gb_uniprot_fasta'),
                },
                nextflow_dataflow_outputs => 0,
            },
            -rc_name         => 'nextflow_launcher',
            -max_retry_count => 2,
        },

        # --- Short ncRNA ---
        {
            -logic_name      => 'RunShortNcrna',
            -module          => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters      => {
                nextflow_binary           => $self->o('nextflow_binary'),
                nextflow_pipeline_dir     => $self->o('nc_pipeline_dir'),
                nextflow_pipeline_name    => 'short_ncrna',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('short_ncrna'),
                nextflow_resume_mode      => $self->o('nextflow_resume_mode'),
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_extra_flags      => $self->o('nextflow_extra_flags'),
                nextflow_params           => {
                    genome_fasta   => $genome_fasta,
                    rfam_cm        => $self->o('nc_rfam_cm'),
                    mirna_fasta    => $self->o('nc_mirna_fasta'),
                    mirna_blast_db => $self->o('nc_mirna_blast_db'),
                },
                nextflow_dataflow_outputs => 0,
            },
            -rc_name         => 'nextflow_launcher',
            -max_retry_count => 2,
        },

        # --- RefSeq import ---
        # Uses synonyms_tsv from load_assembly to remap RefSeq seq-region names
        {
            -logic_name      => 'RunRefseqImport',
            -module          => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters      => {
                nextflow_binary           => $self->o('nextflow_binary'),
                nextflow_pipeline_dir     => $self->o('ri_pipeline_dir'),
                nextflow_pipeline_name    => 'refseq_import',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('refseq_import'),
                nextflow_resume_mode      => $self->o('nextflow_resume_mode'),
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_extra_flags      => $self->o('nextflow_extra_flags'),
                nextflow_params           => {
                    assembly_refseq_accession => $self->o('ri_refseq_accession'),
                    assembly_name             => $self->o('assembly_name'),
                    synonyms_tsv              => $synonyms_tsv,
                },
                nextflow_dataflow_outputs => 0,
            },
            -rc_name         => 'nextflow_launcher',
            -max_retry_count => 2,
        },

        # ------------------------------------------------------------------
        # Stage 3a: Consolidate — triggered once ALL annotation layers finish
        # Scans outdir recursively for **/*.gff3 from all layer output dirs
        # ------------------------------------------------------------------
        {
            -logic_name      => 'RunConsolidate',
            -module          => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters      => {
                nextflow_binary           => $self->o('nextflow_binary'),
                nextflow_pipeline_dir     => $self->o('con_pipeline_dir'),
                nextflow_pipeline_name    => 'consolidate',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('consolidate'),
                nextflow_resume_mode      => $self->o('nextflow_resume_mode'),
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_extra_flags      => $self->o('nextflow_extra_flags'),
                nextflow_params           => {
                    gff3_dir         => $self->o('nextflow_output_root'),
                    layer_priorities => $self->o('con_layer_priorities'),
                },
                nextflow_dataflow_outputs => 1,
            },
            -rc_name         => 'nextflow_launcher',
            -max_retry_count => 2,
            -flow_into       => {
                2 => ['RunUtrAddition'],   # consolidated_gff3 path from manifest
            },
        },

        # ------------------------------------------------------------------
        # Stage 3b: UTR addition
        # ------------------------------------------------------------------
        {
            -logic_name      => 'RunUtrAddition',
            -module          => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters      => {
                nextflow_binary           => $self->o('nextflow_binary'),
                nextflow_pipeline_dir     => $self->o('utr_pipeline_dir'),
                nextflow_pipeline_name    => 'utr_addition',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('utr_addition'),
                nextflow_resume_mode      => $self->o('nextflow_resume_mode'),
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_extra_flags      => $self->o('nextflow_extra_flags'),
                nextflow_params           => {
                    consolidated_gff3 => '#path#',   # injected from RunConsolidate ch2
                    donor_gff3_files  => $donor_gff3_files,
                    max_5prime_utr    => $self->o('utr_max_5prime'),
                    max_3prime_utr    => $self->o('utr_max_3prime'),
                    min_utr_exon_size => $self->o('utr_min_exon_size'),
                },
                nextflow_dataflow_outputs => 1,
            },
            -rc_name         => 'nextflow_launcher',
            -max_retry_count => 2,
            -flow_into       => {
                2 => ['RunFinaliseGeneset'],   # utr_added_gff3 path from manifest
            },
        },

        # ------------------------------------------------------------------
        # Stage 3c: Finalise geneset
        # ------------------------------------------------------------------
        {
            -logic_name      => 'RunFinaliseGeneset',
            -module          => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters      => {
                nextflow_binary           => $self->o('nextflow_binary'),
                nextflow_pipeline_dir     => $self->o('fg_pipeline_dir'),
                nextflow_pipeline_name    => 'finalise_geneset',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->_outdir('finalise_geneset'),
                nextflow_resume_mode      => $self->o('nextflow_resume_mode'),
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_extra_flags      => $self->o('nextflow_extra_flags'),
                nextflow_params           => {
                    input_gff3              => '#path#',   # injected from RunUtrAddition ch2
                    repeat_gff3             => $repeat_gff3_glob,
                    min_orf_aa              => $self->o('fg_min_orf_aa'),
                    min_intron_size         => $self->o('fg_min_intron_size'),
                    max_repeat_cds_coverage => $self->o('fg_max_repeat_cds_cov'),
                    max_readthrough_gap     => $self->o('fg_max_readthrough_gap'),
                    selenoprotein_fasta     => $self->o('fg_selenoprotein_fasta'),
                },
                nextflow_dataflow_outputs => 1,
            },
            -rc_name         => 'nextflow_launcher',
            -max_retry_count => 2,
            -flow_into       => {
                2 => ['ConsumeFinalGeneset'],
            },
        },

        # ------------------------------------------------------------------
        # Stage 4: Consume final gene set — extend to core DB loader when ready
        # ------------------------------------------------------------------
        {
            -logic_name => 'ConsumeFinalGeneset',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => {
                cmd => 'echo "Final annotation complete. GFF3: #path# (type=#type#)"',
            },
            -rc_name => '1GB',
        },

    ];
}


1;
