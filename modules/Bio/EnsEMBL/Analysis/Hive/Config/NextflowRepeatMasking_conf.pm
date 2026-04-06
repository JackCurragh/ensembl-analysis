=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute
Licensed under the Apache License, Version 2.0.

=head1 DESCRIPTION

eHive pipeline configuration for running the ensembl-genes-nf repeat_masking
Nextflow pipeline via HiveRunNextflow. Replaces RepeatMasking.pm.

On completion, HiveRunNextflow reads output_manifest.json and dataflows the
softmasked FASTA and repeat GFF3 paths on channel 2 for downstream pipelines.

=head2 Typical init command

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::NextflowRepeatMasking_conf \
    -pipeline_db -host=<host> -pipeline_db -port=<port>                              \
    -pipeline_db -dbname=${USER}_repeat_masking_nf_pipe                              \
    -nextflow_work_root   /hps/nobackup/flicek/ensembl/genebuild/nextflow_work       \
    -nextflow_output_root /hps/nobackup/flicek/ensembl/genebuild/nextflow_output     \
    -nextflow_pipeline_dir /path/to/ensembl-genes-nf/pipelines/repeat_masking        \
    -rm_genome_fasta      /path/to/genome.fa                                          \
    -rm_repbase_library   /path/to/RepeatMaskerLib.h5

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::NextflowRepeatMasking_conf;

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

        pipeline_name          => 'nextflow_repeat_masking',
        nextflow_pipeline_name => 'repeat_masking',
        nextflow_pipeline_dir  => '/path/to/ensembl-genes-nf/pipelines/repeat_masking',
        nextflow_resume_mode   => 'attempt',
        nextflow_profile       => 'slurm',
        nextflow_work_root     => undef,
        nextflow_output_root   => undef,

        # --- repeat_masking pipeline parameters ---
        rm_genome_fasta       => undef,   # required: path to unmasked genome FASTA
        rm_repbase_library    => undef,   # RepBase library (.h5); undef = use -species
        rm_custom_library     => undef,   # custom RepeatModeler library FASTA; optional
        rm_species            => 'mammals',
        rm_skip_repeatmodeler => 'true',  # default: skip; set 'false' to run RepeatModeler
        rm_skip_red           => 'false',
        rm_skip_trf           => 'false',
        rm_skip_dust          => 'false',
        rm_chunk_size         => 10000000,
        rm_threads            => 4,
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    my $nf_params = {
        genome_fasta       => $self->o('rm_genome_fasta'),
        repbase_library    => $self->o('rm_repbase_library'),
        custom_library     => $self->o('rm_custom_library'),
        species            => $self->o('rm_species'),
        skip_repeatmodeler => $self->o('rm_skip_repeatmodeler'),
        skip_red           => $self->o('rm_skip_red'),
        skip_trf           => $self->o('rm_skip_trf'),
        skip_dust          => $self->o('rm_skip_dust'),
        chunk_size         => $self->o('rm_chunk_size'),
        repeatmasker_threads => $self->o('rm_threads'),
    };

    return [

        {
            -logic_name  => 'check_inputs',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => {
                rm_genome_fasta => $self->o('rm_genome_fasta'),
                cmd => 'test -f #rm_genome_fasta#',
            },
            -rc_name   => '1GB',
            -input_ids => [{}],
            -flow_into => { 1 => ['run_repeat_masking'] },
        },

        {
            -logic_name      => 'run_repeat_masking',
            -module          => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters      => {
                nextflow_binary            => $self->o('nextflow_binary'),
                nextflow_pipeline_dir      => $self->o('nextflow_pipeline_dir'),
                nextflow_pipeline_name     => $self->o('nextflow_pipeline_name'),
                nextflow_work_root         => $self->o('nextflow_work_root'),
                nextflow_output_dir        => catdir(
                    $self->o('nextflow_output_root'),
                    $self->o('nextflow_pipeline_name'),
                ),
                nextflow_resume_mode       => $self->o('nextflow_resume_mode'),
                nextflow_profile           => $self->o('nextflow_profile'),
                nextflow_extra_flags       => $self->o('nextflow_extra_flags'),
                nextflow_params            => $nf_params,
                nextflow_dataflow_outputs  => 1,
            },
            -rc_name         => 'nextflow_launcher',
            -max_retry_count => 2,
            -flow_into       => {
                1 => ['pipeline_complete'],
                2 => ['consume_repeat_output'],
            },
        },

        # Consume each output (softmasked FASTA, repeat GFF3) from the manifest.
        # Extend this to pass paths into downstream pipelines (genblast, rnaseq etc.)
        {
            -logic_name => 'consume_repeat_output',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => {
                cmd => 'echo "Repeat output: type=#type# path=#path#"',
            },
            -rc_name => '1GB',
        },

        {
            -logic_name  => 'pipeline_complete',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => {
                cmd => 'echo "Repeat masking complete."',
            },
            -rc_name => '1GB',
        },

    ];
}


1;
