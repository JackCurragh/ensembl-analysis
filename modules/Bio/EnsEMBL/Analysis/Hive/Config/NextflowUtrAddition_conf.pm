=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute
Licensed under the Apache License, Version 2.0.

=head1 DESCRIPTION

eHive pipeline configuration for the ensembl-genes-nf utr_addition pipeline.
Extends consolidated coding gene models with UTR regions by matching donor
transcripts (long-read, best-targeted, RNA-seq) based on shared internal CDS
splice junctions. Replaces HiveUTRAddition.pm.

=head2 Typical init command

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::NextflowUtrAddition_conf \
    -pipeline_db -host=<host> -pipeline_db -port=<port>                            \
    -pipeline_db -dbname=${USER}_utr_addition_nf_pipe                              \
    -nextflow_work_root   /hps/nobackup/flicek/ensembl/genebuild/nextflow_work     \
    -nextflow_output_root /hps/nobackup/flicek/ensembl/genebuild/nextflow_output   \
    -nextflow_pipeline_dir /path/to/ensembl-genes-nf/pipelines/utr_addition        \
    -utr_consolidated_gff3  /path/to/consolidated.gff3                              \
    -utr_donor_gff3_files   '/path/to/lr/*.gff3,/path/to/bt/*.gff3'

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::NextflowUtrAddition_conf;

use strict;
use warnings;
use feature 'say';
use File::Spec::Functions qw(catdir);
use base ('Bio::EnsEMBL::Analysis::Hive::Config::NextflowPipelineBase_conf');


sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },

        user        => $ENV{GBUSER},
        password    => $ENV{GBPASS},
        user_r      => $ENV{USER_R} || 'ensro',
        password_r  => undef,
        dna_db_name => '',

        pipeline_name          => 'nextflow_utr_addition',
        nextflow_pipeline_name => 'utr_addition',
        nextflow_pipeline_dir  => '/path/to/ensembl-genes-nf/pipelines/utr_addition',
        nextflow_resume_mode   => 'attempt',
        nextflow_profile       => 'slurm',
        nextflow_work_root     => undef,
        nextflow_output_root   => undef,

        # --- utr_addition pipeline parameters ---
        utr_consolidated_gff3 => undef,   # consolidated coding GFF3 (acceptors)
        utr_donor_gff3_files  => undef,   # comma-separated glob patterns for donor GFF3s
        utr_max_5prime        => 5000,    # max 5' UTR extension (bp)
        utr_max_3prime        => 10000,   # max 3' UTR extension (bp)
        utr_min_exon_size     => 30,      # min UTR exon size to retain (bp)
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    my $nf_params = {
        consolidated_gff3 => $self->o('utr_consolidated_gff3'),
        donor_gff3_files  => $self->o('utr_donor_gff3_files'),
        max_5prime_utr    => $self->o('utr_max_5prime'),
        max_3prime_utr    => $self->o('utr_max_3prime'),
        min_utr_exon_size => $self->o('utr_min_exon_size'),
    };

    return [

        {
            -logic_name  => 'seed_utr_addition',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => {
                utr_consolidated_gff3 => $self->o('utr_consolidated_gff3'),
                cmd => 'test -f #utr_consolidated_gff3#',
            },
            -rc_name   => '1GB',
            -input_ids => [{}],
            -flow_into => { 1 => ['run_utr_addition'] },
        },

        {
            -logic_name      => 'run_utr_addition',
            -module          => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters      => {
                nextflow_binary           => $self->o('nextflow_binary'),
                nextflow_pipeline_dir     => $self->o('nextflow_pipeline_dir'),
                nextflow_pipeline_name    => $self->o('nextflow_pipeline_name'),
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => catdir(
                    $self->o('nextflow_output_root'),
                    $self->o('nextflow_pipeline_name'),
                ),
                nextflow_resume_mode      => $self->o('nextflow_resume_mode'),
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_extra_flags      => $self->o('nextflow_extra_flags'),
                nextflow_params           => $nf_params,
                nextflow_dataflow_outputs => 1,
            },
            -rc_name         => 'nextflow_launcher',
            -max_retry_count => 2,
            -flow_into       => {
                1 => ['pipeline_complete'],
                2 => ['consume_utr_output'],
            },
        },

        {
            -logic_name => 'consume_utr_output',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => { cmd => 'echo "UTR addition output: type=#type# path=#path#"' },
            -rc_name    => '1GB',
        },

        {
            -logic_name  => 'pipeline_complete',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => { cmd => 'echo "UTR addition pipeline complete."' },
            -rc_name     => '1GB',
        },

    ];
}


1;
