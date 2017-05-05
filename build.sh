#!/bin/bash

TOOLCHAIN_DIR=/home/skia/workspace/toolchains
TOOLCHAIN_BUILD_DIR=${TOOLCHAIN_DIR}/build/
TOOLCHAIN_BR_DIR=${TOOLCHAIN_BUILD_DIR}/buildroot
TOOLCHAIN_VERSION=$(git --git-dir=${TOOLCHAIN_BR_DIR}/.git describe)

function build {
    name=$1
    toolchaindir=/opt/${name}-${TOOLCHAIN_VERSION}
    logfile=/opt/${name}-${TOOLCHAIN_VERSION}-build.log
    builddir=/opt/toolchain-build/

    echo "Building ${name}..."

    # Create output directory for the new toolchain
    rm -rf ${toolchaindir}
    mkdir ${toolchaindir}

    # Create build directory for the new toolchain
    rm -rf ${builddir}
    mkdir ${builddir}

    # Create the configuration
    configfile=${builddir}/.config
    cp ${TOOLCHAIN_BUILD_DIR}/${name}.config ${configfile}
    echo "BR2_JLEVEL=16" >> ${configfile}
    echo "BR2_HOST_DIR=\"${toolchaindir}\"" >> ${configfile}

    echo "  starting at $(date)"

    # Generate the full configuration
    make -C ${TOOLCHAIN_BR_DIR} O=${builddir} olddefconfig > /dev/null 2>&1

    # Build
    make -C ${TOOLCHAIN_BR_DIR} O=${builddir} > ${logfile} 2>&1
    if [ $? -ne 0 ] ; then
        echo "  finished at $(date) ... FAILED"
        return
    fi

    echo "  finished at $(date) ... SUCCESS"
    cp ${configfile} ${toolchaindir}/buildroot.config

    mv ${toolchaindir}/usr/* ${toolchaindir}/
    rmdir ${toolchaindir}/usr
    (cd /opt; tar cjf `basename ${toolchaindir}`.tar.bz2 `basename ${toolchaindir}`)

    # Remove toolchain directory
    rm -rf ${toolchaindir}

    # Remove build directory
    rm -rf ${builddir}
}

if [ $# -eq 1 ]; then
    build $1
else
    for toolchain in *.config ; do
        build ${toolchain%%.config}
    done
fi


