ARG VERSION="23.10.1"
FROM nextflow/nextflow:${VERSION} AS builder

# # Use a minimal base image for runtime
FROM adoptopenjdk:11-jre-hotspot
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y wget git openjdk-11-jre-headless gnupg2 &&\
    apt-get clean
RUN apt-get update && apt-get install -y curl 

# Copy Nextflow binary from the builder stage
COPY --from=builder /usr/local/bin/nextflow /usr/local/bin/nextflow
RUN chmod 755 /usr/local/bin/nextflow
ENV PATH="/root/.nextflow:${PATH}"
ENV NXF_HOME="/root/.nextflow"

RUN mkdir -p /root/.nextflow/framework/23.10.1
RUN curl -k -L -o  /root/.nextflow/framework/23.10.1/nextflow-23.10.1-one.jar https://www.nextflow.io/releases/v23.10.1/nextflow-23.10.1-one.jar 
# Set the working directory inside the container
RUN apt-get update && apt-get install -y curl 
# RUN conda install -y gxx_linux-64 curl
# Download tostadas
RUN git clone -b dev https://github.com/CDCgov/tostadas.git
ENV HOME /tostadas
WORKDIR $HOME
RUN git checkout ec0bd38

RUN curl -L -O https://github.com/conda-forge/miniforge/releases/latest/download/Mambaforge-$(uname)-$(uname -m).sh
RUN bash Mambaforge-$(uname)-$(uname -m).sh -b -p $HOME/mambaforge
ENV PATH="$HOME/mambaforge/bin:$PATH"
COPY environment.yml /tostadas/environment.yml
RUN  conda env create -n tostadas_local -y -f environment.yml
ENV PATH="/tostadas/mambaforge/envs/tostadas_local/bin:$PATH"

# Copy necessary files to the container
WORKDIR /tostadas
COPY tostadas_azure.config /tostadas/
COPY submission_config.yml /tostadas/bin/config_files
RUN nextflow -version

ENTRYPOINT ["tail", "-f", "/dev/null"]
