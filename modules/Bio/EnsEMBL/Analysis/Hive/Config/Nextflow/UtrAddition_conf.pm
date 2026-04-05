=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

=head1 NAME

Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::UtrAddition_conf

=head1 DESCRIPTION

eHive pipeline that runs the Nextflow utr_addition pipeline (adds UTR
extensions to coding models using long-read, cDNA, and RNA-seq donor
evidence) and dataflows output paths on channel 2.

Typically used downstream of the consolidate pipeline, receiving the
consolidated GFF3 as consolidated_gff3.  Donor evidence GFF3 files are
passed as a comma-separated list (glob patterns accepted when
Channel.fromPath is used in main.nf).

Usage (HPC production — MySQL + SLURM + Singularity):

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::UtrAddition_conf \
    -pipeline_db        "-host mysql-ens-genebuild-prod -port 4527 -user ensrw -pass XXX -dbname jack_grch38_utr" \
    -consolidated_gff3  /hps/scratch/.../consolidate/consolidated.gff3 \
    -donor_gff3_files   "/hps/scratch/.../long_read/**/*.gff3,/hps/scratch/.../best_targeted/**/*.gff3,/hps/scratch/.../rnaseq/**/*.gff3" \
    -outdir             /hps/scratch/flicek/ensembl/genebuild/grch38/utr_addition \
    -nextflow_work_root /hps/scratch/flicek/ensembl/genebuild/grch38/nf_work \
    -nf_pipeline_dir    /nfs/production/flicek/ensembl/genebuild/ensembl-genes-nf/pipelines/utr_addition

  beekeeper.pl -url "$EHIVE_URL" -loop

Usage (local testing with conda):

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::UtrAddition_conf \
    -pipeline_db        "-host 127.0.0.1 -port 3306 -user ensrw -pass XXX -dbname test_utr" \
    -consolidated_gff3  /data/consolidate/consolidated.gff3 \
    -donor_gff3_files   "/data/long_read/**/*.gff3,/data/best_targeted/**/*.gff3,/data/rnaseq/**/*.gff3" \
    -outdir             /data/utr_addition \
    -nextflow_work_root /data/nf_work \
    -nf_pipeline_dir    /path/to/ensembl-genes-nf/pipelines/utr_addition \
    -nextflow_profile   conda \
    -nextflow_path_extra /opt/homebrew/bin \
    -mamba_root_prefix  /Users/me/mamba

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::UtrAddition_conf;

use strict;
use warnings;

use parent ('Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::NfPipelineBase_conf');


sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },

        consolidated_gff3  => undef,   # required: consolidated GFF3 from consolidate pipeline
        donor_gff3_files   => undef,   # required: comma-separated GFF3 paths or glob patterns
                                       #           (long_read, cDNA/best_targeted, rnaseq order)
        max_5prime_utr     => 5000,
        max_3prime_utr     => 10000,
        min_utr_exon_size  => 30,
    };
}


sub pipeline_wide_parameters {
    my ($self) = @_;
    return {
        %{ $self->SUPER::pipeline_wide_parameters() },
        pipeline_name => 'utr_addition',
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    my %nf_params = (
        consolidated_gff3 => $self->o('consolidated_gff3'),
        donor_gff3_files  => $self->o('donor_gff3_files'),
        max_5prime_utr    => $self->o('max_5prime_utr'),
        max_3prime_utr    => $self->o('max_3prime_utr'),
        min_utr_exon_size => $self->o('min_utr_exon_size'),
        outdir            => $self->o('outdir'),
    );

    return [

        {
            -logic_name  => 'SeedUtrAddition',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -input_ids   => [{}],
            -flow_into   => { 1 => 'RunUtrAddition' },
            -meadow_type => 'LOCAL',
        },

        {
            -logic_name  => 'RunUtrAddition',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir     => $self->o('nf_pipeline_dir'),
                nextflow_pipeline_name    => 'utr_addition',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->o('outdir'),
                nextflow_resume_mode      => 'attempt',
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_params           => \%nf_params,
                nextflow_dataflow_outputs => 1,
                nextflow_binary           => $self->_nf_binary(),
            },
            -rc_name         => 'medium_long',
            -flow_into       => { 2 => 'ConsumeUtrAdditionOutput' },
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'ConsumeUtrAdditionOutput',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => { cmd => 'echo "UTR addition ready: type=#type# path=#path#"' },
            -meadow_type => 'LOCAL',
        },

    ];
}


1;
