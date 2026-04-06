=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute
Licensed under the Apache License, Version 2.0.

=head1 DESCRIPTION

eHive pipeline configuration for the ensembl-genes-nf projection pipeline.
Projects transcript gene models from a source genome to a query genome via
LASTZ whole-genome alignment chains.

=head2 Typical init command

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::NextflowProjection_conf \
    -pipeline_db -host=<host> -pipeline_db -port=<port>                           \
    -pipeline_db -dbname=${USER}_projection_nf_pipe                               \
    -nextflow_work_root   /hps/nobackup/flicek/ensembl/genebuild/nextflow_work    \
    -nextflow_output_root /hps/nobackup/flicek/ensembl/genebuild/nextflow_output  \
    -nextflow_pipeline_dir /path/to/ensembl-genes-nf/pipelines/projection         \
    -proj_source_fasta   /path/to/source.softmasked.fa                             \
    -proj_query_fasta    /path/to/query.softmasked.fa                              \
    -proj_source_gff3    /path/to/source.gff3

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::NextflowProjection_conf;

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

        pipeline_name          => 'nextflow_projection',
        nextflow_pipeline_name => 'projection',
        nextflow_pipeline_dir  => '/path/to/ensembl-genes-nf/pipelines/projection',
        nextflow_resume_mode   => 'attempt',
        nextflow_profile       => 'slurm',
        nextflow_work_root     => undef,
        nextflow_output_root   => undef,

        # --- projection pipeline parameters ---
        proj_source_fasta => undef,   # softmasked FASTA of source species
        proj_query_fasta  => undef,   # softmasked FASTA of target species
        proj_source_gff3  => undef,   # gene models in source species to project
        proj_chain        => undef,   # pre-built LASTZ chain file; computed if absent
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    my $nf_params = {
        source_fasta => $self->o('proj_source_fasta'),
        query_fasta  => $self->o('proj_query_fasta'),
        source_gff3  => $self->o('proj_source_gff3'),
        chain        => $self->o('proj_chain'),
    };

    return [

        {
            -logic_name  => 'check_inputs',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => {
                proj_source_fasta => $self->o('proj_source_fasta'),
                proj_query_fasta  => $self->o('proj_query_fasta'),
                proj_source_gff3  => $self->o('proj_source_gff3'),
                cmd => 'test -f #proj_source_fasta# && test -f #proj_query_fasta# && test -f #proj_source_gff3#',
            },
            -rc_name   => '1GB',
            -input_ids => [{}],
            -flow_into => { 1 => ['run_projection'] },
        },

        {
            -logic_name      => 'run_projection',
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
                2 => ['consume_projection_output'],
            },
        },

        {
            -logic_name => 'consume_projection_output',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => { cmd => 'echo "Projection output: type=#type# path=#path#"' },
            -rc_name    => '1GB',
        },

        {
            -logic_name  => 'pipeline_complete',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => { cmd => 'echo "Projection pipeline complete."' },
            -rc_name     => '1GB',
        },

    ];
}


1;
