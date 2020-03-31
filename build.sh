#!/bin/bash

if [ $# -ne 4 ]; then
    cat - <<EOF
    Usage: $0 name target buildroot_treeish

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

version:
	Version identifier.
EOF
    exit 1
fi

echo "Building $1"
echo "Target: $2"
echo "Buildroot tree: $3"
echo "Version identifier: $4"

name="$1"
target="$2"
buildroot_tree="$3"
version="$4"

ssh_server="gitlabci@toolchains.bootlin.com"
main_dir=$(pwd)
frag_dir=${main_dir}/frags
chroot_dir=${main_dir}/build
build_dir=${chroot_dir}/opt
chroot_script="build_chroot.sh"
buildroot_dir=${main_dir}/buildroot
fragment_file=${build_dir}/br_fragment
base_url_sed="http:\/\/toolchains.bootlin.com\/downloads\/${target}\/toolchains"
base_url="http://toolchains.bootlin.com/downloads/${target}"
upload_root_folder="www/downloads"

if [ "$target" == "ci_debug" ]; then
    echo "ci_debug is set as target, you should see this line, but the build won't go further."
    echo "Exiting properly."
    exit 0;
fi

git clone https://github.com/buildroot/buildroot.git ${buildroot_dir} || exit 1
cd ${buildroot_dir}
git remote add buildroot-toolchains https://github.com/bootlin/buildroot-toolchains.git || exit 1
git fetch buildroot-toolchains || exit 1
git fetch --tags buildroot-toolchains || exit 1
git checkout $buildroot_tree || exit 1
br_version=$(git describe --tags)
echo "Buildroot version: " ${br_version}
cd ${main_dir}

function set_test_config {
    case "${arch_name}" in
    armv5-* | armv6-* | armv7-*)
        test_defconfig="qemu_arm_vexpress_defconfig"
        test_board_dir="arm-vexpress"
	;;
    armv7m)
        test_defconfig="stm32f469_disco_defconfig"
	;;
    aarch64)
        test_defconfig="qemu_aarch64_virt_defconfig"
        test_board_dir="aarch64-virt"
	;;
    bfin)
        test_defconfig="gdb_bfin_bf512_defconfig"
	;;
    microblazebe)
        test_defconfig="qemu_microblazebe_mmu_defconfig"
        test_board_dir="microblazebe-mmu"
	;;
    microblazeel)
        test_defconfig="qemu_microblazeel_mmu_defconfig"
        test_board_dir="microblazeel-mmu"
	;;
    mips32)
        test_defconfig="qemu_mips32r2_malta_defconfig"
        test_board_dir="mips32r2-malta"
	;;
    mips32el)
        test_defconfig="qemu_mips32r2el_malta_defconfig"
        test_board_dir="mips32r2el-malta"
	;;
    mips32r5el)
        test_defconfig="qemu_mips32r2el_malta_defconfig"
        test_board_dir="mips32r2el-malta"
        test_qemu_args="-cpu P5600"
	;;
    mips32r6el)
        test_defconfig="qemu_mips32r6el_malta_defconfig"
        test_board_dir="mips32r6el-malta"
	;;
    mips64-n32)
        test_defconfig="qemu_mips64_malta_defconfig"
        test_board_dir="mips64-malta"
	;;
    mips64el-n32)
        test_defconfig="qemu_mips64el_malta_defconfig"
        test_board_dir="mips64el-malta"
	;;
    mips64r6el-n32)
        test_defconfig="qemu_mips64r6el_malta_defconfig"
        test_board_dir="mips64r6el-malta"
	;;
    m68k-68xxx)
        test_defconfig="qemu_m68k_q800_defconfig"
	# cannot boot under qemu, support out of tree
	;;
    m68k-coldfire)
	test_defconfig="qemu_m68k_mcf5208_defconfig"
	# cannot boot under qemu, 2.9 needed
	;;
    nios2)
        test_defconfig="qemu_nios2_10m50_defconfig"
	# cannot boot under qemu, 2.9 needed
	;;
    powerpc64-power8)
        test_defconfig="qemu_ppc64_pseries_defconfig"
        test_board_dir="ppc64-pseries"
        test_qemu_args="-cpu POWER8"
	;;
    powerpc64le-power8)
        test_defconfig="qemu_ppc64le_pseries_defconfig"
        test_board_dir="ppc64le-pseries"
	;;
    sh-sh4)
        test_defconfig="qemu_sh4_r2d_defconfig"
        test_board_dir="sh4-r2d"
	;;
    sparc64)
        test_defconfig="qemu_sparc64_sun4u_defconfig"
        test_board_dir="sparc64-sun4u"
	;;
    sparcv8)
        test_defconfig="qemu_sparc_ss10_defconfig"
        # Qemu >= 2.10 doesn't boot this defconfig anymore
        # test_board_dir="sparc-ss10"
	;;
    x86-core2)
        test_defconfig="qemu_x86_defconfig"
        sed -i "s/tty1/ttyS0/" ${buildroot_dir}/configs/${test_defconfig}
        test_board_dir="x86"
        test_qemu_append="rw console=ttyS0"
	;;
    x86-i686)
        test_defconfig="qemu_x86_defconfig"
        sed -i "s/tty1/ttyS0/" ${buildroot_dir}/configs/${test_defconfig}
        test_board_dir="x86"
        test_qemu_append="rw console=ttyS0"
	;;
    x86-64-core-i7)
        test_defconfig="qemu_x86_64_defconfig"
        sed -i "s/tty1/ttyS0/" ${buildroot_dir}/configs/${test_defconfig}
        test_board_dir="x86_64"
        test_qemu_append="rw console=ttyS0"
	;;
    xtensa-lx60)
        test_defconfig="qemu_xtensa_lx60_defconfig"
        test_board_dir="xtensa-lx60"
        test_qemu_args="-monitor null"
	;;
    esac

    if [[ "${test_board_dir}" == "" ]]; then
        test_qemu_cmd=""
        return
    fi

    # Extract Qemu command from readme.txt
    test_qemu_cmd=$(grep qemu-system ${buildroot_dir}/board/qemu/${test_board_dir}/readme.txt)

    # Replace the output/ folder by the correct path
    test_qemu_cmd=$(echo ${test_qemu_cmd} | sed "s%output/%${test_dir}/%g")

    # Tweak the -append option
    test_qemu_cmd=$(echo ${test_qemu_cmd} | \
                        sed "s%-append \"\(.*\)\"%-append \"\1 ${test_qemu_append}\"%")

    # Remove -serial stdio if present
    test_qemu_cmd=$(echo ${test_qemu_cmd} | sed "s%-serial stdio%%")

    # Append with additional arguments
    test_qemu_cmd="${test_qemu_cmd} ${test_qemu_args}"

    # Special case for SH4 -display none
    if [[ "${arch_name}" == "sh-sh4" ]]; then
        test_qemu_cmd="${test_qemu_cmd} -serial stdio -display none"
    else
        test_qemu_cmd="${test_qemu_cmd} -nographic"
    fi
}

