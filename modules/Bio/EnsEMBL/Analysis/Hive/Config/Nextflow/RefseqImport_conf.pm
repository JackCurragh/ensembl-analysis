=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

=head1 NAME

Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::RefseqImport_conf

=head1 DESCRIPTION

eHive pipeline that runs the Nextflow refseq_import pipeline (downloads and
parses RefSeq annotation for a given assembly) and dataflows output paths on
channel 2.

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::RefseqImport_conf;

use strict;
use warnings;

use parent ('Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::NfPipelineBase_conf');


sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },

        assembly_refseq_accession   => undef,   # e.g. GCF_000001405.40
        assembly_name               => undef,   # e.g. GRCh38.p14
        synonyms_tsv                => undef,   # RefSeq accession → chr name TSV (optional)
        keep_patches                => 0,       # include NT_/NW_ scaffold sequences
    };
}


sub pipeline_wide_parameters {
    my ($self) = @_;
    return {
        %{ $self->SUPER::pipeline_wide_parameters() },
        pipeline_name => 'refseq_import',
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    my %nf_params = (
        assembly_refseq_accession => $self->o('assembly_refseq_accession'),
        assembly_name             => $self->o('assembly_name'),
        keep_patches              => $self->o('keep_patches'),
        outdir                    => $self->o('outdir'),
    );
    $nf_params{synonyms_tsv} = $self->o('synonyms_tsv') if defined $self->o('synonyms_tsv');

    return [

        {
            -logic_name  => 'SeedRefseqImport',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -input_ids   => [{}],
            -flow_into   => { 1 => 'RunRefseqImport' },
            -meadow_type => 'LOCAL',
        },

        {
            -logic_name  => 'RunRefseqImport',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir     => $self->o('nf_pipeline_dir'),
                nextflow_pipeline_name    => 'refseq_import',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->o('outdir'),
                nextflow_resume_mode      => 'attempt',
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_params           => \%nf_params,
                nextflow_dataflow_outputs => 1,
                nextflow_binary           => $self->_nf_binary(),
            },
            -rc_name         => 'small_long',
            -flow_into       => { 2 => 'ConsumeRefseqImportOutput' },
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'ConsumeRefseqImportOutput',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => { cmd => 'echo "RefseqImport output ready: type=#type# path=#path#"' },
            -meadow_type => 'LOCAL',
        },

    ];
}


1;
