=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

=head1 NAME

Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::LoadAssembly_conf

=head1 DESCRIPTION

eHive pipeline that downloads and prepares a genome assembly from NCBI using
the Nextflow load_assembly pipeline, then dataflows output file paths to a
downstream analysis.

Usage (HPC production):

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::LoadAssembly_conf \
    -pipeline_db    "-host mysql-ens-genebuild-prod -port 4527 -user ensrw -pass XXX -dbname jack_load_assembly_human" \
    -assembly_accession GCA_000001405.29 \
    -assembly_name      GRCh38.p14 \
    -outdir             /hps/scratch/flicek/ensembl/genebuild/grch38/load_assembly \
    -nextflow_work_root /hps/scratch/flicek/ensembl/genebuild/grch38/nf_work \
    -nf_pipeline_dir    /nfs/production/flicek/ensembl/genebuild/ensembl-genes-nf/pipelines/load_assembly

Usage (local testing — SQLite, conda profile):

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::LoadAssembly_conf \
    -pipeline_url   sqlite:////tmp/load_assembly.db \
    -assembly_accession GCA_000001405.29 \
    -assembly_name      GRCh38.p14 \
    -outdir             /tmp/load_assembly_out \
    -nextflow_work_root /tmp/nf_work \
    -nf_pipeline_dir    ~/projects/ensembl-genes-nf/pipelines/load_assembly \
    -nextflow_bin       ~/.local/bin/nextflow \
    -nextflow_profile   conda \
    -java_home          /opt/homebrew/Cellar/openjdk@21/21.0.10/libexec/openjdk.jdk/Contents/Home

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::LoadAssembly_conf;

use strict;
use warnings;

use parent ('Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::NfPipelineBase_conf');


sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },

        assembly_accession  => undef,   # e.g. GCA_000001405.29
        assembly_name       => undef,   # e.g. GRCh38.p14
    };
}


sub pipeline_wide_parameters {
    my ($self) = @_;
    return {
        %{ $self->SUPER::pipeline_wide_parameters() },
        pipeline_name => 'load_assembly',
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    return [

        {
            -logic_name  => 'SeedAssembly',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters  => {
                inputlist    => [ [ $self->o('assembly_accession'), $self->o('assembly_name') ] ],
                column_names => [ 'assembly_accession', 'assembly_name' ],
            },
            -input_ids   => [{}],
            -flow_into   => { 2 => 'RunLoadAssembly' },
            -meadow_type => 'LOCAL',
        },

        {
            -logic_name  => 'RunLoadAssembly',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir  => $self->o('nf_pipeline_dir'),
                nextflow_pipeline_name => 'load_assembly',
                nextflow_work_root     => $self->o('nextflow_work_root'),
                nextflow_output_dir    => $self->o('outdir'),
                nextflow_resume_mode   => 'attempt',
                nextflow_profile       => $self->o('nextflow_profile'),
                nextflow_params        => {
                    assembly_accession => '#assembly_accession#',
                    assembly_name      => '#assembly_name#',
                    outdir             => $self->o('outdir'),
                },
                nextflow_dataflow_outputs => 1,
                nextflow_binary           => $self->_nf_binary(),
            },
            -rc_name         => 'small_long',
            -flow_into       => { 2 => 'ConsumeAssemblyOutput' },
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'ConsumeAssemblyOutput',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => {
                cmd => 'echo "Assembly output ready: type=#type# path=#path#"',
            },
            -meadow_type => 'LOCAL',
        },

    ];
}


1;
