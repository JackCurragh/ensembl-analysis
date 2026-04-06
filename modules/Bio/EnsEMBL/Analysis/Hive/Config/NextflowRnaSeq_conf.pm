=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute
Licensed under the Apache License, Version 2.0.

=head1 DESCRIPTION

eHive pipeline configuration for running the ensembl-genes-nf rnaseq
Nextflow pipeline via HiveRunNextflow. Aligns short-read RNA-seq with STAR
and assembles transcripts with StringTie2.

=head2 Typical init command

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::NextflowRnaSeq_conf \
    -pipeline_db -host=<host> -pipeline_db -port=<port>                       \
    -pipeline_db -dbname=${USER}_rnaseq_nf_pipe                               \
    -nextflow_work_root   /hps/nobackup/flicek/ensembl/genebuild/nextflow_work \
    -nextflow_output_root /hps/nobackup/flicek/ensembl/genebuild/nextflow_output \
    -nextflow_pipeline_dir /path/to/ensembl-genes-nf/pipelines/rnaseq         \
    -rs_genome_fasta   /path/to/genome.fa                                      \
    -rs_sample_sheet   /path/to/rnaseq_samples.csv

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::NextflowRnaSeq_conf;

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

        pipeline_name          => 'nextflow_rnaseq',
        nextflow_pipeline_name => 'rnaseq',
        nextflow_pipeline_dir  => '/path/to/ensembl-genes-nf/pipelines/rnaseq',
        nextflow_resume_mode   => 'attempt',
        nextflow_profile       => 'slurm',
        nextflow_work_root     => undef,
        nextflow_output_root   => undef,

        # --- rnaseq pipeline parameters ---
        rs_genome_fasta   => undef,   # softmasked genome FASTA
        rs_sample_sheet   => undef,   # CSV: sample,fastq_1,fastq_2
        rs_star_index     => undef,   # pre-built STAR index; built if absent
        rs_annotation_gtf => undef,   # guide GTF for StringTie2; optional
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    my $nf_params = {
        genome_fasta    => $self->o('rs_genome_fasta'),
        sample_sheet    => $self->o('rs_sample_sheet'),
        star_index      => $self->o('rs_star_index'),
        annotation_gtf  => $self->o('rs_annotation_gtf'),
    };

    return [

        {
            -logic_name  => 'check_inputs',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => {
                rs_genome_fasta => $self->o('rs_genome_fasta'),
                rs_sample_sheet => $self->o('rs_sample_sheet'),
                cmd => 'test -f #rs_genome_fasta# && test -f #rs_sample_sheet#',
            },
            -rc_name   => '1GB',
            -input_ids => [{}],
            -flow_into => { 1 => ['run_rnaseq'] },
        },

        {
            -logic_name      => 'run_rnaseq',
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
            -rc_name         => 'nextflow_launcher_himem',
            -max_retry_count => 2,
            -flow_into       => {
                1 => ['pipeline_complete'],
                2 => ['consume_rnaseq_output'],
            },
        },

        {
            -logic_name => 'consume_rnaseq_output',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => {
                cmd => 'echo "RNA-seq output: type=#type# path=#path#"',
            },
            -rc_name => '1GB',
        },

        {
            -logic_name  => 'pipeline_complete',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => { cmd => 'echo "RNA-seq pipeline complete."' },
            -rc_name     => '1GB',
        },

    ];
}


1;
