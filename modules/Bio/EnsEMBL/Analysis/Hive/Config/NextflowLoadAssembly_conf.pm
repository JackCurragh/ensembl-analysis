=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute
Licensed under the Apache License, Version 2.0.

=head1 DESCRIPTION

eHive pipeline configuration for running the ensembl-genes-nf load_assembly
Nextflow pipeline via HiveRunNextflow. Downloads a genome assembly from NCBI
by GCA accession, indexes it, and produces output_manifest.json.

=head2 Typical init command

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::NextflowLoadAssembly_conf \
    -pipeline_db -host=<host> -pipeline_db -port=<port>                             \
    -pipeline_db -dbname=${USER}_load_assembly_nf_pipe                              \
    -nextflow_work_root   /hps/nobackup/flicek/ensembl/genebuild/nextflow_work      \
    -nextflow_output_root /hps/nobackup/flicek/ensembl/genebuild/nextflow_output    \
    -nextflow_pipeline_dir /path/to/ensembl-genes-nf/pipelines/load_assembly        \
    -la_assembly_accession GCA_000001405.29                                          \
    -la_assembly_name      GRCh38.p14

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::NextflowLoadAssembly_conf;

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

        pipeline_name          => 'nextflow_load_assembly',
        nextflow_pipeline_name => 'load_assembly',
        nextflow_pipeline_dir  => '/path/to/ensembl-genes-nf/pipelines/load_assembly',
        nextflow_resume_mode   => 'attempt',
        nextflow_profile       => 'slurm',
        nextflow_work_root     => undef,
        nextflow_output_root   => undef,

        # --- load_assembly pipeline parameters ---
        la_assembly_accession => undef,   # e.g. GCA_000001405.29
        la_assembly_name      => undef,   # e.g. GRCh38.p14
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    my $nf_params = {
        assembly_accession => $self->o('la_assembly_accession'),
        assembly_name      => $self->o('la_assembly_name'),
    };

    return [

        {
            -logic_name  => 'check_inputs',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => {
                la_assembly_accession => $self->o('la_assembly_accession'),
                cmd => 'test -n "#la_assembly_accession#"',
            },
            -rc_name   => '1GB',
            -input_ids => [{}],
            -flow_into => { 1 => ['run_load_assembly'] },
        },

        {
            -logic_name      => 'run_load_assembly',
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
                2 => ['consume_assembly_output'],
            },
        },

        {
            -logic_name => 'consume_assembly_output',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => {
                cmd => 'echo "Assembly output: type=#type# path=#path#"',
            },
            -rc_name => '1GB',
        },

        {
            -logic_name  => 'pipeline_complete',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => { cmd => 'echo "Load assembly complete."' },
            -rc_name     => '1GB',
        },

    ];
}


1;
