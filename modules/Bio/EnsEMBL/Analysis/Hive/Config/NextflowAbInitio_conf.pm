=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute
Licensed under the Apache License, Version 2.0.

=head1 DESCRIPTION

eHive pipeline configuration for the ensembl-genes-nf ab_initio pipeline.
Runs Augustus ab initio gene prediction on a softmasked genome.

=head2 Typical init command

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::NextflowAbInitio_conf \
    -pipeline_db -host=<host> -pipeline_db -port=<port>                         \
    -pipeline_db -dbname=${USER}_ab_initio_nf_pipe                              \
    -nextflow_work_root   /hps/nobackup/flicek/ensembl/genebuild/nextflow_work  \
    -nextflow_output_root /hps/nobackup/flicek/ensembl/genebuild/nextflow_output \
    -nextflow_pipeline_dir /path/to/ensembl-genes-nf/pipelines/ab_initio        \
    -ai_genome_fasta   /path/to/softmasked.fa                                    \
    -ai_species        human

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::NextflowAbInitio_conf;

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

        pipeline_name          => 'nextflow_ab_initio',
        nextflow_pipeline_name => 'ab_initio',
        nextflow_pipeline_dir  => '/path/to/ensembl-genes-nf/pipelines/ab_initio',
        nextflow_resume_mode   => 'attempt',
        nextflow_profile       => 'slurm',
        nextflow_work_root     => undef,
        nextflow_output_root   => undef,

        # --- ab_initio pipeline parameters ---
        ai_genome_fasta         => undef,   # softmasked genome FASTA
        ai_species              => undef,   # Augustus species model name
        ai_augustus_config_path => undef,   # AUGUSTUS_CONFIG_PATH; optional
        ai_extrinsic_cfg        => undef,   # extrinsic.cfg path; optional
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    my $nf_params = {
        genome_fasta         => $self->o('ai_genome_fasta'),
        species              => $self->o('ai_species'),
        augustus_config_path => $self->o('ai_augustus_config_path'),
        extrinsic_cfg        => $self->o('ai_extrinsic_cfg'),
    };

    return [

        {
            -logic_name  => 'check_inputs',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => {
                ai_genome_fasta => $self->o('ai_genome_fasta'),
                cmd => 'test -f #ai_genome_fasta#',
            },
            -rc_name   => '1GB',
            -input_ids => [{}],
            -flow_into => { 1 => ['run_ab_initio'] },
        },

        {
            -logic_name      => 'run_ab_initio',
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
                2 => ['consume_ab_initio_output'],
            },
        },

        {
            -logic_name => 'consume_ab_initio_output',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => { cmd => 'echo "Ab initio output: type=#type# path=#path#"' },
            -rc_name    => '1GB',
        },

        {
            -logic_name  => 'pipeline_complete',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => { cmd => 'echo "Ab initio pipeline complete."' },
            -rc_name     => '1GB',
        },

    ];
}


1;
