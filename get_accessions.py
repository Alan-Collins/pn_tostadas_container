#!/usr/bin/env python

import argparse
import xml.etree.ElementTree as ET
import os
import json
import re
import sys


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--sra",
        help="xml output file from sra submission",
        metavar="",
        required=True
        )
    parser.add_argument(
        "--biosample",
        help="xml output file from biosample submission",
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


def get_acc_from_xml(xml_file: str, file_id: str):
    accession = None
    qc = "PASS"
    error = ""
    if not os.path.exists(xml_file):
        accession = ""
        qc = "FAIL"
        error = f"XML file not found for {file_id}"
        return accession, qc, error
    
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

    accession = ""
    qc = "FAIL"
    error = f"Accession not found in {file_id} XML document"
    
    return accession, qc, error


def main():
    args = parse_args()
    sra_acc, sra_qc, sra_error = get_acc_from_xml(args.sra, "SRA")
    biosample_acc, biosample_qc, biosample_error = get_acc_from_xml(args.biosample, "Biosample")

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
