=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

=head1 NAME

Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::BestTargeted_conf

=head1 DESCRIPTION

eHive pipeline that runs the Nextflow best_targeted pipeline (Exonerate cDNA
and/or protein alignment followed by best-pick selection) and dataflows output
paths on channel 2.

Usage:

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::BestTargeted_conf \
    -pipeline_db    "-host localhost -port 3306 -user ensrw -pass XXX -dbname best_targeted_pipe" \
    -genome_fasta   /data/genome/genome_softmasked.fa \
    -cdna_fasta     /data/sequences/cdna.fa \
    -protein_fasta  /data/sequences/proteins.fa \
    -outdir         /data/output/best_targeted \
    -nextflow_work_root /data/nf_work \
    -nf_pipeline_dir    /path/to/ensembl-genes-nf/pipelines/best_targeted

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::BestTargeted_conf;

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

        # ----------------------------------------------------------------
        # Optional sequence inputs (at least one must be provided)
        # ----------------------------------------------------------------
        cdna_fasta          => undef,   # cDNA / mRNA FASTA
        protein_fasta       => undef,   # protein FASTA (UniProt/RefSeq)

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
        pipeline_name => 'best_targeted',
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    my %nf_params = (
        genome_fasta => $self->o('genome_fasta'),
        outdir       => $self->o('outdir'),
    );
    if (defined $self->o('cdna_fasta')) {
        $nf_params{cdna_fasta} = $self->o('cdna_fasta');
    }
    if (defined $self->o('protein_fasta')) {
        $nf_params{protein_fasta} = $self->o('protein_fasta');
    }

    return [

        {
            -logic_name  => 'SeedBestTargeted',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -input_ids   => [{}],
            -flow_into   => { 1 => 'RunBestTargeted' },
            -meadow_type => 'LOCAL',
        },

        {
            -logic_name  => 'RunBestTargeted',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir  => $self->o('nf_pipeline_dir'),
                nextflow_pipeline_name => 'best_targeted',
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
            -flow_into   => { 2 => 'ConsumeBestTargetedOutput' },
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'ConsumeBestTargetedOutput',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => {
                cmd => 'echo "BestTargeted output ready: type=#type# path=#path#"',
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
