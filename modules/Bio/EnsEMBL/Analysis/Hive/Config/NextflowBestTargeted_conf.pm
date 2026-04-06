=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute
Licensed under the Apache License, Version 2.0.

=head1 DESCRIPTION

eHive pipeline configuration for the ensembl-genes-nf best_targeted pipeline.
Aligns cDNA and protein sequences against a softmasked genome using Exonerate
and selects the best-scoring model per locus.

=head2 Typical init command

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::NextflowBestTargeted_conf \
    -pipeline_db -host=<host> -pipeline_db -port=<port>                             \
    -pipeline_db -dbname=${USER}_best_targeted_nf_pipe                              \
    -nextflow_work_root   /hps/nobackup/flicek/ensembl/genebuild/nextflow_work      \
    -nextflow_output_root /hps/nobackup/flicek/ensembl/genebuild/nextflow_output    \
    -nextflow_pipeline_dir /path/to/ensembl-genes-nf/pipelines/best_targeted        \
    -bt_genome_fasta   /path/to/softmasked.fa                                        \
    -bt_cdna_fasta     /path/to/cdna.fa                                              \
    -bt_protein_fasta  /path/to/protein.fa

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::NextflowBestTargeted_conf;

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

        pipeline_name          => 'nextflow_best_targeted',
        nextflow_pipeline_name => 'best_targeted',
        nextflow_pipeline_dir  => '/path/to/ensembl-genes-nf/pipelines/best_targeted',
        nextflow_resume_mode   => 'attempt',
        nextflow_profile       => 'slurm',
        nextflow_work_root     => undef,
        nextflow_output_root   => undef,

        # --- best_targeted pipeline parameters ---
        bt_genome_fasta  => undef,   # softmasked genome FASTA
        bt_cdna_fasta    => undef,   # cDNA FASTA; optional (pass NO_FILE if absent)
        bt_protein_fasta => undef,   # protein FASTA; optional
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    my $nf_params = {
        genome_fasta  => $self->o('bt_genome_fasta'),
        cdna_fasta    => $self->o('bt_cdna_fasta'),
        protein_fasta => $self->o('bt_protein_fasta'),
    };

    return [

        {
            -logic_name  => 'check_inputs',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => {
                bt_genome_fasta => $self->o('bt_genome_fasta'),
                cmd => 'test -f #bt_genome_fasta#',
            },
            -rc_name   => '1GB',
            -input_ids => [{}],
            -flow_into => { 1 => ['run_best_targeted'] },
        },

        {
            -logic_name      => 'run_best_targeted',
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
                2 => ['consume_best_targeted_output'],
            },
        },

        {
            -logic_name => 'consume_best_targeted_output',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => { cmd => 'echo "BestTargeted output: type=#type# path=#path#"' },
            -rc_name    => '1GB',
        },

        {
            -logic_name  => 'pipeline_complete',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => { cmd => 'echo "Best-targeted pipeline complete."' },
            -rc_name     => '1GB',
        },

    ];
}


1;
