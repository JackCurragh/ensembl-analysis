=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

=head1 NAME

Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::Projection_conf

=head1 DESCRIPTION

eHive pipeline that runs the Nextflow projection pipeline (LASTZ whole-genome
alignment + transcript coordinate liftover) and dataflows output paths on
channel 2.

Usage:

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::Projection_conf \
    -pipeline_db    "-host localhost -port 3306 -user ensrw -pass XXX -dbname projection_pipe" \
    -source_fasta   /data/source/genome_softmasked.fa \
    -query_fasta    /data/target/genome.fa \
    -source_gff3    /data/source/annotation.gff3 \
    -outdir         /data/output/projection \
    -nextflow_work_root /data/nf_work \
    -nf_pipeline_dir    /path/to/ensembl-genes-nf/pipelines/projection

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::Projection_conf;

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
        source_fasta        => undef,   # softmasked source genome FASTA
        query_fasta         => undef,   # target genome FASTA
        source_gff3         => undef,   # source gene annotation GFF3

        # ----------------------------------------------------------------
        # Optional inputs
        # ----------------------------------------------------------------
        chain               => undef,   # pre-built chain file (skips LASTZ)

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
        pipeline_name => 'projection',
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    my %nf_params = (
        source_fasta => $self->o('source_fasta'),
        query_fasta  => $self->o('query_fasta'),
        source_gff3  => $self->o('source_gff3'),
        outdir       => $self->o('outdir'),
    );
    if (defined $self->o('chain')) {
        $nf_params{chain} = $self->o('chain');
    }

    return [

        {
            -logic_name  => 'SeedProjection',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -input_ids   => [{}],
            -flow_into   => { 1 => 'RunProjection' },
            -meadow_type => 'LOCAL',
        },

        {
            -logic_name  => 'RunProjection',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir  => $self->o('nf_pipeline_dir'),
                nextflow_pipeline_name => 'projection',
                nextflow_work_root     => $self->o('nextflow_work_root'),
                nextflow_output_dir    => $self->o('outdir'),
                nextflow_resume_mode   => 'attempt',
                nextflow_profile       => $self->o('nextflow_profile'),
                nextflow_params        => \%nf_params,
                nextflow_dataflow_outputs => 1,
                nextflow_binary => 'JAVA_HOME=' . $self->o('java_home')
                    . ' PATH=' . $self->o('java_home') . '/bin:$PATH '
                    . $self->o('nextflow_bin'),
            },
            -rc_name     => 'medium_long',
            -flow_into   => { 2 => 'ConsumeProjectionOutput' },
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'ConsumeProjectionOutput',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => {
                cmd => 'echo "Projection output ready: type=#type# path=#path#"',
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
