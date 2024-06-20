#!/usr/bin/env python

import argparse
import xml.etree.ElementTree as ET
import os
import json
import re
import sys
import yaml
import os
import ftplib

SEQSENDER_CONFIG = "/tostadas/bin/config_files/seqsender_main_config.yaml"
SUBMISSION_CONFIG = "/tostadas/bin/config_files/submission_config.yml"

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--sample-name",
        help="name of sample submitted to NCBI",
        metavar="",
        required=True
        )
    parser.add_argument(
        "--submission-type",
        help="Test or Production",
        metavar="",
        required=True
        )
    parser.add_argument(
        "--out",
        help="output file name",
        metavar="",
        required=True
        )
    return parser.parse_args()


def retrieve_report(sample_name: str, submission_type:str, database: str):
    with open(SEQSENDER_CONFIG, "r") as f:
        main_config = yaml.load(f, Loader=yaml.BaseLoader)["SUBMISSION_PORTAL"]

    FTP_HOST = main_config["PORTAL_NAMES"]["NCBI"]["FTP_HOST"]

    with open(SUBMISSION_CONFIG) as fin:
        config_dict = yaml.load(fin, Loader=yaml.BaseLoader).get("Submission")["NCBI"]

    ncbi_submission_name = sample_name + "_" + database

    ftp = ftplib.FTP(FTP_HOST)
    ftp.login(user=config_dict["Username"], passwd=config_dict["Password"])

    # CD into submit dir
    ftp.cwd('submit')

    # CD to to test/production folder
    ftp.cwd(submission_type)

    # Check if submission name exists
    if ncbi_submission_name not in ftp.nlst():
        print("There is no submission with the name of '"+ ncbi_submission_name +"' on NCBI FTP server.", file=sys.stderr)
        print("Please try the submission again.", file=sys.stderr)
        sys.exit(1)
    # CD to submission folder
    ftp.cwd(ncbi_submission_name)
    # Check if report.xml exists
    if "report.xml" in ftp.nlst():
        print("Pulling down report.xml", file=sys.stdout)
        report_file = f"{database}_report.xml"
        with open(report_file, 'wb') as f:
            ftp.retrbinary('RETR report.xml', f.write, 262144)
        return report_file
    

def get_acc_from_xml(xml_file: str, file_id: str):
    accession = None
    qc = "PASS"
    error = ""
    if not os.path.exists(xml_file):
        accession = ""
        qc = "FAIL"
        error = f"XML file not found for {file_id}"
        sys.stderr.write(error)
        sys.exit(2)
    
    tree = ET.parse(xml_file)
    root = tree.getroot()

    # first check success condition
    obj = root.find(".//Object")
    if obj is not None:
        accession = obj.get("accession")
        if accession is not None:
            return accession, qc, error
    
    # next try to get it from the error message
    obj = root.find(".//Message")
    if obj is not None:
        match = re.search(r"Original submission RUNs accessions: (SRR\d+)", obj.text)
        if match is not None:
            accession = match.group(1)
            return accession, qc, error
    
    # next try to get it from the "ExistingSample" section
    obj = root.find(".//ExistingSample")
    if obj is not None:
        # use a regex to make sure the message text is an acceptable accession instead of blindly accepting anything
        match = re.match(r"SAMN\d+", obj.text)
        if match is not None:
            accession = match.group(0)
            return accession, qc, error
    
    # Finally, check for an error message
    obj = root.find(".//Message")
    if obj is not None:
        if obj.get("severity") == "error-stop":
            error = obj.text
            qc = "FAIL"
        return accession, qc, error

    accession = ""
    qc = "FAIL"
    error = f"Accession not found in {file_id} XML document"
    sys.stderr.write(error)
    sys.exit(2)
    


def main():
    args = parse_args()
    sra_report = retrieve_report(args.sample_name, args.submission_type, "SRA")
    sra_acc, sra_qc, sra_error = get_acc_from_xml(sra_report, "SRA")
    biosample_report = retrieve_report(args.sample_name, args.submission_type, "BIOSAMPLE")
    biosample_acc, biosample_qc, biosample_error = get_acc_from_xml(biosample_report, "Biosample")

    qc = "PASS"
    for res in [sra_qc, biosample_qc]:
        if res == "FAIL":
            qc = "FAIL"
    
    errors = []
    for res in [sra_error, biosample_error]:
        if res:
            errors.append(res)

    output_data = {
        "metadata": {
            "SRR_ID": sra_acc,
            "NCBI_ACCESSION": biosample_acc
        },
        "qc": {
            "result": qc,
            "issues": errors
        }
    }

    with open(args.out, "w") as fout:
        json.dump(output_data, fout, indent=4)



if __name__ == "__main__":
    main()
