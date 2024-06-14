#!/usr/bin/env python3

from collections import defaultdict
import subprocess
import json
import re
import sys

# Fields that Tostadas knows how to handle. Anything not below needs a custom metadata definition
DEFAULT_LAYOUT = {
    "Submission info": ['sample_name', 'ncbi-spuid', 'ncbi-spuid_namespace', 'ncbi-bioproject', 'author', 'submitting_lab', 'submitting_lab_division', 'submitting_lab_address', 'publication_status', 'publication_title'],
    "Sample info": ['isolate', 'isolation_source', 'description', 'host_disease', 'host', 'organism', 'collection_date', 'country', 'state', 'collected_by', 'sample_type', 'lat_lon', 'purpose_of_sampling'],
    "Case info": ['sex', 'age', 'race', 'ethnicity'],
    "Assembly info": ['assembly_protocol', 'assembly_method', 'mean_coverage', 'fasta_path'],
    "SRA - all": ['ncbi_sequence_name_sra'],
    "SRA - Illumina info": ['illumina_sequencing_instrument', 'illumina_library_strategy', 'illumina_library_source', 'illumina_library_selection', 'illumina_library_layout', 'illumina_library_protocol', 'file_location', 'illumina_sra_file_path_1', 'illumina_sra_file_path_2'],
    "SRA - Nanopore fields": ['nanopore_sequencing_instrument', 'nanopore_library_strategy', 'nanopore_library_source', 'nanopore_library_selection', 'nanopore_library_layout', 'nanopore_library_protocol', 'nanopore_sra_file_path_1']
}

# Keep track of any fields that must be populated and have global defaults
MANDATORY_FIELDS = {
    "file_location": "local",
    "author": "CDC",
    "ncbi-spuid_namespace": "EDLB-CDC",
    "country": "USA",
    "host": "missing",
    "host_disease": "missing",
    "host_sex": "missing",
    "isolation_source": "missing",
    "state": "missing",
    "lat_lon": "missing",
    "sex": "missing",
    "age": "missing",
    "race": "missing",
    "ethnicity": "missing",
    "isolate": "missing",
    "strain": "missing",
}

data = defaultdict(dict)

custom_fields = []

with open(sys.argv[1]) as fin:
    metadata_cols, *samples = [i.strip().split(",")[1:] for i in fin.readlines() if i != ""]
    # replace file mapping headers with tostadas headers
    metadata_cols[0] = "illumina_sra_file_path_1"
    metadata_cols[1] = "illumina_sra_file_path_2"

# reorganize columns for default layout
for samp in samples:
    s_id = samp[2]
    for header, fld in zip(metadata_cols, samp):
        data[header][s_id] = fld
        
        # check fields with mandatory content or format
        # First check fields which should duplicate data from other fields
        if header == "isolate" and fld == "":
            data[header][s_id] = data["ncbi-spuid"][s_id]
            continue
        if header == "collection_date" and re.match(r"^\\d{4}\$", fld):
            # fld is just the year
            data[header][s_id] += "-01"
        if fld == "" and header in MANDATORY_FIELDS:
            data[header][s_id] = MANDATORY_FIELDS[header]

# Add missing mandatory fields
for header, value in MANDATORY_FIELDS.items():
    for samp in samples:
        s_id = samp[2]
        if s_id not in data[header]:
            data[header][s_id] = value
        if data[header][s_id] == "":
            data[header][s_id] = value

out_lines = [[], []] + [[]] * len(samples)

for major, minor in DEFAULT_LAYOUT.items():
    # first populate header lines
    out_lines[0] += [major] + [""] * (len(minor)-1) # pad columns to include all minor headers
    out_lines[1] += minor

    # then add sample data
    for n, sample in enumerate(samples):
        s_id = sample[2]
        for header in minor:
            try:
                out_lines[2+n].append(data[header].get(s_id, ''))
            except KeyError:
                out_lines[2+n].append('')

                
# Identify custom fields
DEFAULT_FIELDS = set(out_lines[1])

custom_fields = [fld for fld in metadata_cols if fld not in DEFAULT_FIELDS and fld != ""]


# Add custom fields into layout
out_lines[0] += [""]*len(custom_fields)
out_lines[1] += custom_fields
for n, sample in enumerate(samples):
    s_id = sample[2]
    for header in custom_fields:
        try:
            out_lines[2+n].append(data[header].get(s_id, ''))
        except KeyError:
            out_lines[2+n].append('')

# Convert metadata to xlsx
metadata_string = "\\n".join([",".join(line) for line in out_lines] + [""])

command = f"ssconvert <(printf '{metadata_string}') metadata.xlsx"

subprocess.run(command, shell=True, executable="/bin/bash")

# Write metadata fields configuration json

meta_json = {
    fld: {
        "type": "String",
        "samples": ["All"],
        "replace_empty_with": "Missing",
        "new_field_name": ""
    } for fld in custom_fields
}

with open("metadata_fields.json", "w") as fout:
    json.dump(meta_json, fout, indent=4)
