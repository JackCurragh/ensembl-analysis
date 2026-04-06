=head1 LICENSE

Copyright [2016-2024] EMBL-European Bioinformatics Institute
Licensed under the Apache License, Version 2.0.

=head1 DESCRIPTION

eHive pipeline configuration for the ensembl-genes-nf finalise_geneset pipeline.
Applies post-UTR-addition QC steps: filter short ORFs and tiny-intron transcripts,
detect pseudogenes (repeat coverage + frameshifted introns), identify readthrough
transcripts, flag selenoproteins, and select canonical transcripts per gene.
Replaces HivePseudogenes.pm and HiveCleanGeneset.pm.

=head2 Typical init command

  init_pipeline.pl Bio::EnsEMBL::Analysis::Hive::Config::NextflowFinaliseGeneset_conf \
    -pipeline_db -host=<host> -pipeline_db -port=<port>                               \
    -pipeline_db -dbname=${USER}_finalise_geneset_nf_pipe                             \
    -nextflow_work_root   /hps/nobackup/flicek/ensembl/genebuild/nextflow_work        \
    -nextflow_output_root /hps/nobackup/flicek/ensembl/genebuild/nextflow_output      \
    -nextflow_pipeline_dir /path/to/ensembl-genes-nf/pipelines/finalise_geneset       \
    -fg_input_gff3   /path/to/utr_added.gff3                                          \
    -fg_repeat_gff3  /path/to/repeats.gff3

=cut

package Bio::EnsEMBL::Analysis::Hive::Config::NextflowFinaliseGeneset_conf;

use strict;
use warnings;
use feature 'say';
use File::Spec::Functions qw(catdir);
use base ('Bio::EnsEMBL::Analysis::Hive::Config::NextflowPipelineBase_conf');


sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },

        user        => $ENV{GBUSER},
        password    => $ENV{GBPASS},
        user_r      => $ENV{USER_R} || 'ensro',
        password_r  => undef,
        dna_db_name => '',

        pipeline_name          => 'nextflow_finalise_geneset',
        nextflow_pipeline_name => 'finalise_geneset',
        nextflow_pipeline_dir  => '/path/to/ensembl-genes-nf/pipelines/finalise_geneset',
        nextflow_resume_mode   => 'attempt',
        nextflow_profile       => 'slurm',
        nextflow_work_root     => undef,
        nextflow_output_root   => undef,

        # --- finalise_geneset pipeline parameters ---
        fg_input_gff3          => undef,   # UTR-extended gene GFF3
        fg_repeat_gff3         => undef,   # repeat annotation GFF3 for pseudogene detection
        fg_selenoprotein_fasta => undef,   # selenoprotein FASTA; optional
        fg_min_orf_aa          => 100,     # minimum ORF length in amino acids
        fg_min_intron_size     => 10,      # minimum intron size (bp) before removal
        fg_max_repeat_cds_cov  => 0.80,   # max CDS repeat coverage fraction for pseudogene call
        fg_max_readthrough_gap => 10000,   # max inter-CDS gap for readthrough detection (bp)
    };
}


sub pipeline_analyses {
    my ($self) = @_;

    my $nf_params = {
        input_gff3              => $self->o('fg_input_gff3'),
        repeat_gff3             => $self->o('fg_repeat_gff3'),
        min_orf_aa              => $self->o('fg_min_orf_aa'),
        min_intron_size         => $self->o('fg_min_intron_size'),
        max_repeat_cds_coverage => $self->o('fg_max_repeat_cds_cov'),
        max_readthrough_gap     => $self->o('fg_max_readthrough_gap'),
    };

    # Only pass selenoprotein_fasta if defined; Nextflow handles absent param as NO_FILE
    if (defined $self->o('fg_selenoprotein_fasta')) {
        $nf_params->{selenoprotein_fasta} = $self->o('fg_selenoprotein_fasta');
    }

    return [

        {
            -logic_name  => 'seed_finalise_geneset',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => {
                fg_input_gff3  => $self->o('fg_input_gff3'),
                fg_repeat_gff3 => $self->o('fg_repeat_gff3'),
                cmd => 'test -f #fg_input_gff3# && test -f #fg_repeat_gff3#',
            },
            -rc_name   => '1GB',
            -input_ids => [{}],
            -flow_into => { 1 => ['run_finalise_geneset'] },
        },

        {
            -logic_name      => 'run_finalise_geneset',
            -module          => 'Bio::EnsEMBL::Analysis::Hive::RunnableDB::HiveRunNextflow',
            -parameters      => {
                nextflow_binary           => $self->o('nextflow_binary'),
                nextflow_pipeline_dir     => $self->o('nextflow_pipeline_dir'),
                nextflow_pipeline_name    => $self->o('nextflow_pipeline_name'),
                nextflow_work_root        => $self->o('nextflow_work_root'),
                nextflow_output_dir       => catdir(
                    $self->o('nextflow_output_root'),
                    $self->o('nextflow_pipeline_name'),
                ),
                nextflow_resume_mode      => $self->o('nextflow_resume_mode'),
                nextflow_profile          => $self->o('nextflow_profile'),
                nextflow_extra_flags      => $self->o('nextflow_extra_flags'),
                nextflow_params           => $nf_params,
                nextflow_dataflow_outputs => 1,
            },
            -rc_name         => 'nextflow_launcher',
            -max_retry_count => 2,
            -flow_into       => {
                1 => ['pipeline_complete'],
                2 => ['consume_final_geneset'],
            },
        },

        {
            -logic_name => 'consume_final_geneset',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => { cmd => 'echo "Final geneset output: type=#type# path=#path#"' },
            -rc_name    => '1GB',
        },

        {
            -logic_name  => 'pipeline_complete',
            -module      => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters  => { cmd => 'echo "Finalise geneset pipeline complete."' },
            -rc_name     => '1GB',
        },

    ];
}


1;
