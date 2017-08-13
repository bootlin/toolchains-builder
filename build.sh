#!/bin/bash

if [ $# -ne 4 ]; then
    cat - <<EOF
    Usage: $0 name target buildroot_treeish version_nb

name:
        This is the name of the toolchain you are compiling. The name should at
        least begin with "architecture-name--whatever". The double dash is mandatory
        for it is used a splitting token.

target:
        The folder in which to upload the toolchains. 'releases' is the
        production one, so be careful.

buildroot_treeish:
        A git tree-ish object in which to checkout Buildroot for any of its uses
        accross the process.

version_nb:
        A string appended to the toolchain name, useful not to override existing
        ones in the same target.
EOF
    exit 1
fi

echo "Building $1"
echo "Target: $2"
echo "Buildroot tree: $3"
echo "Version number: $4"

name="$1"
target="$2"
buildroot_tree="$3"
version_number="$4"

ssh_server="gitlabci@toolchains.free-electrons.com"
main_dir=$(pwd)
frag_dir=${main_dir}/frags
chroot_dir=${main_dir}/build
build_dir=${chroot_dir}/tmp
chroot_script="build_chroot.sh"
buildroot_dir=${main_dir}/buildroot
fragment_file=${build_dir}/br_fragment
base_url_sed="http:\/\/toolchains.free-electrons.com\/downloads\/${target}\/toolchains"
base_url="http://toolchains.free-electrons.com/downloads/${target}"
upload_root_folder="www/downloads"

if [ "$target" == "ci_debug" ]; then
    echo "ci_debug is set as target, you should see this line, but the build won't go further."
    echo "Exiting properly."
    exit 0;
fi

git clone https://github.com/free-electrons/buildroot-toolchains.git ${buildroot_dir}
if [ $? -ne 0 ] ; then
	exit 1
fi

cd ${buildroot_dir}
git checkout $buildroot_tree
if [ $? -ne 0 ] ; then
	exit 1
fi
echo "Buildroot version: " $(git describe)
cd ${main_dir}

function set_test_config {
    if [[ "${arch_name}" =~ ^"armv"."-".* ]]; then                      # armvX-*
        test_defconfig="qemu_arm_vexpress_defconfig"
        qemu_system_command="qemu-system-arm
            -machine vexpress-a9 -smp 1 -m 256
            -kernel ${test_dir}/images/zImage
            -dtb ${test_dir}/images/vexpress-v2p-ca9.dtb
            -drive file=${test_dir}/images/rootfs.ext2,if=sd,format=raw
            -append \"console=ttyAMA0,115200 root=/dev/mmcblk0\"
            -net nic,model=lan9118 -net user
            -nographic"
    elif [[ "${arch_name}" == "armv7m" ]]; then                        # armv7m
        test_defconfig="stm32f469_disco_defconfig"
        qemu_system_command=""
    elif [[ "${arch_name}" == "aarch64" ]]; then                        # aarch64
        test_defconfig="qemu_aarch64_virt_defconfig"
        # Qemu 2.8 has been tested and works, 2.5 does not.
        qemu_system_command="qemu-system-aarch64
            -machine virt -cpu cortex-a57 -smp 1
            -kernel ${test_dir}/images/Image
            -append \"console=ttyAMA0\"
            -netdev user,id=eth0 -device virtio-net-device,netdev=eth0
            -nographic"
    # elif [[ "${arch_name}" == "aarch64be" ]]; then                      # aarch64be (not supported by qemu yet)
    #     test_defconfig="qemu_aarch64_virt_defconfig"
    #     # Qemu 2.8 has been tested and works, 2.5 does not.
    #     qemu_system_command="qemu-system-aarch64
    #         -machine virt -cpu cortex-a53 -machine type=virt
    #         -kernel ${test_dir}/images/Image
    #         -append \"console=ttyAMA0\""
    elif [[ "${arch_name}" == "bfin" ]]; then                           # bfin
        test_defconfig="gdb_bfin_bf512_defconfig"
        qemu_system_command=""
    elif [[ "${arch_name}" == "microblazebe" ]]; then                   # microblazebe
        test_defconfig="qemu_microblazebe_mmu_defconfig"
        qemu_system_command="qemu-system-microblaze
            -machine petalogix-s3adsp1800
            -kernel ${test_dir}/images/linux.bin
            -drive file=${test_dir}/images/rootfs.cpio,index=0,media=disk,format=raw
            -append \"root=/dev/sda rw\"
            -nographic"
    elif [[ "${arch_name}" == "microblazeel" ]]; then                   # microblazeel
        test_defconfig="qemu_microblazeel_mmu_defconfig"
        qemu_system_command="qemu-system-microblazeel
            -machine petalogix-s3adsp1800
            -kernel ${test_dir}/images/linux.bin
            -drive file=${test_dir}/images/rootfs.cpio,index=0,media=disk,format=raw
            -append \"root=/dev/sda rw\"
            -nographic"
    elif [[ "${arch_name}" == "mips32" ]]; then                         # mips32
        test_defconfig="qemu_mips32r2_malta_defconfig"
        qemu_system_command="qemu-system-mips
            -machine malta
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,format=raw
            -append \"root=/dev/hda rw\"
            -net nic,model=pcnet -net user
            -nographic"
    elif [[ "${arch_name}" == "mips32el" ]]; then                       # mips32el
        test_defconfig="qemu_mips32r2el_malta_defconfig"
        qemu_system_command="qemu-system-mipsel
            -machine malta
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,format=raw
            -append \"root=/dev/hda rw\"
            -nographic"
    elif [[ "${arch_name}" == "mips32r5el" ]]; then                     # mips32r5el
        test_defconfig="qemu_mips32r2el_malta_defconfig"
        qemu_system_command="qemu-system-mipsel
            -machine malta
            -cpu P5600
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,format=raw
            -append \"root=/dev/hda rw\"
            -nographic"
    elif [[ "${arch_name}" == "mips32r6el" ]]; then                     # mips32r6el
        test_defconfig="qemu_mips32r6el_malta_defconfig"
        qemu_system_command="qemu-system-mipsel
            -machine malta
            -cpu mips32r6-generic
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,format=raw
            -append \"root=/dev/hda rw\"
            -nographic"
    elif [[ "${arch_name}" == "mips64-n32" ]]; then                     # mips64-32
        test_defconfig="qemu_mips64_malta_defconfig"
        qemu_system_command="qemu-system-mips64
            -machine malta
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,format=raw
            -append \"root=/dev/hda rw\"
            -nographic"
    elif [[ "${arch_name}" == "mips64el-n32" ]]; then                   # mips64el-n32
        test_defconfig="qemu_mips64el_malta_defconfig"
        qemu_system_command="qemu-system-mips64el
            -machine malta
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,format=raw
            -append \"root=/dev/hda rw\"
            -nographic"
    elif [[ "${arch_name}" == "mips64r6el-n32" ]]; then                 # mips64r6el-n32
        test_defconfig="qemu_mips64r6el_malta_defconfig"
        qemu_system_command="qemu-system-mips64el
            -machine malta
            -cpu I6400
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,format=raw
            -append \"root=/dev/hda rw\"
            -nographic"
    # elif [[ "${arch_name}" == "m68k-68xxxx" ]]; then                    # m68k-68xxxx (support out of tree)
    #    test_defconfig="qemu_m68k_q800_defconfig"
    #    qemu_system_command="qemu-system-m68k
    #        -machine an5206
    #        -kernel ${test_dir}/images/vmlinux
    #        -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk,format=raw
    #        -append \"root=/dev/hda rw\""
    elif [[ "${arch_name}" == "m68k-coldfire" ]]; then                  # m68k-coldfire
        test_defconfig="qemu_m68k_mcf5208_defconfig"
        qemu_system_command="qemu-system-m68k
            -machine mcf5208evb
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk,format=raw
            -append \"root=/dev/hda rw\"
            -nographic"
    # elif [[ "${arch_name}" == "nios2" ]]; then                          # nios2 (no support in 2.8, coming in 2.9)
    #     test_defconfig="qemu_nios2_10m50_defconfig"
    #     qemu_system_command="qemu-system-nios2
    #         -kernel ${test_dir}/images/vmlinux"
    elif [[ "${arch_name}" == "powerpc64-power8" ]]; then               # powerpc64-power8
        test_defconfig="qemu_ppc64_pseries_defconfig"
        qemu_system_command="qemu-system-ppc64
            -machine pseries
            -cpu POWER7
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,index=0,if=scsi,format=raw
            -append \"console=hvc0 root=/dev/sda rw\"
            -display curses
            -nographic"
    elif [[ "${arch_name}" == "sh-sh4" ]]; then                         # sh4
        test_defconfig="qemu_sh4_r2d_defconfig"
        qemu_system_command="qemu-system-sh4
            -machine r2d
            -kernel ${test_dir}/images/zImage
            -drive file=${test_dir}/images/rootfs.ext2,index=0,if=ide,format=raw
            -append \"root=/dev/sda rw console=ttySC1,115200 noiotrap\"
            -net nic,model=rtl8139 -net user
            -serial null
            -serial stdio
            -display none"
    elif [[ "${arch_name}" == "sparc64" ]]; then                        # sparc64
        test_defconfig="qemu_sparc64_sun4u_defconfig"
        qemu_system_command="qemu-system-sparc64
            -machine sun4u
            -kernel ${test_dir}/images/vmlinux
            -drive file=${test_dir}/images/rootfs.ext2,format=raw
            -append \"root=/dev/sda console=ttyS0,115200\"
            -net nic,model=e1000 -net user
            -nographic"
    elif [[ "${arch_name}" == "sparcv8" ]]; then                        # sparcv8
        test_defconfig="qemu_sparc_ss10_defconfig"
        qemu_system_command="qemu-system-sparc
            -machine SS-10
            -kernel ${test_dir}/images/zImage
            -drive file=${test_dir}/images/rootfs.ext2,format=raw
            -append \"root=/dev/sda console=ttyS0,115200\"
            -net nic,model=lance -net user
            -nographic"
    elif [[ "${arch_name}" == "x86-core2" ]]; then                      # x86-core2
        test_defconfig="qemu_x86_defconfig"
        sed -i "s/tty1/ttyS0/" ${buildroot_dir}/configs/${test_defconfig}
        qemu_system_command="qemu-system-i386
            -machine pc
            -kernel ${test_dir}/images/bzImage
            -drive file=${test_dir}/images/rootfs.ext2,format=raw
            -append \"root=/dev/sda rw console=ttyS0\"
            -net nic,model=virtio -net user
            -nographic"
    elif [[ "${arch_name}" == "x86-i686" ]]; then                       # x86-i686
        test_defconfig="qemu_x86_defconfig"
        sed -i "s/tty1/ttyS0/" ${buildroot_dir}/configs/${test_defconfig}
        qemu_system_command="qemu-system-i386
            -machine pc
            -kernel ${test_dir}/images/bzImage
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk,format=raw
            -append \"root=/dev/sda rw console=ttyS0\"
            -net nic,model=virtio -net user
            -nographic"
    elif [[ "${arch_name}" == "x86-64-core-i7" ]]; then                 # x86-64-core-i7
        test_defconfig="qemu_x86_64_defconfig"
        sed -i "s/tty1/ttyS0/" ${buildroot_dir}/configs/${test_defconfig}
        qemu_system_command="qemu-system-x86_64
            -machine pc
            -kernel ${test_dir}/images/bzImage
            -drive file=${test_dir}/images/rootfs.ext2,index=0,media=disk,format=raw
            -append \"root=/dev/sda rw console=ttyS0\"
            -net nic,model=virtio -net user
            -nographic"
    elif [[ "${arch_name}" == "xtensa-lx60" ]]; then                    # xtensa-lx60
        test_defconfig="qemu_xtensa_lx60_defconfig"
        qemu_system_command="qemu-system-xtensa
            -machine lx60
            -cpu dc233c
            -kernel ${test_dir}/images/Image.elf
            -monitor null
            -nographic"
    else
        test_defconfig=""
        qemu_system_command=""
    fi
}

function boot_test {
    echo "  booting test system ... "
    export QEMU_COMMAND="$(echo "${qemu_system_command}"|tr -d '\n')"
    echo "  boot command: ${qemu_system_command}"
    if ! expect expect.sh; then
        echo "  booting test system ... FAILED"
        return 1
    fi
    echo "  booting test system ... SUCCESS"
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
    cp ${buildroot_dir}/configs/${test_defconfig} ${testconfigfile}
    echo "BR2_ROOTFS_OVERLAY=\"${test_dir}/overlay\"" >> ${testconfigfile}
    cat ${fragment_file} >> ${testconfigfile}

    # Starting the system build
    echo "  starting test system build at $(date)"
    echo "  making old config"
    make -C ${buildroot_dir} O=${test_dir} olddefconfig > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        echo "olddefconfig failed"
        return 1
    fi
    make -C ${buildroot_dir} O=${test_dir} savedefconfig > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        echo "savedefconfig failed"
        return 1
    fi
    echo "=================== BEGIN TEST SYSTEM DEFCONFIG ======================"
    cat ${test_dir}/defconfig
    echo "=================== END TEST SYSTEM DEFCONFIG ======================"

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

    if grep "bleeding-edge" <<<"${name}"; then
        debootstrap --variant=buildd jessie ${chroot_dir} http://ftp.us.debian.org/debian/ 2>&1 1>/dev/null
    else
        debootstrap --variant=buildd squeeze ${chroot_dir} http://archive.debian.org/debian/ 2>&1 1>/dev/null
    fi

    mkdir ${chroot_dir}/proc
    mount --bind /proc ${chroot_dir}/proc
    cp ${chroot_script} ${build_dir}
    cp ${frag_dir}/${name}.config ${build_dir}
    cp chroot.conf /etc/schroot/schroot.conf
    cp /etc/resolv.conf ${chroot_dir}/etc/resolv.conf
    echo "  chrooting to ${chroot_dir}"
    # This line MUST be the last one of this function to forward the errors
    chroot ${chroot_dir} /tmp/build_chroot.sh ${name} ${buildroot_tree}
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
    else
        echo "# BR2_TOOLCHAIN_EXTERNAL_LOCALE is not set" >> ${fragment_file}
    fi
    if grep "BR2_TOOLCHAIN_HAS_CXX=y" ${configfile} > /dev/null 2>&1; then
        echo "BR2_TOOLCHAIN_EXTERNAL_HAS_CXX=y" >> ${fragment_file}
    else
        echo "# BR2_TOOLCHAIN_EXTERNAL_CXX is not set" >> ${fragment_file}
    fi
    if grep "BR2_TOOLCHAIN_HAS_SSP=y" ${configfile} > /dev/null 2>&1; then
        echo "BR2_TOOLCHAIN_EXTERNAL_HAS_SSP=y" >> ${fragment_file}
    else
        echo "# BR2_TOOLCHAIN_EXTERNAL_HAS_SSP is not set" >> ${fragment_file}
    fi
    if grep "BR2_PTHREAD_DEBUG is not set" ${configfile} > /dev/null 2>&1; then
        echo "BR2_TOOLCHAIN_EXTERNAL_HAS_THREADS_DEBUG=n" >> ${fragment_file}
    else
        echo "BR2_TOOLCHAIN_EXTERNAL_HAS_THREADS_DEBUG=y" >> ${fragment_file}
    fi
    if ! grep "BR2_TOOLCHAIN_HAS_THREADS_NPTL=y" ${configfile} > /dev/null 2>&1; then
        echo "# BR2_TOOLCHAIN_EXTERNAL_HAS_THREADS_NPTL is not set" >> ${fragment_file}
    else
        echo "BR2_TOOLCHAIN_EXTERNAL_HAS_THREADS_NPTL=y" >> ${fragment_file}
    fi
    if [ "${libc}" == "glibc" ]; then
        echo "BR2_TOOLCHAIN_EXTERNAL_CUSTOM_GLIBC=y" >> ${fragment_file}
    elif [ "${libc}" == "musl" ]; then
        echo "BR2_TOOLCHAIN_EXTERNAL_CUSTOM_MUSL=y" >> ${fragment_file}
    else
        echo "BR2_TOOLCHAIN_EXTERNAL_CUSTOM_UCLIBC=y" >> ${fragment_file}
    fi

    echo "BEGIN FRAGMENT"
    cat ${fragment_file}
    echo "END FRAGMENT"
}

function package {
    readme_file=${toolchain_dir}/README.txt
    summary_file=${toolchain_dir}/summary.csv
    echo "Preparing the packaging of ${release_name}"

    # Update fragment file for release
    sed -i "s/PREINSTALLED/DOWNLOAD/" ${fragment_file}
    sed -i "s/BR2_TOOLCHAIN_EXTERNAL_PATH=\".*\"/BR2_TOOLCHAIN_EXTERNAL_URL=\"${base_url_sed}\/${arch_name}\/tarballs\/${release_name}.tar.bz2\"/" ${fragment_file}
    sed -i "/BR2_WGET/d" ${fragment_file}
    cp ${fragment_file} ${toolchain_dir}

    # Summary
    tail -n +1 ${build_dir}/output/legal-info/manifest.csv >> ${summary_file}
    tail -n +2 ${build_dir}/output/legal-info/host-manifest.csv >> ${summary_file}

    # Make the README
    echo -e "${release_name}\n\n" >> ${readme_file}
    cat ${main_dir}/readme_base.txt >> ${readme_file}
    cat ${build_dir}/output/legal-info/host-manifest.csv|sed 's/","/\t/g'|sed 's/"//g'|cut -f 1,2,3|column -t -s $'\t' >> ${readme_file}
    tail -n +2 ${build_dir}/output/legal-info/manifest.csv|sed 's/","/\t/g'|sed 's/"//g'|cut -f 1,2,3|column -t -s $'\t' >> ${readme_file}
    cat - >> ${readme_file} <<EOF

For those who would like to reproduce the toolchain, you can just follow these steps:

    git clone https://github.com/free-electrons/buildroot-toolchains.git buildroot
    cd buildroot
    git checkout ${buildroot_tree}

    curl ${base_url}/toolchains/${arch_name}/build_fragments/${release_name}.defconfig > .config
    make olddefconfig
    make
EOF
    if [ $return_value -eq 1 ]; then
        echo "THIS TOOLCHAIN MAY NOT WORK, OR THERE MAY BE A PROBLEM IN THE CONFIGURATION, PLEASE CHECK!"
        cat - >> ${readme_file} <<EOF

This toolchain has been built, but the test system failed to build with it.
This doesn't mean that this toolchain doesn't work, just that it hasn't been
successfully tested.
FLAG: SYSTEM-BUILD-FAILED
EOF
    elif [ $return_value -eq 2 ]; then
        echo "THIS TOOLCHAIN MAY BUILD BROKEN BINARIES, OR THERE MAY BE A PROBLEM IN THE CONFIGURATION, PLEASE CHECK!"
        cat - >> ${readme_file} <<EOF

This toolchain has been built, but the test system built with it failed to boot.
This doesn't mean that this toolchain doesn't work, just that it hasn't been
successfully tested.
FLAG: NO-BOOT
EOF
    elif [ $return_value -eq 3 ]; then
        echo "THIS TOOLCHAIN CAN NOT BE TESTED!"
        cat - >> ${readme_file} <<EOF

This toolchain has been built, but the infrastructure does not contains enough
informations about testing it.
This doesn't mean that this toolchain doesn't work, just that it hasn't been
fully tested.
FLAG: CAN-NOT-TEST
EOF
        return_value=0
    else
        cat - >> ${readme_file} <<EOF

This toolchain has been built, and the test system built with it has
successfully booted.
This doesn't mean that this toolchain will work in every cases, but it is at
least capable of building a Linux kernel with a basic rootfs that boots.
FLAG: TEST-OK
EOF
        return_value=0
    fi

    # Make the tarball
    echo "Packaging the toolchain as ${release_name}.tar.bz2"
    cd ${build_dir}
    tar cjf `basename ${release_name}`.tar.bz2 `basename ${toolchain_dir}`
    sha256sum ${release_name}.tar.bz2 > ${release_name}.sha256


    # Upload everything
    ssh ${ssh_server} "mkdir -p ${upload_folder}/fragments"
    ssh ${ssh_server} "mkdir -p ${upload_folder}/tarballs"
    ssh ${ssh_server} "mkdir -p ${upload_folder}/readmes"
    ssh ${ssh_server} "mkdir -p ${upload_folder}/summaries"
    ssh ${ssh_server} "mkdir -p ${upload_folder}/build_test_logs"
    ssh ${ssh_server} "mkdir -p ${upload_folder}/boot_test_logs"
    ssh ${ssh_server} "mkdir -p ${upload_folder}/build_fragments"
    ssh ${ssh_server} "mkdir -p ${upload_folder}/test_system_defconfigs"
    ssh ${ssh_server} "mkdir -p ${upload_folder}/available_toolchains"
    rsync ${testlogfile} ${ssh_server}:${upload_folder}/build_test_logs/                                            # build test log file
    rsync ${bootlogfile} ${ssh_server}:${upload_folder}/boot_test_logs/${release_name}.log                          # boot test log file
    rsync ${readme_file} ${ssh_server}:${upload_folder}/readmes/${release_name}.txt                                 # README
    rsync ${summary_file} ${ssh_server}:${upload_folder}/summaries/${release_name}.csv                              # summary
    rsync "${release_name}.tar.bz2" ${ssh_server}:${upload_folder}/tarballs/                                        # toolchain tarball
    rsync "${release_name}.sha256" ${ssh_server}:${upload_folder}/tarballs/                                         # toolchain checksum
    rsync "${fragment_file}" ${ssh_server}:${upload_folder}/fragments/${release_name}.frag                          # BR fragment
    rsync ${test_dir}/defconfig ${ssh_server}:${upload_folder}/test_system_defconfigs/${release_name}.defconfig     # test system defconfig
    rsync -r ${build_dir}/output/defconfig ${ssh_server}:${upload_folder}/build_fragments/${release_name}.defconfig # build fragment
    rsync -r ${build_dir}/output/legal-info/host-licenses/ ${ssh_server}:${upload_root_folder}/${target}/licenses/  # licenses
    rsync -r ${build_dir}/output/legal-info/host-sources/ ${ssh_server}:${upload_root_folder}/${target}/sources/    # sources
    ssh ${ssh_server} "touch ${upload_folder}/available_toolchains/${release_name}"                                 # toolchain name for webpage listing
    ssh ${ssh_server} "touch ${upload_root_folder}/NEED_REFRESH"
}

function generate {
    echo "Generating ${name}..."

    logfile=${build_dir}/${name}-build.log
    testlogfile=${build_dir}/${name}-test.log
    bootlogfile=/tmp/expect_session.log
    arch_name=$(echo "${name}" |sed "s/--/\t/" |cut -f 1)
    upload_folder=${upload_root_folder}/${target}/toolchains/${arch_name}

    if ! launch_build; then
        echo "Toolchain build failed, not going further"
        echo "Uploading build log"
        ssh ${ssh_server} "mkdir -p ${upload_folder}/build_logs"
        rsync ${logfile} ${ssh_server}:${upload_folder}/build_logs/
        exit 1
    fi
    echo "Uploading build log"
    ssh ${ssh_server} "mkdir -p ${upload_folder}/build_logs"
    rsync ${logfile} ${ssh_server}:${upload_folder}/build_logs/

    release_name=${name}-$(cat ${build_dir}/br_version)
    [[ "$version_number" != "" ]] && release_name="${release_name}-$version_number"
    toolchain_dir="${build_dir}/${name}"
    configfile=${toolchain_dir}/buildroot.config
    test_dir=${build_dir}/test-${name}
    overlaydir=${test_dir}/overlay

    make_br_fragment
    set_test_config

    return_value=0
    # Test the toolchain
    echo "Building a test system using ${name}..."
    if [ "${test_defconfig}" != "" ]; then
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
                return_value=3
            fi
        else
            echo "Test system failed to build"
            return_value=1
        fi
    else
        return_value=3
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


