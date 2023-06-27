# Container for building and running qemu
# Note: libgtk-3-dev includes glib-2.0

FROM debian:bullseye as base

# set environment
ENV LANG C.UTF-8
ENV TERM=linux
ENV DEBIAN_FRONTEND=noninteractive

ARG PYTHON=python3
ARG PIP=pip3

ARG USER=user1
ARG GROUP=user1
# These must be identical to the host user for shared volumes
ARG USERID=1000
ARG GROUPID=1000

RUN apt-get update --fix-missing && \
    apt-get install -y \
    	    apt-utils \
	    ${PYTHON} \
	    ${PYTHON}-pip \
	    time \
	    wget ssh \
	    cloud-image-utils cloud-init \
	    build-essential \
	    git \
    	    sudo \
	    pkg-config \
	    libgtk-3-dev \
	    libslirp-dev \
	    ninja-build
	    
# upgrade for current python3 support
RUN ${PIP} --no-cache-dir install --upgrade \
    pip \
    setuptools
RUN ln -s $(which ${PYTHON}) /usr/local/bin/python

# set up non-root user with sudo rights
RUN adduser --disabled-password --gecos '' ${USER} && \
    adduser ${USER} sudo && \
    echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Update user meson package to most recent
# sphinx necessary for meson and qemu docs
RUN ${PIP} install meson sphinx sphinx_rtd_theme

# enter user
USER ${USER}

# overwrite the default .bashrc with our custom one
COPY bashrc.docker /home/${USER}/.bashrc

# add local python packages to path
#ENV PATH=/home/${USER}/.local/bin:$PATH

# override PS1 in local .bashrc
#RUN echo 'export PS1="\u:\!> "' >> /home/user1/.bashrc



