#!/bin/bash

echo "Building $1"
echo "Target: $2"
echo "Buildroot tree: $3"
echo "Version number: $4"

name="$1"
target="$2"
buildroot_tree="$3"
version_number="$4"

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
    curl "https://git.buildroot.org/buildroot/patch/?id=4d1c2c82e8945a5847d636458f3825c55529835b" |patch -p1
    cd ..
fi

ssh_server="gitlabci@toolchains.free-electrons.com"
main_dir=$(pwd)
frag_dir=${main_dir}/frags
build_dir=${main_dir}/builds
chroot_script="build_chroot.sh"
buildroot_dir=${main_dir}/buildroot
fragment_file=${build_dir}/br_fragment
base_url="https:\/\/toolchains.free-electrons.com\/${target}\/toolchains"

function set_qemu_config {
    if [[ "${arch_name}" =~ ^"armv".* ]]; then                           # arm*
        qemu_defconfig="qemu_arm_vexpress_defconfig"
        qemu_system_command="qemu-system-arm
            -machine vexpress-a9
            -kernel ${test_dir}/images/zImage
            -dtb ${test_dir}/images/vexpress-v2p-ca9.dtb
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk,format=raw
            -append \"root=/dev/sda rw\""
    elif [[ "${arch_name}" == "aarch64" ]]; then                        # aarch64
        qemu_defconfig="qemu_aarch64_virt_defconfig"
        # Qemu 2.8 has been tested and works, 2.5 does not.
        qemu_system_command="qemu-system-aarch64
            -machine virt -cpu cortex-a53 -machine type=virt
            -kernel ${test_dir}/images/Image
            -append \"console=ttyAMA0\""
    elif [[ "${arch_name}" == "aarch64be" ]]; then                      # aarch64be
        qemu_defconfig="qemu_aarch64_virt_defconfig"
        # Qemu 2.8 has been tested and works, 2.5 does not.
        qemu_system_command="qemu-system-aarch64
            -machine virt -cpu cortex-a53 -machine type=virt
            -kernel ${test_dir}/images/Image
            -append \"console=ttyAMA0\""
    elif [[ "${arch_name}" == "bfin" ]]; then                           # bfin
        qemu_defconfig="gdb_bfin_bf512_defconfig"
        qemu_system_command=""
    elif [[ "${arch_name}" == "microblazebe" ]]; then                   # microblazebe
        qemu_defconfig="qemu_microblazebe_mmu_defconfig"
        qemu_system_command="qemu-system-microblaze
            -machine petalogix-s3adsp1800
            -kernel ${test_dir}/images/linux.bin
            -drive file=${test_dir}/images/rootfs.cpio,index=0,media=disk,format=raw
            -append \"root=/dev/sda rw\""
    elif [[ "${arch_name}" == "microblazeel" ]]; then                   # microblazeel
        qemu_defconfig="qemu_microblazeel_mmu_defconfig"
        qemu_system_command="qemu-system-microblazeel
            -machine petalogix-s3adsp1800
            -kernel ${test_dir}/images/linux.bin
            -drive file=${test_dir}/images/rootfs.cpio,index=0,media=disk,format=raw
            -append \"root=/dev/sda rw\""
    elif [[ "${arch_name}" == "mips32" ]]; then                         # mips32
        qemu_defconfig="qemu_mips32r2_malta_defconfig"
        qemu_system_command="qemu-system-mips
            -machine malta
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk,format=raw
            -append \"root=/dev/hda rw\""
    elif [[ "${arch_name}" == "mips32el" ]]; then                       # mips32el
        qemu_defconfig="qemu_mips32r2el_malta_defconfig"
        qemu_system_command="qemu-system-mipsel
            -machine malta
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk,format=raw
            -append \"root=/dev/hda rw\""
    elif [[ "${arch_name}" == "mips32r5el" ]]; then                     # mips32r5el
        qemu_defconfig="qemu_mips32r2el_malta_defconfig"
        qemu_system_command="qemu-system-mipsel
            -machine malta
            -cpu P5600
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk,format=raw
            -append \"root=/dev/hda rw\""
    elif [[ "${arch_name}" == "mips32r6el" ]]; then                     # mips32r6el
        qemu_defconfig="qemu_mips32r6el_malta_defconfig"
        qemu_system_command="qemu-system-mipsel
            -machine malta
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk,format=raw
            -append \"root=/dev/hda rw\""
    elif [[ "${arch_name}" == "mips64" ]]; then                         # mips64
        qemu_defconfig="qemu_mips64_malta_defconfig"
        qemu_system_command="qemu-system-mips64
            -machine malta
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk,format=raw
            -append \"root=/dev/hda rw\""
    elif [[ "${arch_name}" == "mips64el" ]]; then                       # mips64el
        qemu_defconfig="qemu_mips64el_malta_defconfig"
        qemu_system_command="qemu-system-mips64el
            -machine malta
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk,format=raw
            -append \"root=/dev/hda rw\""
    elif [[ "${arch_name}" == "mips64r6el" ]]; then                     # mips64r6el
        qemu_defconfig="qemu_mips64r6el_malta_defconfig"
        qemu_system_command="qemu-system-mips64el
            -machine malta
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk,format=raw
            -append \"root=/dev/hda rw\""
    elif [[ "${arch_name}" == "m68k-68xxxx" ]]; then                    # m68k-68xxxx
        qemu_defconfig="qemu_m68k_q800_defconfig"
        qemu_system_command="qemu-system-m68k
            -machine an5206
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk,format=raw
            -append \"root=/dev/hda rw\""
    elif [[ "${arch_name}" == "m68k-coldfire" ]]; then                  # m68k-coldfire
        qemu_defconfig="qemu_m68k_mcf5208_defconfig"
        qemu_system_command="qemu-system-m68k
            -machine mcf5208evb
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk,format=raw
            -append \"root=/dev/hda rw\""
    elif [[ "${arch_name}" == "nios2" ]]; then                          # nios2
        qemu_defconfig="qemu_nios2_10m50_defconfig"
        qemu_system_command="qemu-system-nios2
            -kernel ${test_dir}/images/vmlinux"
    elif [[ "${arch_name}" == "powerpc64-power8" ]]; then               # powerpc64-power8
        qemu_defconfig="qemu_ppc64_pseries_defconfig"
        sed -i "s/hvc0/ttyS0/" ${buildroot_dir}/configs/${qemu_defconfig}
        qemu_system_command="qemu-system-ppc64
            -machine pseries
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk,format=raw
            -append \"root=/dev/sda rw\""
    elif [[ "${arch_name}" == "sh4" ]]; then                            # sh4
        qemu_defconfig="qemu_sh4_r2d_defconfig"
        qemu_system_command="qemu-system-sh4
            -machine r2d
            -kernel ${test_dir}/images/zImage
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk,format=raw
            -append \"root=/dev/sda rw console=ttySC1,115200 noiotrap\""
    elif [[ "${arch_name}" == "sparc64" ]]; then                        # sparc64
        qemu_defconfig="qemu_sparc64_sun4u_defconfig"
        qemu_system_command="qemu-system-sparc64
            -machine sun4u
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk,format=raw
            -append \"root=/dev/sda rw console=ttyS0,115200\""
    elif [[ "${arch_name}" == "sparcv8" ]]; then                        # sparcv8
        qemu_defconfig="qemu_sparc_ss10_defconfig"
        qemu_system_command="qemu-system-sparc
            -machine SS-10
            -kernel ${test_dir}/images/zImage
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk,format=raw
            -append \"root=/dev/sda rw console=ttyS0,115200\""
    elif [[ "${arch_name}" == "x86-core2" ]]; then                      # x86-core2
        qemu_defconfig="qemu_x86_defconfig"
        sed -i "s/tty1/ttyS0/" ${buildroot_dir}/configs/${qemu_defconfig}
        qemu_system_command="qemu-system-i386
            -machine pc
            -kernel ${test_dir}/images/bzImage
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk,format=raw
            -append \"root=/dev/sda rw console=ttyS0\""
    elif [[ "${arch_name}" == "x86-i686" ]]; then                       # x86-i686
        qemu_defconfig="qemu_x86_defconfig"
        sed -i "s/tty1/ttyS0/" ${buildroot_dir}/configs/${qemu_defconfig}
        qemu_system_command="qemu-system-i386
            -machine pc
            -kernel ${test_dir}/images/bzImage
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk,format=raw
            -append \"root=/dev/sda rw console=ttyS0\""
    elif [[ "${arch_name}" == "x86-64-core-i7" ]]; then                 # x86-64-core-i7
        qemu_defconfig="qemu_x86_64_defconfig"
        sed -i "s/tty1/ttyS0/" ${buildroot_dir}/configs/${qemu_defconfig}
        qemu_system_command="qemu-system-x86_64
            -machine pc
            -kernel ${test_dir}/images/bzImage
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk,format=raw
            -append \"root=/dev/sda rw console=ttyS0\""
    elif [[ "${arch_name}" == "xtensa-lx60" ]]; then                    # xtensa-lx60
        qemu_defconfig="qemu_xtensa_lx60_defconfig"
        qemu_system_command="qemu-system-xtensa
            -machine lx60
            -kernel ${test_dir}/images/Image.elf
            -drive file=${test_dir}/images/rootfs.cpio,index=0,media=disk,format=raw
            -append \"root=/dev/sda rw console=ttyS0\""
    else
        qemu_defconfig=""
        qemu_system_command=""
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
    return 0
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
    return 0
}

