#!/usr/bin/env nextflow

nextflow.enable.dsl=2
nextflow.preview.recursion=true

include {UPDATE_SUBMISSION} from './tostadas/modules/local/update_submission/'

params.output_dir = "/outputs"

// workflow wGET_ACCESSIONS{
//     take:
//     submission_output
//     submission_log

//     main:
//     UPDATE_SUBMISSION(
//         30,
//         "/tostadas/bin/config_files/submission_config.yml",
//         submission_output,
//         submission_log
//     )
//     GRAB_ACCESSIONS(UPDATE_SUBMISSION.out.submission_files)

//     emit: 
//     QC = GRAB_ACCESSIONS.out.QC
//     submission_log

// }



/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PULSENET WRAPPING FUNCTIONALITY
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

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

    // label 'main'

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
        submission.py check_submission_status \
            --organism $params.organism \
            --submission_dir .  \
            --submission_name $submission_output $test_flag
        
        /tostadas/get_accessions.py \
            --sra \$dir/submission_files/SRA/report.xml \
            --biosample \$dir/submission_files/BIOSAMPLE/report.xml \
            --out "\$acc"_accessions.json

        # output that a QC failed if any accessions didn't pass
        grep "FAIL" *_accessions.json && QC=FAIL || QC=PASS

        if [[ $QC == "FAIL" ]]; then
            sleep $wait_time
        fi
    """

    
} 

// process GRAB_ACCESSIONS {
//     publishDir "$params.publish_dir/accession_jsons"

//     input: 
//     val submission_files

//     output:
//         path "*.json"
//         env QC, emit: QC
    
//     script:
//         """
//             for dir in \$(ls -d $submission_files/*/)
//             do
//                 acc=\${dir%/}
//                 acc=\${acc##*/}
//                 /tostadas/get_accessions.py \
//                     --sra \$dir/submission_files/SRA/report.xml \
//                     --biosample \$dir/submission_files/BIOSAMPLE/report.xml \
//                     --out "\$acc"_accessions.json
//             done
//             # output that a QC failed if any accessions didn't pass
//             grep "FAIL" *_accessions.json && QC=FAIL || QC=PASS
//         """

// }


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN ALL WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// WORKFLOW: Execute a single named workflow for the pipeline
// See: https://github.com/nf-core/rnaseq/issues/619
//
workflow {
    CONVERT_CSV(params.reads)
    RUN_TOSTADAS(CONVERT_CSV.out.xlsx)
    
    // repeat until all submissions are acceptable
    // wGET_ACCESSIONS
    //     .recurse(RUN_TOSTADAS.out.submission_outputs, RUN_TOSTADAS.out.submission_log)
    //     .until { it -> it.out.QC == "PASS" }
    UPDATE_SUBMISSION
        .recurse(300, RUN_TOSTADAS.out.submission_outputs, RUN_TOSTADAS.out.submission_log)
        .until { it -> it.out.QC == "PASS" }
}


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
