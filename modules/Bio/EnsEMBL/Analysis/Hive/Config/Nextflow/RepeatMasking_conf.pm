=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

=head1 NAME

Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::RepeatMasking_conf

=head1 DESCRIPTION

eHive pipeline that runs the Nextflow repeat_masking pipeline (RepeatMasker,
RED, TRF, DUST masking → softmasked genome FASTA) and dataflows output paths
on channel 2.

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::RepeatMasking_conf;

use strict;
use warnings;

use parent ('Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::NfPipelineBase_conf');


sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },

        genome_fasta        => undef,       # raw / unmasked genome FASTA
        repbase_library     => undef,       # RepBase library .h5 (optional)
        custom_library      => undef,       # custom repeat library FASTA (optional)
        repeat_species      => 'mammals',   # RepeatMasker species clade
        skip_repeatmodeler  => 1,           # RepeatModeler is slow; off by default
        skip_red            => 0,
        skip_trf            => 0,
        skip_dust           => 0,
    };
}


sub pipeline_wide_parameters {
    my ($self) = @_;
    return {
        %{ $self->SUPER::pipeline_wide_parameters() },
        pipeline_name => 'repeat_masking',
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    my %nf_params = (
        genome_fasta       => $self->o('genome_fasta'),
        species            => $self->o('repeat_species'),
        skip_repeatmodeler => $self->o('skip_repeatmodeler'),
        skip_red           => $self->o('skip_red'),
        skip_trf           => $self->o('skip_trf'),
        skip_dust          => $self->o('skip_dust'),
        outdir             => $self->o('outdir'),
    );
    $nf_params{repbase_library}  = $self->o('repbase_library')  if defined $self->o('repbase_library');
    $nf_params{custom_library}   = $self->o('custom_library')   if defined $self->o('custom_library');

    return [

        {
            -logic_name  => 'SeedRepeatMasking',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -input_ids   => [{}],
            -flow_into   => { 1 => 'RunRepeatMasking' },
            -meadow_type => 'LOCAL',
        },

        {
            -logic_name  => 'RunRepeatMasking',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir     => $self->o('nf_pipeline_dir'),
                nextflow_pipeline_name    => 'repeat_masking',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->o('outdir'),
                nextflow_resume_mode      => 'attempt',
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_params           => \%nf_params,
                nextflow_dataflow_outputs => 1,
                nextflow_binary           => $self->_nf_binary(),
            },
            -rc_name         => 'large_long',
            -flow_into       => { 2 => 'ConsumeRepeatMaskingOutput' },
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'ConsumeRepeatMaskingOutput',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => { cmd => 'echo "RepeatMasking output ready: type=#type# path=#path#"' },
            -meadow_type => 'LOCAL',
        },

    ];
}


1;