function launch_build {
    echo "  Setup chroot and launch build"
    rm -rf ${build_dir}
    mkdir -p ${build_dir}
    debootstrap --variant=buildd squeeze ${build_dir} http://archive.debian.org/debian/ 2>&1 1>/dev/null
    mkdir ${build_dir}/proc
    mount --bind /proc ${build_dir}/proc
    cp ${chroot_script} ${build_dir}
    cp ${frag_dir}/${name}.config ${build_dir}
    cp chroot.conf /etc/schroot/schroot.conf
    cp /etc/resolv.conf ${build_dir}/etc/resolv.conf
    echo "  chrooting to ${build_dir}"
    chroot ${build_dir} ./build_chroot.sh ${name} ${buildroot_tree}
}

function make_br_fragment {
    echo "  Making BR fragment to use the toolchain"
    gcc_version=$(grep "^BR2_GCC_VERSION_" ${configfile} | sed 's/BR2_GCC_VERSION_\(.*\)_X=.*/\1/')
    linux_version=$(grep "^BR2_KERNEL_HEADERS_" ${configfile} | sed 's/BR2_KERNEL_HEADERS_\(.*\)=./\1/')
    locale=$(grep "^BR2_TOOLCHAIN_BUILDROOT_LOCALE" ${configfile} | sed 's/BR2_TOOLCHAIN_BUILDROOT_LOCALE=\(.\)/\1/')
    libc=$(grep "^BR2_TOOLCHAIN_BUILDROOT_LIBC=\".*\"" ${configfile} | sed 's/BR2_TOOLCHAIN_BUILDROOT_LIBC="\(.*\)"/\1/')

    echo "BR2_WGET=\"wget --passive-ftp -nd -t 3 --no-check-certificate\"" >> ${fragment_file} # XXX
    cat ${main_dir}/configs/arch/${arch_name}.config >> ${fragment_file}
    echo "BR2_TOOLCHAIN_EXTERNAL=y" >> ${fragment_file}
    echo "BR2_TOOLCHAIN_EXTERNAL_CUSTOM=y" >> ${fragment_file}
    echo "BR2_TOOLCHAIN_EXTERNAL_PREINSTALLED=y" >> ${fragment_file}
    echo "BR2_TOOLCHAIN_EXTERNAL_PATH=\"${toolchain_dir}\"" >> ${fragment_file}
    echo "BR2_TOOLCHAIN_EXTERNAL_GCC_${gcc_version}=y" >> ${fragment_file}
    echo "BR2_TOOLCHAIN_EXTERNAL_HEADERS_${linux_version}=y" >> ${fragment_file}
    if [ "${locale}" == "y" ]; then
        echo "BR2_TOOLCHAIN_EXTERNAL_LOCALE=y" >> ${fragment_file}
    fi
    if grep "BR2_TOOLCHAIN_HAS_SSP=y" ${configfile} > /dev/null 2>&1; then
        echo "BR2_TOOLCHAIN_EXTERNAL_HAS_SSP=y" >> ${fragment_file}
    else
        echo "# BR2_TOOLCHAIN_EXTERNAL_HAS_SSP is not set" >> ${fragment_file}
    fi
    if grep "BR2_PTHREAD_DEBUG is not set" ${configfile} > /dev/null 2>&1; then
        echo "BR2_TOOLCHAIN_EXTERNAL_HAS_THREADS_DEBUG=n" >> ${fragment_file}
    fi
    if ! grep "BR2_TOOLCHAIN_HAS_THREADS_NPTL=y" ${configfile} > /dev/null 2>&1; then
        echo "# BR2_TOOLCHAIN_EXTERNAL_HAS_THREADS_NPTL is not set" >> ${fragment_file}
    fi
    if [ "${libc}" == "glibc" ]; then
        echo "BR2_TOOLCHAIN_EXTERNAL_CUSTOM_GLIBC=y" >> ${fragment_file}
    elif [ "${libc}" == "musl" ]; then
        echo "BR2_TOOLCHAIN_EXTERNAL_CUSTOM_MUSL=y" >> ${fragment_file}
    fi

    echo "BEGIN FRAGMENT"
    cat ${fragment_file}
    echo "END FRAGMENT"
}

