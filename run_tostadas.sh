#!/bin/bash

ssconvert /inputs/metadata.csv /inputs/metadata.xlsx

nextflow run /tostadas/main.nf -profile conda --bacteria --output_dir /inputs --submission_wait_time 300 --submission --annotation false --genbank false --sra true --fastq_path /inputs/reads/ --meta_path /inputs/metadata.xlsx --submission_config /inputs/test_submission_config.yml --fasta_path /inputs/reads/ --bakta_db_path /inputs/reads/ || cp .nextflow.log /inputs/
