#!/bin/bash

echo "Building $1"
echo "Target: $2"
echo "Buildroot tree: $3"

name="$1"
target="$2"
buildroot_tree="$3"

if [ "$target" == "ci_debug" ]; then
    echo "ci_debug is set as target, you should see this line, but the build won't go further."
    echo "Exiting properly."
    exit 0;
fi

if git clone https://github.com/buildroot/buildroot.git; then
    # buildroot needs patchs
    cd buildroot
    git checkout $buildroot_tree
    curl http://free-electrons.com/~thomas/pub/0001-mpc-mpfr-gmp-build-statically-for-the-host.patch |patch -p1
    curl http://free-electrons.com/~thomas/pub/0002-toolchain-attempt-to-fix-the-toolchain-wrapper.patch |patch -p1
    cd ..
fi

ssh_server="gitlabci@libskia.so"
main_dir=$(pwd)
build_dir=${main_dir}/builds
chroot_script="build_chroot.sh"
buildroot_dir=${main_dir}/buildroot
fragment_file=${build_dir}/br_fragment

function set_qemu_config {
    arch_name=$(echo "${toolchain_name}" |sed "s/--/\t/" |cut -f 1)
    if [ ${arch_name} == "arm" ]; then
        qemu_defconfig="qemu_arm_versatile_defconfig"
        qemu_system_command="qemu-system-arm
            -machine versatilepb
            -kernel ${test_dir}/images/zImage
            -dtb ${test_dir}/images/versatile-pb.dtb
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk
            -append \"root=/dev/sda rw\""
    elif [ ${arch_name} == "aarch64" ]; then
        qemu_defconfig="qemu_aarch64_virt_defconfig"
        # Qemu 2.8 has been tested and works, 2.5 does not.
        qemu_system_command="qemu-system-aarch64
            -machine virt -cpu cortex-a57 -machine type=virt
            -kernel ${test_dir}/images/Image
            -append \"console=ttyAMA0\""
    elif [ ${arch_name} == "i386-core2" ]; then
        qemu_defconfig="qemu_x86_defconfig"
        qemu_system_command="qemu-system-i386
            -machine pc
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk
            -append \"root=/dev/hda rw\""
    elif [ ${arch_name} == "i386-i686" ]; then
        qemu_defconfig="qemu_x86_defconfig"
        qemu_system_command="qemu-system-i386
            -machine pc
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk
            -append \"root=/dev/hda rw\""
    elif [ ${arch_name} == "mips" ]; then
        qemu_defconfig="qemu_mips32r2_malta_defconfig"
        qemu_system_command="qemu-system-mips
            -machine malta
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk
            -append \"root=/dev/hda rw\""
    elif [ ${arch_name} == "mipsel" ]; then
        qemu_defconfig="qemu_mips32r2el_malta_defconfig"
        qemu_system_command="qemu-system-mipsel
            -machine malta
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk
            -append \"root=/dev/hda rw\""
    elif [ ${arch_name} == "m68k-68040" ]; then
        qemu_defconfig="qemu_m68k_q800_defconfig"
        qemu_system_command="qemu-system-m68k
            -machine an5206
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk
            -append \"root=/dev/hda rw\""
    elif [ ${arch_name} == "m68k-508" ]; then
        qemu_defconfig="qemu_m68k_mcf5208_defconfig"
        qemu_system_command="qemu-system-m68k
            -machine mcf5208evb
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
    cat ${fragment_file} >> ${testconfigfile}

    # Starting the system build
    echo "  starting test system build at $(date)"
    echo "  making old config"
    make -C ${buildroot_dir} O=${test_dir} olddefconfig > /dev/null 2>&1
    echo "  building test system"
    make -C ${buildroot_dir} O=${test_dir} > ${testlogfile} 2>&1
    if [ $? -ne 0 ] ; then
        echo "  finished test system build at $(date) ... FAILED"
        echo "  printing the end of the logs before exiting"
        echo "=================== BEGIN LOG FILE ======================"
        tail -n 200 ${testlogfile}
        echo "==================== END LOG FILE ======================="
        return 1
    fi
    echo "  finished test system build at $(date) ... SUCCESS"
}

function launch_build {
    echo "  Setup chroot and launch build"
    rm -rf ${build_dir}
    mkdir -p ${build_dir}
    debootstrap --variant=buildd squeeze ${build_dir} http://archive.debian.org/debian/ 2>&1 1>/dev/null
    cp ${chroot_script} ${build_dir}
    cp ${name}.config ${build_dir}
    cp chroot.conf /etc/schroot/schroot.conf
    cp /etc/resolv.conf ${build_dir}/etc/resolv.conf
    echo "  chrooting to ${build_dir}"
    chroot ${build_dir} ./build_chroot.sh ${name} ${buildroot_tree}
}

