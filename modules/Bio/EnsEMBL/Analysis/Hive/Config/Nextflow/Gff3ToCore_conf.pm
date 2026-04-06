=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

=head1 NAME

Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::Gff3ToCore_conf

=head1 DESCRIPTION

eHive pipeline that runs the Nextflow gff3_to_core pipeline, which loads
a final-geneset GFF3 into an Ensembl core MySQL database schema and assigns
Ensembl stable IDs (ENSG/ENST/ENSE/ENSP).

This is the last stage in the Nextflow genebuild pipeline, replacing the
eHive-based WriteGenes + StableIdMapping runnables.

Prerequisites:
  - An empty Ensembl core schema DB must exist before this pipeline runs.
    Create it with:
      mysql -u ensrw -p -e "CREATE DATABASE homo_sapiens_core_109_38;"
      mysql -u ensrw -p homo_sapiens_core_109_38 < ensembl-core-schema.sql
  - genome_fai: samtools .fai index for seq_region loading
  - synonyms_tsv: produced by load_assembly pipeline for seq-region name mapping

Usage (HPC production):

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::Gff3ToCore_conf \
    -pipeline_db              "-host mysql-ens-genebuild-prod -port 4527 -user ensrw -pass XXX -dbname jack_grch38_gff3_to_core" \
    -input_gff3               /hps/scratch/.../finalise_geneset/final.canonical.gff3 \
    -target_db_host           mysql-ens-genebuild-prod \
    -target_db_port           4527 \
    -target_db_user           ensrw \
    -target_db_password       XXX \
    -target_db_name           homo_sapiens_core_109_38 \
    -assembly                 GRCh38 \
    -species_name             homo_sapiens \
    -genome_fai               /hps/scratch/.../load_assembly/genome/GCA_000001405.29_GRCh38.p14_genomic.fai \
    -synonyms_tsv             /hps/scratch/.../load_assembly/genome/GCA_000001405.29_GRCh38.p14.synonyms.tsv \
    -outdir                   /hps/scratch/flicek/ensembl/genebuild/grch38/gff3_to_core \
    -nextflow_work_root       /hps/scratch/flicek/ensembl/genebuild/grch38/nf_work \
    -nf_pipeline_dir          /nfs/production/flicek/ensembl/genebuild/ensembl-genes-nf/pipelines/gff3_to_core

  beekeeper.pl -url "$EHIVE_URL" -loop

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::Gff3ToCore_conf;

use strict;
use warnings;

use parent ('Bio::EnsEMBL::Analysis::Hive::Config::Nextflow::NfPipelineBase_conf');


sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },

        # ----------------------------------------------------------------
        # Input GFF3 (final annotated geneset from finalise_geneset)
        # ----------------------------------------------------------------
        input_gff3              => undef,   # required

        # ----------------------------------------------------------------
        # Target Ensembl core database connection
        # ----------------------------------------------------------------
        target_db_host          => undef,   # required
        target_db_port          => 3306,
        target_db_user          => undef,   # required — needs INSERT/UPDATE/CREATE
        target_db_password      => '',
        target_db_name          => undef,   # required — must already have core schema

        # ----------------------------------------------------------------
        # Assembly and species metadata
        # ----------------------------------------------------------------
        assembly                => undef,   # required — e.g. GRCh38
        species_name            => '',      # Ensembl production name, e.g. homo_sapiens
        species_id              => 1,       # species.species_id in the core DB
        stable_id_prefix        => '',      # '' for human, 'GAL' for chicken, etc.
        coord_system            => 'chromosome',
        analysis_logic_name     => 'ensembl',

        # ----------------------------------------------------------------
        # Optional inputs (paths derived from load_assembly when not set)
        # ----------------------------------------------------------------
        genome_fai              => undef,   # samtools .fai index — undef → NO_FILE_FAI sentinel
        synonyms_tsv            => undef,   # seq-region synonyms TSV — undef → NO_FILE_SYN sentinel
    };
}


sub pipeline_wide_parameters {
    my ($self) = @_;
    return {
        %{ $self->SUPER::pipeline_wide_parameters() },
        pipeline_name => 'gff3_to_core',
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    my %nf_params = (
        input_gff3          => $self->o('input_gff3'),
        db_host             => $self->o('target_db_host'),
        db_port             => $self->o('target_db_port'),
        db_user             => $self->o('target_db_user'),
        db_password         => $self->o('target_db_password'),
        db_name             => $self->o('target_db_name'),
        assembly            => $self->o('assembly'),
        species_name        => $self->o('species_name'),
        species_id          => $self->o('species_id'),
        stable_id_prefix    => $self->o('stable_id_prefix'),
        coord_system        => $self->o('coord_system'),
        analysis_logic_name => $self->o('analysis_logic_name'),
        outdir              => $self->o('outdir'),
    );

    # Only pass optional file params when provided
    if (defined $self->o('genome_fai')) {
        $nf_params{genome_fai} = $self->o('genome_fai');
    }
    if (defined $self->o('synonyms_tsv')) {
        $nf_params{synonyms_tsv} = $self->o('synonyms_tsv');
    }

    return [

        {
            -logic_name  => 'SeedGff3ToCore',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -input_ids   => [{}],
            -flow_into   => { 1 => 'RunGff3ToCore' },
            -meadow_type => 'LOCAL',
        },

        {
            -logic_name  => 'RunGff3ToCore',
            -module      => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters  => {
                nextflow_pipeline_dir     => $self->o('nf_pipeline_dir'),
                nextflow_pipeline_name    => 'gff3_to_core',
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => $self->o('outdir'),
                nextflow_resume_mode      => 'attempt',
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_params           => \%nf_params,
                nextflow_dataflow_outputs => 1,
                nextflow_binary           => $self->_nf_binary(),
            },
            -rc_name         => 'medium_long',
            -flow_into       => { 2 => 'ConsumeGff3ToCoreOutput' },
            -max_retry_count => 1,
        },

        {
            -logic_name  => 'ConsumeGff3ToCoreOutput',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => {
                cmd => 'echo "Core DB loaded: type=#type# path=#path#"',
            },
            -meadow_type => 'LOCAL',
        },

    ];
}


1;
