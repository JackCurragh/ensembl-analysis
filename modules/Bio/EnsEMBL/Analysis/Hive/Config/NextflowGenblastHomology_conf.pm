=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute
Licensed under the Apache License, Version 2.0.

=head1 DESCRIPTION

eHive pipeline configuration for the ensembl-genes-nf genblast_homology
pipeline. Aligns UniProt proteins against the genome using genblast in
7-tier mode, producing ranked GFF3 outputs.

=head2 Typical init command

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::NextflowGenblastHomology_conf \
    -pipeline_db -host=<host> -pipeline_db -port=<port>                                 \
    -pipeline_db -dbname=${USER}_genblast_homology_nf_pipe                              \
    -nextflow_work_root   /hps/nobackup/flicek/ensembl/genebuild/nextflow_work          \
    -nextflow_output_root /hps/nobackup/flicek/ensembl/genebuild/nextflow_output        \
    -nextflow_pipeline_dir /path/to/ensembl-genes-nf/pipelines/genblast_homology        \
    -gb_genome_fasta   /path/to/genome.fa                                                \
    -gb_uniprot_fasta  /path/to/uniprot_vertebrata.fa

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::NextflowGenblastHomology_conf;

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

        pipeline_name          => 'nextflow_genblast_homology',
        nextflow_pipeline_name => 'genblast_homology',
        nextflow_pipeline_dir  => '/path/to/ensembl-genes-nf/pipelines/genblast_homology',
        nextflow_resume_mode   => 'attempt',
        nextflow_profile       => 'slurm',
        nextflow_work_root     => undef,
        nextflow_output_root   => undef,

        # --- genblast_homology pipeline parameters ---
        gb_genome_fasta  => undef,   # genome FASTA (softmasked)
        gb_uniprot_fasta => undef,   # UniProt FASTA for homology search
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    my $nf_params = {
        genome_fasta  => $self->o('gb_genome_fasta'),
        uniprot_fasta => $self->o('gb_uniprot_fasta'),
    };

    return [

        {
            -logic_name  => 'check_inputs',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => {
                gb_genome_fasta  => $self->o('gb_genome_fasta'),
                gb_uniprot_fasta => $self->o('gb_uniprot_fasta'),
                cmd => 'test -f #gb_genome_fasta# && test -f #gb_uniprot_fasta#',
            },
            -rc_name   => '1GB',
            -input_ids => [{}],
            -flow_into => { 1 => ['run_genblast_homology'] },
        },

        {
            -logic_name      => 'run_genblast_homology',
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
                2 => ['consume_genblast_output'],
            },
        },

        {
            -logic_name => 'consume_genblast_output',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => { cmd => 'echo "GenBlast output: type=#type# path=#path#"' },
            -rc_name    => '1GB',
        },

        {
            -logic_name  => 'pipeline_complete',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => { cmd => 'echo "GenBlast homology pipeline complete."' },
            -rc_name     => '1GB',
        },

    ];
}


1;