function make_br_fragment {
    arch=$(grep "BR2_ARCH=" ${configfile} | sed 's/BR2_ARCH="\(.*\)"/\1/')
    endianess=$(grep "BR2_ENDIAN=" ${configfile} | sed 's/BR2_ENDIAN="\(.*\)"/\1/')
    gcc_version=$(grep "^BR2_GCC_VERSION_" ${configfile} | sed 's/BR2_GCC_VERSION_\(.*\)_X=.*/\1/')
    linux_version=$(grep "^BR2_KERNEL_HEADERS_" ${configfile} | sed 's/BR2_KERNEL_HEADERS_\(.*\)=./\1/')
    locale=$(grep "^BR2_TOOLCHAIN_BUILDROOT_LOCALE" ${configfile} | sed 's/BR2_TOOLCHAIN_BUILDROOT_LOCALE=\(.\)/\1/')
    libc=$(grep "^BR2_TOOLCHAIN_BUILDROOT_LIBC=\".*\"" ${configfile} | sed 's/BR2_TOOLCHAIN_BUILDROOT_LIBC="\(.*\)"/\1/')

    echo "BR2_WGET=\"wget --passive-ftp -nd -t 3 --no-check-certificate\"" >> ${fragment_file}
    echo "BR2_TOOLCHAIN_EXTERNAL=y" >> ${fragment_file}
    echo "BR2_TOOLCHAIN_EXTERNAL_CUSTOM=y" >> ${fragment_file}
    echo "BR2_TOOLCHAIN_EXTERNAL_PREINSTALLED=y" >> ${fragment_file}
    echo "BR2_TOOLCHAIN_EXTERNAL_PATH=\"${toolchain_dir}\"" >> ${fragment_file}
    echo "BR2_TOOLCHAIN_EXTERNAL_GCC_${gcc_version}=y" >> ${fragment_file}
    echo "BR2_TOOLCHAIN_EXTERNAL_HEADERS_${linux_version}=y" >> ${fragment_file}
    if [ "${locale}" == "y" ]; then
        echo "BR2_TOOLCHAIN_EXTERNAL_LOCALE=y" >> ${fragment_file}
    fi
    if grep "BR2_PTHREAD_DEBUG is not set" ${configfile} > /dev/null 2>&1; then
        echo "BR2_TOOLCHAIN_EXTERNAL_HAS_THREADS_DEBUG=n" >> ${fragment_file}
    fi
    if [ "${libc}" == "glibc" ]; then
        echo "BR2_TOOLCHAIN_EXTERNAL_CUSTOM_GLIBC=y" >> ${fragment_file}
    elif [ "${libc}" == "musl" ]; then
        echo "BR2_TOOLCHAIN_EXTERNAL_CUSTOM_MUSL=y" >> ${fragment_file}
    fi
}

function generate {
    echo "Generating ${name}..."
    if ! launch_build; then
        echo "Toolchain build failed, not going further"
        exit 1
    fi

    toolchain_name=$(basename ${build_dir}/${name}-*)
    toolchain_dir="${build_dir}/${toolchain_name}"
    configfile=${toolchain_dir}/buildroot.config
    test_dir=${build_dir}/test-${toolchain_name}
    testlogfile=${build_dir}/test-${toolchain_name}-build.log
    overlaydir=${test_dir}/overlay

    make_br_fragment
    set_qemu_config

    return_value=0
    # Test the toolchain
    echo "Building a test system using ${name}..."
    if build_test; then
        echo "Booting the test system in qemu..."
        if boot_test; then
            echo "Booting passed"
        else
            echo "Booting failed"
            return_value=1
        fi
    else
        echo "Test system failed to build"
        return_value=1
    fi

    if [ $return_value -eq 1 ]; then
        echo "THIS TOOLCHAIN MAY NOT WORK, OR THERE MAY BE A PROBLEM IN THE CONFIGURATION, PLEASE CHECK!"
        toolchain_name="${toolchain_name}-UNTESTED"
        return_value=0
    fi

    # Everything works, package the toolchain
    echo "Packaging the toolchain as ${toolchain_name}.tar.bz2"
    cd ${build_dir}
    cp ${fragment_file} ${toolchain_dir}
    tar cjf `basename ${toolchain_name}`.tar.bz2 `basename ${toolchain_dir}`
    scp "${toolchain_name}.tar.bz2" ${ssh_server}:
    return $return_value
}

if [ $# -eq 3 ]; then
    if ! generate ${name}; then
        echo "Something went wrong. Exiting with code 1"
        exit 1
    fi
else
    echo "Usage: $0 configname.config target buildroot-tree"
    exit 1
fi


