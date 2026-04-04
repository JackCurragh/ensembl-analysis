=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

=head1 NAME

Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::LongRead_conf

=head1 DESCRIPTION

eHive pipeline that runs the Nextflow long_read pipeline (minimap2 alignment,
transcript collapse, UniProt-based classification) and dataflows output paths
on channel 2.

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::LongRead_conf;

use strict;
use warnings;

use parent ('Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::NfPipelineBase_conf');


sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },

        sample_sheet    => undef,   # TSV: id, fastq path, (optional) platform
        genome_fasta    => undef,   # genome FASTA
        protein_db      => undef,   # UniProt BLAST DB path
        genome_index    => undef,   # pre-built minimap2 index (optional)
    };
}


sub pipeline_wide_parameters {
    my ($self) = @_;
    return {
        %{ $self->SUPER::pipeline_wide_parameters() },
        pipeline_name => 'long_read',
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    my %nf_params = (
        sample_sheet => $self->o('sample_sheet'),
        genome_fasta => $self->o('genome_fasta'),
        protein_db   => $self->o('protein_db'),
        outdir       => $self->o('outdir'),
    );
    $nf_params{genome_index} = $self->o('genome_index') if defined $self->o('genome_index');

    return [

        {
            -logic_name  => 'SeedLongRead',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -input_ids   => [{}],
            -flow_into   => { 1 => 'RunLongRead' },
            -meadow_type => 'LOCAL',
        },

        {
            -logic_name  => 'RunLongRead',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir     => $self->o('nf_pipeline_dir'),
                nextflow_pipeline_name    => 'long_read',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->o('outdir'),
                nextflow_resume_mode      => 'attempt',
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_params           => \%nf_params,
                nextflow_dataflow_outputs => 1,
                nextflow_binary           => $self->_nf_binary(),
            },
            -rc_name         => 'large_long',
            -flow_into       => { 2 => 'ConsumeLongReadOutput' },
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'ConsumeLongReadOutput',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => { cmd => 'echo "LongRead output ready: type=#type# path=#path#"' },
            -meadow_type => 'LOCAL',
        },

    ];
}


1;
