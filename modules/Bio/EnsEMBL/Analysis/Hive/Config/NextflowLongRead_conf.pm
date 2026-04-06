=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

=head1 DESCRIPTION

eHive pipeline configuration for running the ensembl-genes-nf long_read
Nextflow pipeline via HiveRunNextflow. Replaces long_read.pm.

The eHive launcher job is lightweight (2 GB, 7-day wall-time); real compute
runs in Slurm jobs submitted by Nextflow itself.

On successful completion, HiveRunNextflow reads output_manifest.json from
--outdir and fans out one job per GFF3 output on channel 2. Downstream
analyses (e.g. transcript_selection) consume these via -flow_into on
channel 2.

=head2 Typical init command

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::NextflowLongRead_conf \
    -pipeline_db -host=<host> -pipeline_db -port=<port>                          \
    -pipeline_db -dbname=${USER}_long_read_nf_pipe                                \
    -nextflow_work_root   /hps/nobackup/flicek/ensembl/genebuild/nextflow_work    \
    -nextflow_output_root /hps/nobackup/flicek/ensembl/genebuild/nextflow_output  \
    -nextflow_pipeline_dir /path/to/ensembl-genes-nf/pipelines/long_read          \
    -long_read_sample_sheet /path/to/species_long_read.tsv                        \
    -long_read_genome_fasta /path/to/genome.fa                                    \
    -long_read_protein_db   /path/to/uniprot_blastdb/

=head2 Directory layout produced

  ${nextflow_work_root}/long_read/job_${id}/attempt_0/work/
  ${nextflow_output_root}/long_read/
    *.classified.gff3           (one per sample)
    *.sorted.bam                (one per sample)
    output_manifest.json        (consumed by HiveRunNextflow dataflow)
    pipeline_info/              (Nextflow execution reports)

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::NextflowLongRead_conf;

use strict;
use warnings;
use feature 'say';

use File::Spec::Functions qw(catdir);

use base ('Bio::EnsEMBL::Analysis::Hive::Config::NextflowPipelineBase_conf');


sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },

        # --- eHive DB credentials ---
        user        => $ENV{GBUSER},
        password    => $ENV{GBPASS},
        user_r      => $ENV{USER_R} || 'ensro',
        password_r  => undef,
        dna_db_name => '',   # no core DB needed during annotation

        # --- eHive pipeline identity ---
        pipeline_name          => 'nextflow_long_read',

        # --- Nextflow pipeline identity ---
        nextflow_pipeline_name => 'long_read',
        nextflow_pipeline_dir  => '/path/to/ensembl-genes-nf/pipelines/long_read',

        # --- Resume strategy ---
        nextflow_resume_mode   => 'attempt',

        # slurm profile — Singularity containers pulled automatically
        nextflow_profile       => 'slurm',

        # --- Directory roots ---
        nextflow_work_root     => undef,
        nextflow_output_root   => undef,

        # --- long_read pipeline parameters ---
        # Passed as --param to nextflow run

        # Required
        long_read_sample_sheet  => undef,   # TSV: sample_name\tfastq_file\tinstrument_platform
        long_read_genome_fasta  => undef,   # Path to genome FASTA (with .fai index)
        long_read_protein_db    => undef,   # Path to UniProt BLAST database directory

        # Optional
        long_read_genome_index    => undef,   # Pre-built .mmi index; created if absent
        long_read_minimap2_preset => 'splice',
        long_read_min_overlap     => 0.8,
        long_read_max_intron      => 200000,
        long_read_blast_evalue    => '1e-5',
        long_read_skip_download   => 'false',
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    my $nf_params = {
        sample_sheet      => $self->o('long_read_sample_sheet'),
        genome_fasta      => $self->o('long_read_genome_fasta'),
        protein_db        => $self->o('long_read_protein_db'),
        genome_index      => $self->o('long_read_genome_index'),
        minimap2_preset   => $self->o('long_read_minimap2_preset'),
        collapse_min_overlap => $self->o('long_read_min_overlap'),
        max_intron_size   => $self->o('long_read_max_intron'),
        blast_evalue      => $self->o('long_read_blast_evalue'),
        skip_download     => $self->o('long_read_skip_download'),
    };

    return [

        # 1. Sanity-check inputs before spending compute
        {
            -logic_name  => 'check_inputs',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => {
                long_read_sample_sheet => $self->o('long_read_sample_sheet'),
                long_read_genome_fasta => $self->o('long_read_genome_fasta'),
                long_read_protein_db   => $self->o('long_read_protein_db'),
                cmd => 'test -f #long_read_sample_sheet# && test -f #long_read_genome_fasta# && test -d #long_read_protein_db#',
            },
            -rc_name     => '1GB',
            -input_ids   => [{}],
            -flow_into   => { 1 => ['run_long_read'] },
        },

        # 2. Launch the Nextflow long_read pipeline and wait for completion.
        #    On success, HiveRunNextflow reads output_manifest.json and
        #    dataflows each GFF3 entry on channel 2.
        {
            -logic_name      => 'run_long_read',
            -module          => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters      => {
                nextflow_binary            => $self->o('nextflow_binary'),
                nextflow_pipeline_dir      => $self->o('nextflow_pipeline_dir'),
                nextflow_pipeline_name     => $self->o('nextflow_pipeline_name'),
                nextflow_work_root         => $self->o('nextflow_work_root'),
                nextflow_output_dir        => catdir(
                    $self->o('nextflow_output_root'),
                    $self->o('nextflow_pipeline_name'),
                ),
                nextflow_resume_mode       => $self->o('nextflow_resume_mode'),
                nextflow_profile           => $self->o('nextflow_profile'),
                nextflow_extra_flags       => $self->o('nextflow_extra_flags'),
                nextflow_params            => $nf_params,
                nextflow_dataflow_outputs  => 1,
            },
            -rc_name         => 'nextflow_launcher',
            -max_retry_count => 2,
            -flow_into       => {
                1 => ['pipeline_complete'],
                2 => ['consume_long_read_output'],   # one job per output_manifest entry
            },
        },

        # 3. Consume each GFF3 output (dataflowed from output_manifest.json).
        #    Downstream: feed into transcript_selection or load to core DB.
        #    Currently a stub — extend to MessagePipeline or loader as needed.
        {
            -logic_name  => 'consume_long_read_output',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => {
                cmd => 'echo "Long-read output: #path# (type=#type# sample=#meta.id#)"',
            },
            -rc_name     => '1GB',
        },

        # 4. Completion marker
        {
            -logic_name  => 'pipeline_complete',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => {
                nextflow_output_dir => catdir(
                    $self->o('nextflow_output_root'),
                    $self->o('nextflow_pipeline_name'),
                ),
                cmd => 'echo "Long-read pipeline complete. Results: #nextflow_output_dir#"',
            },
            -rc_name => '1GB',
        },

    ];
}


1;
