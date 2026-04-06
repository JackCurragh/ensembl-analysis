=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute
Licensed under the Apache License, Version 2.0.

=head1 DESCRIPTION

eHive pipeline configuration for the ensembl-genes-nf consolidate pipeline.
Merges gene models from multiple annotation sources using layer-annotation
priority (long_read > best_targeted > rnaseq > projection > refseq > ab_initio
> genblast). A lower-priority transcript is suppressed only where it overlaps a
higher-priority retained model.

=head2 Typical init command

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::NextflowConsolidate_conf \
    -pipeline_db -host=<host> -pipeline_db -port=<port>                            \
    -pipeline_db -dbname=${USER}_consolidate_nf_pipe                               \
    -nextflow_work_root   /hps/nobackup/flicek/ensembl/genebuild/nextflow_work     \
    -nextflow_output_root /hps/nobackup/flicek/ensembl/genebuild/nextflow_output   \
    -nextflow_pipeline_dir /path/to/ensembl-genes-nf/pipelines/consolidate         \
    -con_gff3_dir         /path/to/annotation_outputs/

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::NextflowConsolidate_conf;

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

        pipeline_name          => 'nextflow_consolidate',
        nextflow_pipeline_name => 'consolidate',
        nextflow_pipeline_dir  => '/path/to/ensembl-genes-nf/pipelines/consolidate',
        nextflow_resume_mode   => 'attempt',
        nextflow_profile       => 'slurm',
        nextflow_work_root     => undef,
        nextflow_output_root   => undef,

        # --- consolidate pipeline parameters ---
        # gff3_dir: directory scanned recursively for **/*.gff3 files
        con_gff3_dir         => undef,
        con_layer_priorities => '{"long_read":0,"best_targeted":1,"rnaseq":2,"projection":3,"refseq":4,"ab_initio":5,"genblast":6}',
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    my $nf_params = {
        gff3_dir         => $self->o('con_gff3_dir'),
        layer_priorities => $self->o('con_layer_priorities'),
    };

    return [

        {
            -logic_name  => 'check_inputs',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => {
                con_gff3_dir => $self->o('con_gff3_dir'),
                cmd => 'test -d #con_gff3_dir#',
            },
            -rc_name   => '1GB',
            -input_ids => [{}],
            -flow_into => { 1 => ['run_consolidate'] },
        },

        {
            -logic_name      => 'run_consolidate',
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
                2 => ['consume_consolidate_output'],
            },
        },

        {
            -logic_name => 'consume_consolidate_output',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => { cmd => 'echo "Consolidate output: type=#type# path=#path#"' },
            -rc_name    => '1GB',
        },

        {
            -logic_name  => 'pipeline_complete',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => { cmd => 'echo "Consolidate pipeline complete."' },
            -rc_name     => '1GB',
        },

    ];
}


1;
