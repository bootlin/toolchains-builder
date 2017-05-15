#!/bin/bash

echo "Building $1"
echo "Target: $2"

if [ "$2" == "ci_debug" ]; then
    echo "ci_debug is set as target, you should see this line, but the build won't go further."
    echo "Exiting properly."
    exit 0;
fi

if git clone git://git.buildroot.net/buildroot; then
    # buildroot needs patchs
    cd buildroot
    curl http://free-electrons.com/~thomas/pub/0001-mpc-mpfr-gmp-build-statically-for-the-host.patch |patch -p1
    curl http://free-electrons.com/~thomas/pub/0002-toolchain-attempt-to-fix-the-toolchain-wrapper.patch |patch -p1
    cd ..
fi

main_dir=$(pwd)
build_dir=${main_dir}/builds
chroot_script="build_chroot.sh"
buildroot_dir=${main_dir}/buildroot

function set_qemu_config {
    if [ ${arch} == "arm" ]; then
        qemu_defconfig="qemu_arm_versatile_defconfig"
        qemu_system_command="qemu-system-arm
            -machine versatilepb
            -kernel ${test_dir}/images/zImage
            -dtb ${test_dir}/images/versatile-pb.dtb
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk
            -append \"root=/dev/sda rw\""
    elif [ ${arch} == "aarch64" ]; then
        qemu_defconfig="qemu_aarch64_virt_defconfig"
        # Qemu 2.9 has been tested and works, 2.5 does not.
        qemu_system_command="qemu-system-aarch64
            -machine virt -cpu cortex-a57 -machine type=virt
            -kernel ${test_dir}/images/Image
            -append \"console=ttyAMA0\""
    elif [ ${arch} == "mips" ]; then
        qemu_defconfig="qemu_mips32r2_malta_defconfig"
        qemu_system_command="qemu-system-mips
            -machine malta
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk
            -append \"root=/dev/hda rw\""
    elif [ ${arch} == "mipsel" ]; then
        qemu_defconfig="qemu_mips32r2el_malta_defconfig"
        qemu_system_command="qemu-system-mipsel
            -machine malta
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk
            -append \"root=/dev/hda rw\""
    fi
}

function boot_test {
    echo "  booting test system ... "
    qemu_system_command="${qemu_system_command}
            -serial telnet:127.0.0.1:4000,server,nowait,nodelay
            -nographic"
    echo "  boot command: ${qemu_system_command}"
    eval ${qemu_system_command} &
    echo $! > /tmp/qemu-test.pid
    sleep 2
    if ! ps p $(cat /tmp/qemu-test.pid) &>/dev/null; then
        echo "  Failed to launch qemu ... Not going further"
        return 1
    fi
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
    rm -rf ${test_dir}
    mkdir ${test_dir}
    cp -r overlay ${overlaydir}

    # Generate the full qemu system configuration
    testconfigfile=${test_dir}/.config
    echo "  generating configuration"
    cp ${buildroot_dir}/configs/${qemu_defconfig} ${testconfigfile}
    echo "BR2_ROOTFS_OVERLAY=\"${test_dir}/overlay\"" >> ${testconfigfile}
    echo "BR2_TOOLCHAIN_EXTERNAL=y" >> ${testconfigfile}
    echo "BR2_TOOLCHAIN_EXTERNAL_CUSTOM=y" >> ${testconfigfile}
    echo "BR2_TOOLCHAIN_EXTERNAL_PREINSTALLED=y" >> ${testconfigfile}
    echo "BR2_TOOLCHAIN_EXTERNAL_PATH=\"${toolchain_dir}\"" >> ${testconfigfile}
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
    make -C ${buildroot_dir} O=${test_dir} olddefconfig > /dev/null 2>&1
    echo "  building test system"
    make -C ${buildroot_dir} O=${test_dir} > ${testlogfile} 2>&1
    if [ $? -ne 0 ] ; then
        echo "  finished test system build at $(date) ... FAILED"
        return 1
    fi
    echo "  finished test system build at $(date) ... SUCCESS"
}

function launch_build {
    echo "  Setup chroot and launch build"
    rm -rf ${build_dir}
    mkdir -p ${build_dir}
    debootstrap --variant=buildd lenny ${build_dir} http://archive.debian.org/debian/
    cp ${chroot_script} ${build_dir}
    cp ${1}.config ${build_dir}
    cp chroot.conf /etc/schroot/schroot.conf
    cp /etc/resolv.conf ${build_dir}/etc/resolv.conf
    echo "  chrooting to ${build_dir}"
    chroot ${build_dir} ./build_chroot.sh $1
}

function generate {
    name=$1

    echo "Generating ${name}..."
    launch_build $1

    toolchain_name=$(basename ${build_dir}/${name}-*)
    toolchain_dir="${build_dir}/${toolchain_name}"
    configfile=${toolchain_dir}/buildroot.config
    test_dir=${toolchain_dir}-tests
    testlogfile=${build_dir}/${toolchain_name}-test.log

    overlaydir=${test_dir}/overlay
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

    # Everything works, package the toolchain
    (cd ${build_dir}; tar cjf `basename ${toolchain_dir}`.tar.bz2 `basename
    ${toolchain_dir}`)

    # Remove toolchain directory
    # rm -rf ${toolchain_dir}

    # Remove build directory
    # rm -rf ${builddir}
}

if [ $# -eq 1 ]; then
    generate $1
else
    echo "Usage: $0 configname.config"
fi


