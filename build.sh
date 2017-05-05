#!/bin/bash

TOOLCHAIN_DIR=/home/skia/workspace/toolchains
TOOLCHAIN_BUILD_DIR=${TOOLCHAIN_DIR}/build/
TOOLCHAIN_BR_DIR=${TOOLCHAIN_BUILD_DIR}/buildroot
TOOLCHAIN_VERSION=$(git --git-dir=${TOOLCHAIN_BR_DIR}/.git describe)

function get_qemu_defconfig {
    echo ${arch}
    echo ${endianess}
    if [ ${arch} == "arm" ]; then
        qemu_defconfig="qemu_arm_versatile_defconfig"
    fi
}

function check {
    arch=$(grep "BR2_ARCH=" ${configfile} | sed 's/BR2_ARCH="\(.*\)"/\1/')
    endianess=$(grep "BR2_ENDIAN=" ${configfile} | sed 's/BR2_ENDIAN="\(.*\)"/\1/')
    gcc_version=$(grep "^BR2_GCC_VERSION_" ${configfile} | sed 's/BR2_GCC_VERSION_\(.*\)_X=.*/\1/')
    linux_version=$(grep "^BR2_KERNEL_HEADERS_" ${configfile} | sed 's/BR2_KERNEL_HEADERS_\(.*\)=./\1/')

    get_qemu_defconfig

    # Create test directory for the new toolchain
    rm -rf ${testdir}
    mkdir ${testdir}

    # Generate the full qemu system configuration
    testconfigfile=${testdir}/.config
    cp ${TOOLCHAIN_BR_DIR}/configs/${qemu_defconfig} ${testconfigfile}
    echo "BR2_TOOLCHAIN_EXTERNAL=y" >> ${testconfigfile}
    echo "BR2_TOOLCHAIN_EXTERNAL_CUSTOM=y" >> ${testconfigfile}
    echo "BR2_TOOLCHAIN_EXTERNAL_PREINSTALLED=y" >> ${testconfigfile}
    echo "BR2_TOOLCHAIN_EXTERNAL_PATH=\"${toolchaindir}\"" >> ${testconfigfile}
    echo "BR2_TOOLCHAIN_EXTERNAL_GCC_${gcc_version}=y" >> ${testconfigfile}
    echo "BR2_TOOLCHAIN_EXTERNAL_HEADERS_${linux_version}=y" >> ${testconfigfile}
    echo "  starting test system build at $(date)"
    echo "Making old config"
    make -C ${TOOLCHAIN_BR_DIR} O=${testdir} olddefconfig > /dev/null 2>&1
    echo "Building test system"
    make -C ${TOOLCHAIN_BR_DIR} O=${testdir} > ${testlogfile} 2>&1
    if [ $? -ne 0 ] ; then
        echo "  finished test system build at $(date) ... FAILED"
        return
    fi
    echo "  finished test system build at $(date) ... SUCCESS"
}

function build {
    # Create output directory for the new toolchain
    # rm -rf ${toolchaindir}
    mkdir ${toolchaindir}

    # Create build directory for the new toolchain
    # rm -rf ${builddir}
    mkdir ${builddir}

    # Create the configuration
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
    # Toolchain built
}

function generate {
    name=$1
    toolchaindir=/opt/${name}-${TOOLCHAIN_VERSION}
    testdir=${toolchaindir}-tests
    logfile=/opt/${name}-${TOOLCHAIN_VERSION}-build.log
    testlogfile=/opt/${name}-${TOOLCHAIN_VERSION}-test.log
    builddir=/opt/toolchain-build/
    configfile=${builddir}/.config

    echo "Generating ${name}..."

    # build

    # Test the toolchain
    check

    return

    # Everything works, package the toolchain
    (cd /opt; tar cjf `basename ${toolchaindir}`.tar.bz2 `basename ${toolchaindir}`)

    # Remove toolchain directory
    # rm -rf ${toolchaindir}

    # Remove build directory
    # rm -rf ${builddir}
}

if [ $# -eq 1 ]; then
    generate $1
else
    for toolchain in *.config ; do
        generate ${toolchain%%.config}
    done
fi


