#!/bin/bash

apt-get install -y --force-yes -qq --no-install-recommends \
    build-essential locales bc ca-certificates file rsync gcc-multilib \
    git bzr cvs mercurial subversion unzip wget cpio curl git-core \

sed -i 's/# \(en_US.UTF-8\)/\1/' /etc/locale.gen
/usr/sbin/locale-gen

if git clone git://git.buildroot.net/buildroot; then
    # buildroot needs patchs
    cd buildroot
    curl http://free-electrons.com/~thomas/pub/0001-mpc-mpfr-gmp-build-statically-for-the-host.patch |patch -p1
    curl http://free-electrons.com/~thomas/pub/0002-toolchain-attempt-to-fix-the-toolchain-wrapper.patch |patch -p1
    cd ..
fi

TOOLCHAIN_DIR=$(pwd)
TOOLCHAIN_BUILD_DIR=${TOOLCHAIN_DIR}
TOOLCHAIN_BR_DIR=${TOOLCHAIN_DIR}/buildroot
TOOLCHAIN_VERSION=$(git --git-dir=${TOOLCHAIN_BR_DIR}/.git describe)

name=$1
toolchaindir=${TOOLCHAIN_BUILD_DIR}/${name}-${TOOLCHAIN_VERSION}
logfile=${TOOLCHAIN_BUILD_DIR}/${name}-${TOOLCHAIN_VERSION}-build.log
builddir=${TOOLCHAIN_BUILD_DIR}/toolchain-build
configfile=${builddir}/.config

mkdir -p ${TOOLCHAIN_BUILD_DIR} &>/dev/null

function build {
    # Create output directory for the new toolchain
    rm -rf ${toolchaindir}
    mkdir ${toolchaindir}

    # Create build directory for the new toolchain
    rm -rf ${builddir}
    mkdir ${builddir}

    # Create the configuration
    cp ${name}.config ${configfile}
    echo "BR2_JLEVEL=16" >> ${configfile}
    echo "BR2_HOST_DIR=\"${toolchaindir}\"" >> ${configfile}

    echo "  starting at $(date)"

    # Generate the full configuration
    make -C ${TOOLCHAIN_BR_DIR} O=${builddir} olddefconfig > /dev/null 2>&1

    # Build
    make -C ${TOOLCHAIN_BR_DIR} O=${builddir} > ${logfile} 2>&1
    if [ $? -ne 0 ] ; then
        echo "  finished at $(date) ... FAILED"
        echo "  printing the logs before exiting"
        echo "=================== BEGIN LOG FILE ======================"
        cat ${logfile}
        echo "==================== END LOG FILE ======================="
        return 1
    fi

    echo "  finished at $(date) ... SUCCESS"
    cp ${configfile} ${toolchaindir}/buildroot.config
    mv ${toolchaindir}/usr/* ${toolchaindir}/
    rmdir ${toolchaindir}/usr
    # Toolchain built
}

if [ $# -eq 1 ]; then
    echo "Generating ${name}..."
    if ! build $1; then
        echo "Error in toolchain build. Exiting"
        exit 1
    fi
else
    echo "Usage: $0 toolchain_name"
fi


