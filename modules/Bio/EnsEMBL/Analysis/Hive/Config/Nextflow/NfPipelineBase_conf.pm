=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

=head1 NAME

Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::NfPipelineBase_conf

=head1 DESCRIPTION

Abstract base class for all Nextflow PipeConfig modules.

Provides:
  - Shared default_options (nextflow_bin, nextflow_profile, java_home,
    nextflow_work_root, nf_pipeline_dir, outdir)
  - _nf_binary()  — constructs the nextflow invocation, optionally prefixed
    with JAVA_HOME when java_home is set (needed on macOS where the system
    Java may be <17; not needed on Linux HPC where Java 17+ is on PATH)
  - resource_classes (small_long / medium_long / large_long for
    LOCAL / LSF / SLURM meadows)

Subclass this instead of HiveGeneric_conf for any pipeline that runs a
Nextflow subpipeline via HiveRunNextflow.

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::NfPipelineBase_conf;

use strict;
use warnings;

use parent ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');


sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },

        # ----------------------------------------------------------------
        # Nextflow execution
        # ----------------------------------------------------------------
        nextflow_bin        => 'nextflow',

        # 'slurm'  — production HPC (Singularity containers, SLURM scheduler)
        # 'local'  — local testing without containers (needs tools on PATH or conda)
        # 'conda'  — local testing with micromamba-managed tool environments
        # 'docker' — local testing with Docker
        nextflow_profile    => 'slurm',

        # Java ≥17 required by Nextflow ≥23.
        # Leave empty ('') on Linux HPC where Java 17+ is on PATH.
        # Set to the Homebrew OpenJDK path on macOS, e.g.:
        #   /opt/homebrew/Cellar/openjdk@21/21.0.10/libexec/openjdk.jdk/Contents/Home
        java_home           => '',

        # ----------------------------------------------------------------
        # Paths common to all pipelines
        # ----------------------------------------------------------------
        outdir              => undef,
        nextflow_work_root  => undef,
        nf_pipeline_dir     => undef,   # override per-pipeline if needed
    };
}


=head2 _nf_binary

  Description: Returns the shell token used to invoke Nextflow.
               If java_home is set, prepends JAVA_HOME= and PATH= assignments
               so that Nextflow picks up the correct JVM.  Otherwise returns
               nextflow_bin as-is.
  Returntype : String

=cut

sub _nf_binary {
    my ($self) = @_;
    my $java_home = $self->o('java_home');
    my $nf_bin    = $self->o('nextflow_bin');
    if ($java_home) {
        return "JAVA_HOME=${java_home} PATH=${java_home}/bin:\$PATH ${nf_bin}";
    }
    return $nf_bin;
}


sub resource_classes {
    my ($self) = @_;
    return {
        %{ $self->SUPER::resource_classes() },

        # Launcher: tiny RAM but must outlast the full Nextflow run
        'small_long' => {
            'LOCAL' => '',
            'LSF'   => '-q normal -M 500 -R "select[mem>500] rusage[mem=500]"',
            'SLURM' => '--partition=long --mem=500M --time=24:00:00',
        },

        # Most annotation launcher jobs
        'medium_long' => {
            'LOCAL' => '',
            'LSF'   => '-q normal -M 2000 -R "select[mem>2000] rusage[mem=2000]"',
            'SLURM' => '--partition=long --mem=2G --time=48:00:00',
        },

        # Long-read alignment and repeat masking (high RAM, long wall time)
        'large_long' => {
            'LOCAL' => '',
            'LSF'   => '-q normal -M 25000 -R "select[mem>25000] rusage[mem=25000]"',
            'SLURM' => '--partition=long --mem=25G --time=120:00:00',
        },
    };
}


1;
