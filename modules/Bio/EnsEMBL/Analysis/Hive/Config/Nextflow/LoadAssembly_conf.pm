=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

=head1 NAME

Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::LoadAssembly_conf

=head1 DESCRIPTION

Minimal eHive pipeline that downloads and prepares a genome assembly from
NCBI using the Nextflow load_assembly pipeline, then dataflows the output
file paths to a downstream analysis.

Designed for local testing without a core database.  A downstream
StoreAssemblyOutputs analysis is a stub that prints the manifest outputs
to confirm the dataflow contract works end-to-end.

Usage:

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::LoadAssembly_conf \
    -pipeline_db    "-host localhost -port 3306 -user ensrw -pass XXX -dbname load_assembly_pipe" \
    -assembly_accession GCA_000001405.29 \
    -assembly_name      GRCh38.p14 \
    -outdir             /data/output/grch38 \
    -nextflow_work_root /data/nf_work \
    -nextflow_bin       /usr/local/bin/nextflow \
    -nf_pipeline_dir    /path/to/ensembl-genes-nf/pipelines/load_assembly

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::LoadAssembly_conf;

use strict;
use warnings;

use parent ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');


sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },

        # ----------------------------------------------------------------
        # Assembly identity — set on command line
        # ----------------------------------------------------------------
        assembly_accession  => undef,   # e.g. GCA_000001405.29
        assembly_name       => undef,   # e.g. GRCh38.p14

        # ----------------------------------------------------------------
        # Paths — set on command line
        # ----------------------------------------------------------------
        outdir              => undef,   # root output dir written by Nextflow
        nextflow_work_root  => undef,   # eHive-managed Nextflow work dirs
        nf_pipeline_dir     => undef,   # path to pipelines/load_assembly/

        # ----------------------------------------------------------------
        # Nextflow config
        # ----------------------------------------------------------------
        nextflow_bin        => 'nextflow',
        nextflow_profile    => 'local',   # 'slurm' on HPC

        # Java ≥17 is required by Nextflow ≥23.  The system default may be
        # older; override here if needed.
        java_home           => '/opt/homebrew/Cellar/openjdk@21/21.0.10/libexec/openjdk.jdk/Contents/Home',
    };
}


sub pipeline_wide_parameters {
    my ($self) = @_;
    return {
        %{ $self->SUPER::pipeline_wide_parameters() },
        pipeline_name => 'load_assembly',
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    return [

        # ----------------------------------------------------------------
        # 1. Seed — a single factory job to kick things off
        # ----------------------------------------------------------------
        {
            -logic_name  => 'SeedAssembly',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters  => {
                inputlist    => [ [ $self->o('assembly_accession'), $self->o('assembly_name') ] ],
                column_names => [ 'assembly_accession', 'assembly_name' ],
            },
            -input_ids   => [{}],
            -flow_into   => { 2 => 'RunLoadAssembly' },
            -meadow_type => 'LOCAL',
        },

        # ----------------------------------------------------------------
        # 2. Run Nextflow load_assembly pipeline
        # ----------------------------------------------------------------
        {
            -logic_name  => 'RunLoadAssembly',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir  => $self->o('nf_pipeline_dir'),
                nextflow_pipeline_name => 'load_assembly',
                nextflow_work_root     => $self->o('nextflow_work_root'),
                nextflow_output_dir    => $self->o('outdir'),
                nextflow_resume_mode   => 'attempt',
                nextflow_profile       => $self->o('nextflow_profile'),
                nextflow_params        => {
                    assembly_accession => '#assembly_accession#',
                    assembly_name      => '#assembly_name#',
                    outdir             => $self->o('outdir'),
                },
                nextflow_dataflow_outputs => 1,
                # Prefix JAVA_HOME so Nextflow picks up the correct JVM.
                # HiveRunNextflow uses nextflow_binary as the first shell token.
                nextflow_binary => 'JAVA_HOME=' . $self->o('java_home')
                    . ' PATH=' . $self->o('java_home') . '/bin:$PATH '
                    . $self->o('nextflow_bin'),
                nextflow_extra_flags => ['-stub'],
            },
            -rc_name     => 'small_long',   # small RAM, long wall time
            -flow_into   => { 2 => 'ConsumeAssemblyOutput' },
            -max_retry_count => 1,
        },

        # ----------------------------------------------------------------
        # 3. Downstream stub — receives each output from output_manifest.json
        #    on channel 2.  Replace with real loading logic.
        # ----------------------------------------------------------------
        {
            -logic_name  => 'ConsumeAssemblyOutput',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => {
                # Each output has: type, path, (optional) meta
                cmd => 'echo "Assembly output ready: type=#type# path=#path#"',
            },
            -meadow_type => 'LOCAL',
        },

    ];
}


sub resource_classes {
    my ($self) = @_;
    return {
        %{ $self->SUPER::resource_classes() },
        # Launcher job: tiny RAM, but must outlast the full Nextflow run
        # Format: meadow_type => submission_cmd_args  (scalar or [submit, worker])
        'small_long' => {
            'LOCAL' => '',
            'LSF'   => '-q normal -M 500 -R "select[mem>500] rusage[mem=500]"',
            'SLURM' => '--partition=long --mem=500M --time=24:00:00',
        },
    };
}


1;