function boot_test {
    echo "  booting test system ... "
    export QEMU_COMMAND="$(echo "${test_qemu_cmd}"|tr -d '\n')"
    echo "  boot command: ${test_qemu_cmd}"
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
    # FORCE_UNSAFE_CONFIGURE=1 to allow to build host-tar as root
    make FORCE_UNSAFE_CONFIGURE=1 -C ${buildroot_dir} O=${test_dir} > ${testlogfile} 2>&1
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
    rm -rf ${build_dir} || return 1
    mkdir -p ${build_dir} || return 1
    mkdir -p ${build_dir}/buildroot || return 1

    debootstrap --variant=buildd jessie ${chroot_dir} http://ftp.us.debian.org/debian/ || return 1

    mkdir -p ${chroot_dir}/proc || return 1
    mount --bind /proc ${chroot_dir}/proc || return 1
    mount --bind ${buildroot_dir} ${build_dir}/buildroot || return 1
    cp ${chroot_script} ${build_dir} || return 1
    cp ${frag_dir}/${name}.config ${build_dir} || return 1
    cp chroot.conf /etc/schroot/schroot.conf || return 1
    cp /etc/resolv.conf ${chroot_dir}/etc/resolv.conf || return 1
    echo "  chrooting to ${chroot_dir}"

    chroot ${chroot_dir} /opt/build_chroot.sh ${name} ${version}
    return $?
}

