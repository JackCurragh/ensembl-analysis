=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute
Licensed under the Apache License, Version 2.0.

=head1 DESCRIPTION

eHive pipeline configuration for the ensembl-genes-nf short_ncrna pipeline.
Searches for ncRNA loci using Rfam covariance models (cmsearch) and miRBase
BLAST, working on the unmasked genome.

=head2 Typical init command

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::NextflowShortNcrna_conf \
    -pipeline_db -host=<host> -pipeline_db -port=<port>                           \
    -pipeline_db -dbname=${USER}_short_ncrna_nf_pipe                              \
    -nextflow_work_root   /hps/nobackup/flicek/ensembl/genebuild/nextflow_work    \
    -nextflow_output_root /hps/nobackup/flicek/ensembl/genebuild/nextflow_output  \
    -nextflow_pipeline_dir /path/to/ensembl-genes-nf/pipelines/short_ncrna        \
    -nc_genome_fasta   /path/to/genome.fa                                          \
    -nc_rfam_cm        /path/to/Rfam.cm

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::NextflowShortNcrna_conf;

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

        pipeline_name          => 'nextflow_short_ncrna',
        nextflow_pipeline_name => 'short_ncrna',
        nextflow_pipeline_dir  => '/path/to/ensembl-genes-nf/pipelines/short_ncrna',
        nextflow_resume_mode   => 'attempt',
        nextflow_profile       => 'slurm',
        nextflow_work_root     => undef,
        nextflow_output_root   => undef,

        # --- short_ncrna pipeline parameters ---
        nc_genome_fasta   => undef,   # unmasked genome FASTA
        nc_rfam_cm        => undef,   # Rfam covariance models file
        nc_mirna_fasta    => undef,   # miRBase mature miRNA FASTA; optional
        nc_mirna_blast_db => undef,   # pre-built miRBase BLAST db; optional
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    my $nf_params = {
        genome_fasta   => $self->o('nc_genome_fasta'),
        rfam_cm        => $self->o('nc_rfam_cm'),
        mirna_fasta    => $self->o('nc_mirna_fasta'),
        mirna_blast_db => $self->o('nc_mirna_blast_db'),
    };

    return [

        {
            -logic_name  => 'check_inputs',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => {
                nc_genome_fasta => $self->o('nc_genome_fasta'),
                nc_rfam_cm      => $self->o('nc_rfam_cm'),
                cmd => 'test -f #nc_genome_fasta# && test -f #nc_rfam_cm#',
            },
            -rc_name   => '1GB',
            -input_ids => [{}],
            -flow_into => { 1 => ['run_short_ncrna'] },
        },

        {
            -logic_name      => 'run_short_ncrna',
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
                2 => ['consume_ncrna_output'],
            },
        },

        {
            -logic_name => 'consume_ncrna_output',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => { cmd => 'echo "Short ncRNA output: type=#type# path=#path#"' },
            -rc_name    => '1GB',
        },

        {
            -logic_name  => 'pipeline_complete',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => { cmd => 'echo "Short ncRNA pipeline complete."' },
            -rc_name     => '1GB',
        },

    ];
}


1;