function package {
    echo "Packaging the toolchain as ${release_name}.tar.bz2"
    cd ${build_dir}
    sed -i "s/PREINSTALLED/DOWNLOAD/" ${fragment_file}
    sed -i "s/BR2_TOOLCHAIN_EXTERNAL_PATH=\".*\"/BR2_TOOLCHAIN_EXTERNAL_URL=\"${base_url}\/${release_name}.tar.bz2\"/" ${fragment_file}
    cp ${build_dir}/output/target/usr/bin/gdbserver ${toolchain_dir}/*/sysroot/usr/bin/
    cp ${build_dir}/output/legal-info/host-manifest.csv ${toolchain_dir}/manifest.csv
    cp ${fragment_file} ${toolchain_dir}
    tar cjf `basename ${release_name}`.tar.bz2 `basename ${toolchain_dir}`
    ssh ${ssh_server} "mkdir -p www/${target}/fragments"
    ssh ${ssh_server} "mkdir -p www/${target}/toolchains"
    ssh ${ssh_server} "mkdir -p www/${target}/manifests"
    ssh ${ssh_server} "mkdir -p www/${target}/build_test_logs"
    rsync ${testlogfile} ${ssh_server}:www/${target}/build_test_logs/
    rsync ${build_dir}/output/legal-info/host-manifest.csv ${ssh_server}:www/${target}/manifests/${release_name}.csv
    rsync "${release_name}.tar.bz2" ${ssh_server}:www/${target}/toolchains/
    rsync "${fragment_file}" ${ssh_server}:www/${target}/fragments/${release_name}.frag
    rsync -r ${build_dir}/output/legal-info/host-licenses/ ${ssh_server}:www/${target}/licenses/
    rsync -r ${build_dir}/output/legal-info/host-sources/ ${ssh_server}:www/${target}/sources/
}

function generate {
    echo "Generating ${name}..."

    logfile=${build_dir}/${name}-build.log
    testlogfile=${build_dir}/${name}-test.log

    if ! launch_build; then
        echo "Toolchain build failed, not going further"
        echo "Uploading build log"
        ssh ${ssh_server} "mkdir -p www/${target}/build_logs"
        rsync ${logfile} ${ssh_server}:www/${target}/build_logs/
        exit 1
    fi
    echo "Uploading build log"
    ssh ${ssh_server} "mkdir -p www/${target}/build_logs"
    rsync ${logfile} ${ssh_server}:www/${target}/build_logs/

    arch_name=$(echo "${name}" |sed "s/--/\t/" |cut -f 1)
    release_name=${name}-$(cat ${build_dir}/br_version)
    [[ "$version_number" != "" ]] && release_name="${release_name}-$version_number"
    toolchain_dir="${build_dir}/${name}"
    configfile=${toolchain_dir}/buildroot.config
    test_dir=${build_dir}/test-${name}
    overlaydir=${test_dir}/overlay

    make_br_fragment
    set_qemu_config

    return_value=0
    # Test the toolchain
    echo "Building a test system using ${name}..."
    if [ "${qemu_defconfig}" != "" ]; then
        if build_test; then
            if [ "${qemu_system_command}" != "" ]; then
                echo "Booting the test system in qemu..."
                if boot_test; then
                    echo "Booting passed"
                else
                    echo "Booting failed"
                    return_value=2
                fi
            else
                echo "No boot command set, can't try to boot"
            fi
        else
            echo "Test system failed to build"
            return_value=1
        fi
    else
        return_value=3
    fi

    if [ $return_value -eq 1 ]; then
        echo "THIS TOOLCHAIN MAY NOT WORK, OR THERE MAY BE A PROBLEM IN THE CONFIGURATION, PLEASE CHECK!"
        release_name="${release_name}-BF"
        return_value=0
    elif [ $return_value -eq 2 ]; then
        echo "THIS TOOLCHAIN MAY BUILD BROKEN BINARIES, OR THERE MAY BE A PROBLEM IN THE CONFIGURATION, PLEASE CHECK!"
        release_name="${release_name}-NB"
        return_value=0
    elif [ $return_value -eq 3 ]; then
        echo "THIS TOOLCHAIN CAN NOT BE TESTED!"
        release_name="${release_name}-CT"
        return_value=0
    else
        release_name="${release_name}-OK"
        return_value=0
    fi

    # Everything works, package the toolchain
    package

    return $return_value
}

if [ $# -ge 3 ]; then
    if ! generate ${name}; then
        echo "Something went wrong. Exiting with code 1"
        exit 1
    fi
else
    echo "Usage: $0 configname.config target buildroot-tree [version_number]"
    exit 1
fi


