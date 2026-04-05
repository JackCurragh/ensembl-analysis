=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

=head1 NAME

Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::FinaliseGeneset_conf

=head1 DESCRIPTION

eHive pipeline that runs the Nextflow finalise_geneset pipeline (filters
gene models using repeat coverage, ORF length, intron size, and read-through
thresholds; optionally incorporates selenoprotein models) and dataflows output
paths on channel 2.

Typically used downstream of the utr_addition pipeline, receiving the
UTR-extended GFF3 as input_gff3, and a merged repeat GFF3 (published by
MERGE_REPEATS in the repeat_masking pipeline) as repeat_gff3.

NOTE: MERGE_REPEATS must have a publishDir configured to write
      *.repeats.gff3 to outdir/repeats/ for the repeat_gff3 path to
      resolve at runtime.

Usage (HPC production — MySQL + SLURM + Singularity):

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::FinaliseGeneset_conf \
    -pipeline_db        "-host mysql-ens-genebuild-prod -port 4527 -user ensrw -pass XXX -dbname jack_grch38_finalise" \
    -input_gff3         /hps/scratch/.../utr_addition/geneset_with_utrs.gff3 \
    -repeat_gff3        /hps/scratch/.../repeat_masking/repeats/GCA_000001405.29_GRCh38.p14_genomic.repeats.gff3 \
    -outdir             /hps/scratch/flicek/ensembl/genebuild/grch38/finalise_geneset \
    -nextflow_work_root /hps/scratch/flicek/ensembl/genebuild/grch38/nf_work \
    -nf_pipeline_dir    /nfs/production/flicek/ensembl/genebuild/ensembl-genes-nf/pipelines/finalise_geneset

  beekeeper.pl -url "$EHIVE_URL" -loop

Usage (local testing with conda):

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::FinaliseGeneset_conf \
    -pipeline_db        "-host 127.0.0.1 -port 3306 -user ensrw -pass XXX -dbname test_finalise" \
    -input_gff3         /data/utr_addition/geneset_with_utrs.gff3 \
    -repeat_gff3        /data/repeat_masking/repeats/assembly_genomic.repeats.gff3 \
    -selenoprotein_fasta /data/sequences/selenoproteins.fa \
    -outdir             /data/finalise_geneset \
    -nextflow_work_root /data/nf_work \
    -nf_pipeline_dir    /path/to/ensembl-genes-nf/pipelines/finalise_geneset \
    -nextflow_profile   conda \
    -nextflow_path_extra /opt/homebrew/bin \
    -mamba_root_prefix  /Users/me/mamba

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::FinaliseGeneset_conf;

use strict;
use warnings;

use parent ('Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::NfPipelineBase_conf');


sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },

        input_gff3              => undef,   # required: GFF3 from utr_addition or consolidate
        repeat_gff3             => undef,   # required: merged repeat GFF3 from repeat_masking
        selenoprotein_fasta     => undef,   # optional: FASTA of selenoprotein sequences
        min_orf_aa              => 100,
        min_intron_size         => 10,
        max_repeat_cds_coverage => 0.80,
        max_readthrough_gap     => 10000,
    };
}


sub pipeline_wide_parameters {
    my ($self) = @_;
    return {
        %{ $self->SUPER::pipeline_wide_parameters() },
        pipeline_name => 'finalise_geneset',
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    my %nf_params = (
        input_gff3              => $self->o('input_gff3'),
        repeat_gff3             => $self->o('repeat_gff3'),
        min_orf_aa              => $self->o('min_orf_aa'),
        min_intron_size         => $self->o('min_intron_size'),
        max_repeat_cds_coverage => $self->o('max_repeat_cds_coverage'),
        max_readthrough_gap     => $self->o('max_readthrough_gap'),
        outdir                  => $self->o('outdir'),
    );
    $nf_params{selenoprotein_fasta} = $self->o('selenoprotein_fasta')
        if defined $self->o('selenoprotein_fasta');

    return [

        {
            -logic_name  => 'SeedFinaliseGeneset',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -input_ids   => [{}],
            -flow_into   => { 1 => 'RunFinaliseGeneset' },
            -meadow_type => 'LOCAL',
        },

        {
            -logic_name  => 'RunFinaliseGeneset',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir     => $self->o('nf_pipeline_dir'),
                nextflow_pipeline_name    => 'finalise_geneset',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->o('outdir'),
                nextflow_resume_mode      => 'attempt',
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_params           => \%nf_params,
                nextflow_dataflow_outputs => 1,
                nextflow_binary           => $self->_nf_binary(),
            },
            -rc_name         => 'medium_long',
            -flow_into       => { 2 => 'ConsumeFinalGeneset' },
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'ConsumeFinalGeneset',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => { cmd => 'echo "Final geneset ready: type=#type# path=#path#"' },
            -meadow_type => 'LOCAL',
        },

    ];
}


1;
