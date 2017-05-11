#!/bin/bash

TOOLCHAIN_DIR=/home/skia/workspace/toolchains
TOOLCHAIN_BUILD_DIR=${TOOLCHAIN_DIR}/build/
TOOLCHAIN_BR_DIR=${TOOLCHAIN_BUILD_DIR}/buildroot
TOOLCHAIN_VERSION=$(git --git-dir=${TOOLCHAIN_BR_DIR}/.git describe)

function set_qemu_config {
    if [ ${arch} == "arm" ]; then
        qemu_defconfig="qemu_arm_versatile_defconfig"
        qemu_machine="versatilepb"
        qemu_dtb="versatile-pb.dtb"
    elif [ ${arch} == "aarch64" ]; then
        qemu_defconfig="qemu_aarch64_virt_defconfig"
        qemu_machine="virt"
        qemu_dtb="virt.dtb"
    fi
}
function eval_command() {
  "$@";
}

function boot_test {
    # cd ${testdir}/images
    macaddress="f8:ca:b8:3f:ae:e9"
    echo "  booting test system ... "
    qemu-system-${arch} \
        -machine ${qemu_machine} \
        -kernel ${testdir}/images/zImage \
        -dtb ${testdir}/images/${qemu_dtb} \
        -hda ${testdir}/images/rootfs.ext2 \
        -append "root=/dev/sda rw" \
        -serial telnet:127.0.0.1:4000,server,nowait,nodelay \
        -nographic &
    echo $! > /tmp/qemu-test.pid
    sleep 2
    if ! expect expect.sh; then
        echo "  booting test system ... FAILED"
        kill -9 $(cat /tmp/qemu-test.pid)
        return 1
    fi
    echo "  booting test system ... SUCCESS"
    kill -9 $(cat /tmp/qemu-test.pid)
}

function build_test {
    # Create test directory for the new toolchain
    rm -rf ${testdir}
    mkdir ${testdir}
    cp -r overlay ${overlaydir}

    # Generate the full qemu system configuration
    testconfigfile=${testdir}/.config
    echo "  generating configuration"
    cp ${TOOLCHAIN_BR_DIR}/configs/${qemu_defconfig} ${testconfigfile}
    echo "BR2_ROOTFS_OVERLAY=\"${testdir}/overlay\"" >> ${testconfigfile}
    echo "BR2_TOOLCHAIN_EXTERNAL=y" >> ${testconfigfile}
    echo "BR2_TOOLCHAIN_EXTERNAL_CUSTOM=y" >> ${testconfigfile}
    echo "BR2_TOOLCHAIN_EXTERNAL_PREINSTALLED=y" >> ${testconfigfile}
    echo "BR2_TOOLCHAIN_EXTERNAL_PATH=\"${toolchaindir}\"" >> ${testconfigfile}
    echo "BR2_TOOLCHAIN_EXTERNAL_GCC_${gcc_version}=y" >> ${testconfigfile}
    echo "BR2_TOOLCHAIN_EXTERNAL_HEADERS_${linux_version}=y" >> ${testconfigfile}
    if [ ${locale} == "y" ]; then
        echo "BR2_TOOLCHAIN_EXTERNAL_LOCALE=y" >> ${testconfigfile}
    fi
    if grep "BR2_PTHREAD_DEBUG is not set" ${configfile} > /dev/null 2>&1; then
        echo "BR2_TOOLCHAIN_EXTERNAL_HAS_THREADS_DEBUG=n" >> ${testconfigfile}
    fi

    # Starting the system build
    echo "  starting test system build at $(date)"
    echo "  making old config"
    make -C ${TOOLCHAIN_BR_DIR} O=${testdir} olddefconfig > /dev/null 2>&1
    echo "  building test system"
    make -C ${TOOLCHAIN_BR_DIR} O=${testdir} > ${testlogfile} 2>&1
    if [ $? -ne 0 ] ; then
        echo "  finished test system build at $(date) ... FAILED"
        return 1
    fi
    echo "  finished test system build at $(date) ... SUCCESS"
}

function build {
    # Create output directory for the new toolchain
    rm -rf ${toolchaindir}
    mkdir ${toolchaindir}

    # Create build directory for the new toolchain
    rm -rf ${builddir}
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
    build

    overlaydir=${testdir}/overlay
    arch=$(grep "BR2_ARCH=" ${configfile} | sed 's/BR2_ARCH="\(.*\)"/\1/')
    endianess=$(grep "BR2_ENDIAN=" ${configfile} | sed 's/BR2_ENDIAN="\(.*\)"/\1/')
    gcc_version=$(grep "^BR2_GCC_VERSION_" ${configfile} | sed 's/BR2_GCC_VERSION_\(.*\)_X=.*/\1/')
    linux_version=$(grep "^BR2_KERNEL_HEADERS_" ${configfile} | sed 's/BR2_KERNEL_HEADERS_\(.*\)=./\1/')
    locale=$(grep "^BR2_TOOLCHAIN_BUILDROOT_LOCALE" ${configfile} | sed 's/BR2_TOOLCHAIN_BUILDROOT_LOCALE=\(.\)/\1/')
    set_qemu_config

    # Test the toolchain
    echo "Building a test system using ${name}..."
    build_test

    echo "Booting the test system in qemu..."
    boot_test
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


