#!/usr/bin/env nextflow

nextflow.enable.dsl=2

params.output_dir = "/outputs"

process CONVERT_CSV {

    input:
        path csv

    output:
        path "*.xlsx", emit: xlsx
        path "metadata_fields.json", emit: metadata_json

    script:
    """
        /convert_csv.py $csv
    """
}

process RUN_TOSTADAS {
    errorStrategy 'finish'

    input:
    path metadata
    path meta_json

    output:
    tuple env(sample), env(sub_name), emit: submission

    script:
    """
    sample=\$(echo $metadata | sed 's/.xlsx//')

    nextflow run /tostadas/main.nf \
    -profile conda,azure \
    --output_dir ./ \
    --submission --annotation false --genbank false --sra true --bacteria \
    --fastq_path /tostadas/ --fasta_path /tostadas/ --bakta_db_path /tostadas/ \
    --meta_path \$(pwd)/$metadata \
    --custom_fields_file \$(pwd)/$meta_json \
    --submission_config /tostadas/bin/config_files/submission_config.yml \
    -c /tostadas/tostadas_azure_test.config

    sub_name=\$(ls -d submission_outputs/*)
    sub_name=\${sub_name%/}
    """
}

process UPDATE_SUBMISSION {

    publishDir "$params.output_dir/$sample/", mode: 'copy', overwrite: true
    errorStrategy { sleep(wait_time * 1000); task.exitStatus == 2 ? 'retry' : 'terminate' }
    maxRetries 100

    input:
        val wait_time 
        tuple val(sample), val(sub_name)
        val submission_type

    output:
        path "PipelineProcessOutputs.json"
    
    script:
    """
    /tostadas/get_accessions.py \
        --sample-name $sub_name \
        --submission-type $submission_type \
        --out PipelineProcessOutputs.json
    """    
} 

workflow {
    CONVERT_CSV(params.reads)
    RUN_TOSTADAS(CONVERT_CSV.out.xlsx.flatten(), CONVERT_CSV.out.metadata_json)
    UPDATE_SUBMISSION(300, RUN_TOSTADAS.out.submission, "Test")
}
