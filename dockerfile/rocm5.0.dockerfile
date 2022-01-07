FROM amdprivate.azurecr.io/superbench:rocm9234_ubuntu18.04_py3.8_pytorch_1.9.0_amd

LABEL maintainer="SuperBench"

ENV DEBIAN_FRONTEND=noninteractive
#RUN wget -qO - http://repo.radeon.com/rocm/apt/debian/rocm.gpg.key | APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1 apt-key add - && \
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    autoconf \
    automake \
    build-essential \
    curl \
    dmidecode \
    git \
    jq \
    libaio-dev \
    libcap2 \
    libpci-dev \
    libtinfo5 \
    libtool \
    lshw \
    net-tools \
    numactl \
    openssh-client \
    openssh-server \
    pciutils \
    util-linux \
    vim \
    wget \
    && \
    apt-get autoremove && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/*

# Install Docker
ENV DOCKER_VERSION=20.10.8
RUN cd /tmp && \
    wget https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz -O docker.tgz && \
    tar --extract --file docker.tgz --strip-components 1 --directory /usr/local/bin/ && \
    rm docker.tgz

# Update system config
RUN mkdir -p /root/.ssh && \
    touch /root/.ssh/authorized_keys && \
    mkdir -p /var/run/sshd && \
    sed -i "s/[# ]*PermitRootLogin prohibit-password/PermitRootLogin yes/" /etc/ssh/sshd_config && \
    sed -i "s/[# ]*PermitUserEnvironment no/PermitUserEnvironment yes/" /etc/ssh/sshd_config && \
    sed -i "s/[# ]*Port.*/Port 22/" /etc/ssh/sshd_config && \
    echo -e "* soft nofile 1048576\n* hard nofile 1048576" >> /etc/security/limits.conf && \
    echo -e "root soft nofile 1048576\nroot hard nofile 1048576" >> /etc/security/limits.conf

# Install OpenMPI
ENV OPENMPI_VERSION=4.0.5
RUN cd /tmp && \
    wget -q https://www.open-mpi.org/software/ompi/v4.0/downloads/openmpi-${OPENMPI_VERSION}.tar.gz && \
    tar xzf openmpi-${OPENMPI_VERSION}.tar.gz && \
    cd openmpi-${OPENMPI_VERSION} && \
    ./configure --enable-orterun-prefix-by-default && \
    make -j $(nproc) all && \
    make install && \
    ldconfig && \
    rm -rf /tmp/openmpi-${OPENMPI_VERSION}*

# Install OFED
ENV OFED_VERSION=5.2-2.2.3.0
RUN cd /tmp && \
    wget -q http://content.mellanox.com/ofed/MLNX_OFED-${OFED_VERSION}/MLNX_OFED_LINUX-${OFED_VERSION}-ubuntu18.04-x86_64.tgz && \
    tar xzf MLNX_OFED_LINUX-${OFED_VERSION}-ubuntu18.04-x86_64.tgz && \
    PATH=/usr/bin:${PATH} MLNX_OFED_LINUX-${OFED_VERSION}-ubuntu18.04-x86_64/mlnxofedinstall --user-space-only --without-fw-update --force --all && \
    rm -rf MLNX_OFED_LINUX-${OFED_VERSION}*

ENV PATH="${PATH}" \
    LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH}" \
    SB_HOME="/opt/superbench" \
    SB_MICRO_PATH="/opt/superbench"

WORKDIR ${SB_HOME}

ADD third_party third_party
RUN echo gfx90a >> /opt/rocm/bin/target.lst && ROCM_VERSION=rocm-5.0.0 make -j -C third_party -o rocm_rocblas rocm

ADD . .
RUN python3 -m pip install .[torch] && \
    make cppbuild

ADD /home/amduser/ubuntu2004 /home/amduser/
RUN echo -e  "deb [trusted=yes arch=amd64] file:/home/amduser/ubuntu2004 ./" > /etc/apt/source.list.d/rocm.list  && \
    sudo apt update && \
    sudo apt install libboost-program-options-dev && \
    sudo apt install libomp-dev && \
    sudo apt install gfortran-7 && \
    sudo apt install rocblas-clients && \
    cp -v /opt/rocm/rocblas/bin/rocblas-bench ${SB_MICRO_PATH}/bin/

RUN cd /opt/rocm && \
    git clone -b release/rocm-rel-5.0 https://github.com/ROCmSoftwarePlatform/rccl-rdma-sharp-plugins.git && \
    cd rccl-rdma-sharp-plugins && \
    ./autogen.sh && ./configure && make -j64
