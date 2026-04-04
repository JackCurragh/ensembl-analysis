=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

=head1 NAME

Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::AbInitio_conf

=head1 DESCRIPTION

eHive pipeline that runs the Nextflow ab_initio pipeline (Augustus gene
prediction) and dataflows output paths on channel 2.

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::AbInitio_conf;

use strict;
use warnings;

use parent ('Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::NfPipelineBase_conf');


sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },

        genome_fasta            => undef,   # softmasked genome FASTA
        species                 => undef,   # Augustus species model (e.g. 'human')
        augustus_config_path    => undef,   # path to Augustus config/ dir (optional)
        extrinsic_cfg           => undef,   # extrinsic.M.RM.E.W.cfg for hints (optional)
    };
}


sub pipeline_wide_parameters {
    my ($self) = @_;
    return {
        %{ $self->SUPER::pipeline_wide_parameters() },
        pipeline_name => 'ab_initio',
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    my %nf_params = (
        genome_fasta => $self->o('genome_fasta'),
        species      => $self->o('species'),
        outdir       => $self->o('outdir'),
    );
    $nf_params{augustus_config_path} = $self->o('augustus_config_path') if defined $self->o('augustus_config_path');
    $nf_params{extrinsic_cfg}        = $self->o('extrinsic_cfg')        if defined $self->o('extrinsic_cfg');

    return [

        {
            -logic_name  => 'SeedAbInitio',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -input_ids   => [{}],
            -flow_into   => { 1 => 'RunAbInitio' },
            -meadow_type => 'LOCAL',
        },

        {
            -logic_name  => 'RunAbInitio',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir     => $self->o('nf_pipeline_dir'),
                nextflow_pipeline_name    => 'ab_initio',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->o('outdir'),
                nextflow_resume_mode      => 'attempt',
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_params           => \%nf_params,
                nextflow_dataflow_outputs => 1,
                nextflow_binary           => $self->_nf_binary(),
            },
            -rc_name         => 'medium_long',
            -flow_into       => { 2 => 'ConsumeAbInitioOutput' },
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'ConsumeAbInitioOutput',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => { cmd => 'echo "AbInitio output ready: type=#type# path=#path#"' },
            -meadow_type => 'LOCAL',
        },

    ];
}


1;
