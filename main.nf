#!/usr/bin/env nextflow

nextflow.enable.dsl=2

params.output_dir = "/outputs"

process CONVERT_CSV {
    publishDir "./", mode: "copy"

    input:
        path csv

    output:
        path "metadata.xlsx", emit: xlsx
        path "metadata_fields.json"

    script:
    """
        /convert_csv.py $csv
    """
}

process RUN_TOSTADAS {
    input:
    path metadata

    output:
    path "submission_outputs/", emit: submission_outputs
    path "submission_outputs/combined_submission_log.csv", emit: submission_log

    script:
    """
    nextflow run /tostadas/main.nf \
    -profile conda,azure \
    --output_dir ./ \
    --submission --annotation false --genbank false --sra true --bacteria \
    --fastq_path /tostadas/ --fasta_path /tostadas/ --bakta_db_path /tostadas/ \
    --meta_path /metadata.xlsx \
    --custom_fields_file /metadata_fields.json \
    --submission_config /tostadas/bin/config_files/submission_config.yml \
    -c /tostadas/tostadas_azure_test.config
    """
}

process UPDATE_SUBMISSION {

    publishDir "$params.output_dir/$params.submission_output_dir/", mode: 'copy', overwrite: true

    conda (params.enable_conda ? params.env_yml : null)
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'staphb/tostadas:latest' : 'staphb/tostadas:latest' }"

    input:
        val wait_time 
        path submission_output
        path submission_log

    output:
        path "*.json"
        env QC, emit: QC
    
    def test_flag = params.submission_prod_or_test == 'test' ? '--test' : ''
    script:
    """
    mv submission_outputs/* .
    rm -r submission_outputs
    cp /tostadas/bin/config_files/submission_config.yml .
    for sub_name in \$(ls -d */); do
        sub_name=\${sub_name%/}
        cp "\$sub_name"_submission_log.csv \$sub_name/
        repeat="TRUE"
        while [[ \$repeat == "TRUE" ]]; do
            /tostadas/bin/submission.py check_submission_status \
                --organism $params.organism \
                --submission_dir \$sub_name/  \
                --submission_name \$sub_name $test_flag

            /tostadas/get_accessions.py \
                --sra \$sub_name/submission_files/SRA/report.xml \
                --biosample \$sub_name/submission_files/BIOSAMPLE/report.xml \
                --out "\$sub_name"_accessions.json

            # output that a QC failed if any accessions didn't pass
            grep "FAIL" "\$sub_name"_accessions.json && QC=FAIL || QC=PASS

            if [[ \$QC == "FAIL" ]]; then
                sleep $wait_time
            else
                repeat="FALSE"
            fi
        done
    done
    """    
} 

workflow {
    CONVERT_CSV(params.reads)
    RUN_TOSTADAS(CONVERT_CSV.out.xlsx)
    UPDATE_SUBMISSION(300, RUN_TOSTADAS.out.submission_outputs, RUN_TOSTADAS.out.submission_log)
}
