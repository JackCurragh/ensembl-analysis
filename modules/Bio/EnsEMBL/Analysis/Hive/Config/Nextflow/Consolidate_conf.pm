=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

=head1 NAME

Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::Consolidate_conf

=head1 DESCRIPTION

eHive pipeline that runs the Nextflow consolidate pipeline (multi-layer gene
merging with priority-based overlap resolution) and dataflows output paths on
channel 2.

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::Consolidate_conf;

use strict;
use warnings;

use parent ('Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::NfPipelineBase_conf');


sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },

        # Provide gff3_dir OR gff3_files
        gff3_dir    => undef,   # directory containing *.gff3 files
        gff3_files  => undef,   # glob or comma-separated list of GFF3 files
    };
}


sub pipeline_wide_parameters {
    my ($self) = @_;
    return {
        %{ $self->SUPER::pipeline_wide_parameters() },
        pipeline_name => 'consolidate',
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    my %nf_params = (outdir => $self->o('outdir'));
    $nf_params{gff3_dir}   = $self->o('gff3_dir')   if defined $self->o('gff3_dir');
    $nf_params{gff3_files} = $self->o('gff3_files') if defined $self->o('gff3_files');

    return [

        {
            -logic_name  => 'SeedConsolidate',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -input_ids   => [{}],
            -flow_into   => { 1 => 'RunConsolidate' },
            -meadow_type => 'LOCAL',
        },

        {
            -logic_name  => 'RunConsolidate',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir     => $self->o('nf_pipeline_dir'),
                nextflow_pipeline_name    => 'consolidate',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->o('outdir'),
                nextflow_resume_mode      => 'attempt',
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_params           => \%nf_params,
                nextflow_dataflow_outputs => 1,
                nextflow_binary           => $self->_nf_binary(),
            },
            -rc_name         => 'medium_long',
            -flow_into       => { 2 => 'ConsumeConsolidateOutput' },
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'ConsumeConsolidateOutput',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => { cmd => 'echo "Consolidate output ready: type=#type# path=#path#"' },
            -meadow_type => 'LOCAL',
        },

    ];
}


1;
