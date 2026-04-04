=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

=head1 NAME

Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::Igtr_conf

=head1 DESCRIPTION

eHive pipeline that runs the Nextflow igtr pipeline (Immunoglobulin and
T-cell Receptor gene annotation via GenBlast protein homology) and dataflows
output paths on channel 2.

Usage:

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::Igtr_conf \
    -pipeline_db    "-host localhost -port 3306 -user ensrw -pass XXX -dbname igtr_pipe" \
    -genome_fasta   /data/genome/genome_softmasked.fa \
    -igtr_proteins  /data/imgt/imgt_proteins.fa \
    -outdir         /data/output/igtr \
    -nextflow_work_root /data/nf_work \
    -nf_pipeline_dir    /path/to/ensembl-genes-nf/pipelines/igtr

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::Igtr_conf;

use strict;
use warnings;

use parent ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');


sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },

        # ----------------------------------------------------------------
        # Required inputs
        # ----------------------------------------------------------------
        genome_fasta        => undef,   # softmasked genome FASTA
        igtr_proteins       => undef,   # IMGT IG/TR protein FASTA

        # ----------------------------------------------------------------
        # Paths
        # ----------------------------------------------------------------
        outdir              => undef,
        nextflow_work_root  => undef,
        nf_pipeline_dir     => undef,

        # ----------------------------------------------------------------
        # Nextflow config
        # ----------------------------------------------------------------
        nextflow_bin        => 'nextflow',
        nextflow_profile    => 'local',
        java_home           => '/opt/homebrew/Cellar/openjdk@21/21.0.10/libexec/openjdk.jdk/Contents/Home',
    };
}


sub pipeline_wide_parameters {
    my ($self) = @_;
    return {
        %{ $self->SUPER::pipeline_wide_parameters() },
        pipeline_name => 'igtr',
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    return [

        {
            -logic_name  => 'SeedIgtr',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -input_ids   => [{}],
            -flow_into   => { 1 => 'RunIgtr' },
            -meadow_type => 'LOCAL',
        },

        {
            -logic_name  => 'RunIgtr',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir  => $self->o('nf_pipeline_dir'),
                nextflow_pipeline_name => 'igtr',
                nextflow_work_root     => $self->o('nextflow_work_root'),
                nextflow_output_dir    => $self->o('outdir'),
                nextflow_resume_mode   => 'attempt',
                nextflow_profile       => $self->o('nextflow_profile'),
                nextflow_params        => {
                    genome_fasta   => $self->o('genome_fasta'),
                    igtr_proteins  => $self->o('igtr_proteins'),
                    outdir         => $self->o('outdir'),
                },
                nextflow_dataflow_outputs => 1,
                nextflow_binary => 'JAVA_HOME=' . $self->o('java_home')
                    . ' PATH=' . $self->o('java_home') . '/bin:$PATH '
                    . $self->o('nextflow_bin'),
            },
            -rc_name     => 'medium_long',
            -flow_into   => { 2 => 'ConsumeIgtrOutput' },
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'ConsumeIgtrOutput',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => {
                cmd => 'echo "IGTR output ready: type=#type# path=#path#"',
            },
            -meadow_type => 'LOCAL',
        },

    ];
}


sub resource_classes {
    my ($self) = @_;
    return {
        %{ $self->SUPER::resource_classes() },
        'medium_long' => {
            'LOCAL' => '',
            'LSF'   => '-q normal -M 2000 -R "select[mem>2000] rusage[mem=2000]"',
            'SLURM' => '--partition=long --mem=2G --time=48:00:00',
        },
    };
}


1;
