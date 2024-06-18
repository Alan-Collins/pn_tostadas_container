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
    input:
    path metadata
    path meta_json

    output:
    tuple env(sample), path("submission_outputs/*"), path("submission_outputs/combined_submission_log.csv"), emit: submission_outputs

    script:
    """
    sample=\$(echo $metadata | sed 's/.xlsx//')

    nextflow run /tostadas/main.nf \
    -profile conda,azure \
    --output_dir ./ \
    --submission --annotation false --genbank false --sra true --bacteria \
    --fastq_path /tostadas/ --fasta_path /tostadas/ --bakta_db_path /tostadas/ \
    --meta_path $metadata \
    --custom_fields_file $meta_json \
    --submission_config /tostadas/bin/config_files/submission_config.yml \
    -c /tostadas/tostadas_azure_test.config
    """
}

process UPDATE_SUBMISSION {

    publishDir "$params.output_dir/$sample/", mode: 'copy', overwrite: true
    errorStrategy { sleep(wait_time * 1000); task.exitStatus == 2 ? 'retry' : 'terminate' }
    maxRetries 100

    conda (params.enable_conda ? params.env_yml : null)
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'staphb/tostadas:latest' : 'staphb/tostadas:latest' }"

    input:
        val wait_time 
        tuple val(sample), path(submission_output), path(submission_log)

    output:
        path "PipelineProcessOutputs.json"
    
    def test_flag = params.submission_prod_or_test == 'test' ? '--test' : ''

    script:
    """
    # mv submission_outputs/* .
    # rm -r submission_outputs
    cp /tostadas/bin/config_files/submission_config.yml .
    
    sub_name=\$(ls -d */)
    sub_name=\${sub_name%/}
    cp "\$sub_name"_submission_log.csv \$sub_name/

    /tostadas/bin/submission.py check_submission_status \
        --organism $params.organism \
        --submission_dir \$sub_name/  \
        --submission_name \$sub_name $test_flag

    /tostadas/get_accessions.py \
        --sra \$sub_name/submission_files/SRA/report.xml \
        --biosample \$sub_name/submission_files/BIOSAMPLE/report.xml \
        --out PipelineProcessOutputs.json
    """    
} 

workflow {
    CONVERT_CSV(params.reads)
    RUN_TOSTADAS(CONVERT_CSV.out.xlsx.flatten(), CONVERT_CSV.out.metadata_json)
    UPDATE_SUBMISSION(300, RUN_TOSTADAS.out.submission_outputs, RUN_TOSTADAS.out.submission_log)
}
