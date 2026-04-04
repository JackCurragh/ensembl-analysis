=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

=head1 NAME

Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::GenblastHomology_conf

=head1 DESCRIPTION

eHive pipeline that runs the Nextflow genblast_homology pipeline (GenBlast
protein homology search and classification) and dataflows output paths on
channel 2.

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::GenblastHomology_conf;

use strict;
use warnings;

use parent ('Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::NfPipelineBase_conf');


sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },

        genome_fasta    => undef,   # softmasked genome FASTA
        uniprot_fasta   => undef,   # UniProt protein FASTA (clade-specific)
        uniprot_set     => '',      # informational label, e.g. 'mammals_basic'
    };
}


sub pipeline_wide_parameters {
    my ($self) = @_;
    return {
        %{ $self->SUPER::pipeline_wide_parameters() },
        pipeline_name => 'genblast_homology',
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    return [

        {
            -logic_name  => 'SeedGenblastHomology',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -input_ids   => [{}],
            -flow_into   => { 1 => 'RunGenblastHomology' },
            -meadow_type => 'LOCAL',
        },

        {
            -logic_name  => 'RunGenblastHomology',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir     => $self->o('nf_pipeline_dir'),
                nextflow_pipeline_name    => 'genblast_homology',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->o('outdir'),
                nextflow_resume_mode      => 'attempt',
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_params           => {
                    genome_fasta  => $self->o('genome_fasta'),
                    uniprot_fasta => $self->o('uniprot_fasta'),
                    uniprot_set   => $self->o('uniprot_set'),
                    outdir        => $self->o('outdir'),
                },
                nextflow_dataflow_outputs => 1,
                nextflow_binary           => $self->_nf_binary(),
            },
            -rc_name         => 'medium_long',
            -flow_into       => { 2 => 'ConsumeGenblastHomologyOutput' },
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'ConsumeGenblastHomologyOutput',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => { cmd => 'echo "GenblastHomology output ready: type=#type# path=#path#"' },
            -meadow_type => 'LOCAL',
        },

    ];
}


1;
