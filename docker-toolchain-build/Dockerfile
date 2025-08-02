# This Dockerfile generates the docker image that gets used by toolchain-builder Gitlab CI
# To build it (YYYYMMDD.HHMM is the current date and time in UTC):
#   sudo docker build -t tpetazzoni/toolchain-builder-build:YYYYMMDD.HHMM .
#   sudo docker push tpetazzoni/toolchain-builder-build:YYYYMMDD.HHMM

# We use a specific tag for the base image *and* the corresponding date
# for the repository., so do not forget to update the apt-sources.list
# file that is shipped next to this Dockerfile.
FROM debian:bullseye-20250721

LABEL maintainer="Thomas Petazzoni <thomas.petazzoni@bootlin.com>" \
      vendor="Bootlin" \
description="Container used to build toolchains.bootlin.com toolchains"

# Setup environment
ENV DEBIAN_FRONTEND=noninteractive

# This repository can be a bit slow at times. Don't panic...
COPY apt-sources.list /etc/apt/sources.list

# The container has no package lists, so need to update first
RUN dpkg --add-architecture i386 && \
    apt-get update -y
RUN apt-get install -y --no-install-recommends \
        bc \
        build-essential \
        bzr \
        ca-certificates \
        cmake \
        cpio \
        file \
        g++-multilib \
        git \
        libc6:i386 \
        libncurses5-dev \
        locales \
        rsync \
        unzip \
        wget \
        && \
    apt-get -y autoremove && \
    apt-get -y clean

# To be able to generate a toolchain with locales, enable one UTF-8 locale
RUN sed -i 's/# \(en_US.UTF-8\)/\1/' /etc/locale.gen && \
    /usr/sbin/locale-gen

RUN useradd -ms /bin/bash br-user && \
    chown -R br-user:br-user /home/br-user

USER br-user
WORKDIR /home/br-user
ENV HOME=/home/br-user
ENV LC_ALL=en_US.UTF-8