function make_br_fragment {
    echo "  Making BR fragment to use the toolchain"
    gcc_version=$(grep "^BR2_GCC_VERSION_" ${configfile} | sed 's/BR2_GCC_VERSION_\(.*\)_X=.*/\1/')
    linux_version=$(grep "^BR2_KERNEL_HEADERS_" ${configfile} | sed 's/BR2_KERNEL_HEADERS_\(.*\)=./\1/')
    locale=$(grep "^BR2_TOOLCHAIN_BUILDROOT_LOCALE" ${configfile} | sed 's/BR2_TOOLCHAIN_BUILDROOT_LOCALE=\(.\)/\1/')
    libc=$(grep "^BR2_TOOLCHAIN_BUILDROOT_LIBC=\".*\"" ${configfile} | sed 's/BR2_TOOLCHAIN_BUILDROOT_LIBC="\(.*\)"/\1/')

    echo "BR2_WGET=\"wget --passive-ftp -nd -t 3 --no-check-certificate\"" >> ${fragment_file} # XXX
    if [[ "${version_name}" =~ "special-" ]]; then
	cat ${main_dir}/configs/special/${name}.config | grep -v "^BR2_TOOLCHAIN_BUILDROOT" | grep -v "^BR2_KERNEL_HEADERS" >> ${fragment_file}
    else
	cat ${main_dir}/configs/arch/${arch_name}.config >> ${fragment_file}
    fi
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
    if grep "BR2_TOOLCHAIN_BUILDROOT_CXX=y" ${configfile} > /dev/null 2>&1; then
        echo "BR2_TOOLCHAIN_EXTERNAL_CXX=y" >> ${fragment_file}
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
    if ! grep "BR2_TOOLCHAIN_HAS_THREADS=y" ${configfile} > /dev/null 2>&1; then
	echo "# BR2_TOOLCHAIN_EXTERNAL_HAS_THREADS is not set" >> ${fragment_file}
    else
	echo "BR2_TOOLCHAIN_EXTERNAL_HAS_THREADS=y" >> ${fragment_file}
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

    git clone https://github.com/bootlin/buildroot-toolchains.git buildroot
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

    # Create directories on the server, where the different artefacts
    # will be uploaded.
    for d in fragments tarballs readmes summaries \
                       build_test_logs boot_test_logs \
                       build_fragments test_system_defconfigs \
                       available_toolchains test-system; do
        ssh ${ssh_server} "mkdir -p ${upload_folder}/${d}"
    done

    # Upload log of qemu defconfig build, as well as the qemu
    # defconfig itself
    if [ "${test_defconfig}" != "" ]; then
        rsync ${testlogfile} ${ssh_server}:${upload_folder}/build_test_logs/
        rsync ${test_dir}/defconfig ${ssh_server}:${upload_folder}/test_system_defconfigs/${release_name}.defconfig
    fi
    # Upload log of qemu boot
    if [ "${test_qemu_cmd}" != "" ]; then
        rsync ${bootlogfile} ${ssh_server}:${upload_folder}/boot_test_logs/${release_name}.log
    fi

    for i in ${test_dir}/images/* ; do
	rsync $i ${ssh_server}:${upload_folder}/test-system/${release_name}-$(basename $i)
    done

    rsync ${readme_file} ${ssh_server}:${upload_folder}/readmes/${release_name}.txt                                 # README
    rsync ${summary_file} ${ssh_server}:${upload_folder}/summaries/${release_name}.csv                              # summary
    rsync "${release_name}.tar.bz2" ${ssh_server}:${upload_folder}/tarballs/                                        # toolchain tarball
    rsync "${release_name}.sha256" ${ssh_server}:${upload_folder}/tarballs/                                         # toolchain checksum
    rsync "${fragment_file}" ${ssh_server}:${upload_folder}/fragments/${release_name}.frag                          # BR fragment
    rsync -r ${build_dir}/output/defconfig ${ssh_server}:${upload_folder}/build_fragments/${release_name}.defconfig # build fragment
    rsync -r ${build_dir}/output/legal-info/host-licenses/ ${ssh_server}:${upload_root_folder}/${target}/licenses/  # licenses
    rsync -r ${build_dir}/output/legal-info/host-sources/ ${ssh_server}:${upload_root_folder}/${target}/sources/    # sources
    rsync -r ${build_dir}/output/legal-info/licenses/ ${ssh_server}:${upload_root_folder}/${target}/licenses/  	    # licenses
    rsync -r ${build_dir}/output/legal-info/sources/ ${ssh_server}:${upload_root_folder}/${target}/sources/         # sources
    ssh ${ssh_server} "touch ${upload_folder}/available_toolchains/${release_name}"                                 # toolchain name for webpage listing
    ssh ${ssh_server} "touch ${upload_root_folder}/NEED_REFRESH"
}

function generate {
    echo "Generating ${name}..."

    logfile=${build_dir}/${name}-build.log
    bootlogfile=/tmp/expect_session.log
    arch_name=$(echo "${name}" |sed "s/--/\t/" |cut -f 1)
    version_name=$(echo "${name}" |sed "s/--/\t/" |cut -f 3)
    upload_folder=${upload_root_folder}/${target}/toolchains/${arch_name}

    launch_build
    build_status=$?

    release_name=${name}-${version}

    echo "Uploading build log"
    ssh ${ssh_server} "mkdir -p ${upload_folder}/build_logs"
    scp ${logfile} ${ssh_server}:${upload_folder}/build_logs/${release_name}-build.log

    if test $build_status -ne 0 ; then
        echo "Toolchain build failed, not going further"
        exit 1
    fi

    toolchain_dir="${build_dir}/${release_name}"
    configfile=${toolchain_dir}/buildroot.config
    test_dir=${build_dir}/test-${name}
    overlaydir=${test_dir}/overlay

    make_br_fragment
    set_test_config

    return_value=0
    # Test the toolchain
    echo "Building a test system using ${name}..."
    if [ "${test_defconfig}" != "" ]; then
        testlogfile=${build_dir}/${release_name}-test.log

        if build_test; then
            if [ "${test_qemu_cmd}" != "" ]; then
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

if [ $# -ge 2 ]; then
    if ! generate ${name}; then
        echo "Something went wrong. Exiting with code 1"
        exit 1
    fi
else
    echo "Usage: $0 configname.config target buildroot-tree"
    exit 1
fi


