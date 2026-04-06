=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute
Licensed under the Apache License, Version 2.0.

=head1 DESCRIPTION

eHive pipeline configuration for the ensembl-genes-nf refseq_import pipeline.
Downloads and parses a RefSeq GFF3 annotation for a given GCA/GCF accession.

=head2 Typical init command

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::NextflowRefseqImport_conf \
    -pipeline_db -host=<host> -pipeline_db -port=<port>                             \
    -pipeline_db -dbname=${USER}_refseq_import_nf_pipe                              \
    -nextflow_work_root   /hps/nobackup/flicek/ensembl/genebuild/nextflow_work      \
    -nextflow_output_root /hps/nobackup/flicek/ensembl/genebuild/nextflow_output    \
    -nextflow_pipeline_dir /path/to/ensembl-genes-nf/pipelines/refseq_import        \
    -ri_assembly_refseq_accession GCF_000001405.40                                   \
    -ri_assembly_name             GRCh38.p14

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::NextflowRefseqImport_conf;

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

        pipeline_name          => 'nextflow_refseq_import',
        nextflow_pipeline_name => 'refseq_import',
        nextflow_pipeline_dir  => '/path/to/ensembl-genes-nf/pipelines/refseq_import',
        nextflow_resume_mode   => 'attempt',
        nextflow_profile       => 'slurm',
        nextflow_work_root     => undef,
        nextflow_output_root   => undef,

        # --- refseq_import pipeline parameters ---
        ri_assembly_refseq_accession => undef,   # GCF accession
        ri_assembly_name             => undef,   # assembly name string
        ri_synonyms_tsv              => undef,   # seq-region synonyms TSV; optional
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    my $nf_params = {
        assembly_refseq_accession => $self->o('ri_assembly_refseq_accession'),
        assembly_name             => $self->o('ri_assembly_name'),
    };

    # Add synonyms_tsv only if defined
    if (defined $self->o('ri_synonyms_tsv')) {
        $nf_params->{synonyms_tsv} = $self->o('ri_synonyms_tsv');
    }

    return [

        {
            -logic_name  => 'check_inputs',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => {
                ri_assembly_refseq_accession => $self->o('ri_assembly_refseq_accession'),
                cmd => 'test -n "#ri_assembly_refseq_accession#"',
            },
            -rc_name   => '1GB',
            -input_ids => [{}],
            -flow_into => { 1 => ['run_refseq_import'] },
        },

        {
            -logic_name      => 'run_refseq_import',
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
                2 => ['consume_refseq_output'],
            },
        },

        {
            -logic_name => 'consume_refseq_output',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => { cmd => 'echo "RefSeq output: type=#type# path=#path#"' },
            -rc_name    => '1GB',
        },

        {
            -logic_name  => 'pipeline_complete',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => { cmd => 'echo "RefSeq import complete."' },
            -rc_name     => '1GB',
        },

    ];
}


1;
