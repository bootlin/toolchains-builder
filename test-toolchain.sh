#!/bin/bash
# -*- mode: Shell-script; sh-basic-offset: 4; -*-

set -e
set -o pipefail

base_dir=$(dirname "$0")

source ${base_dir}/common.sh

name="$1"
target="$2"
buildroot_tree="$3"
version="$4"

main_dir=$(pwd)
frag_dir=${main_dir}/frags
build_dir=${main_dir}/build
buildroot_dir=${main_dir}/buildroot
test_dir=${main_dir}/test
test_build_dir=${test_dir}/output
release_name=${name}-${version}
toolchain_dir=${test_dir}/${release_name}
base_url="http://toolchains.bootlin.com/downloads/${target}"

arch_name=$(echo "${name}" |sed "s/--/\t/" |cut -f 1)
version_name=$(echo "${name}" |sed "s/--/\t/" |cut -f 3)


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
	test_board_dir="m68k-q800"
	;;
    m68k-coldfire)
	test_defconfig="qemu_m68k_mcf5208_defconfig"
	# Needs qemu >= 2.9
	test_board_dir="m68k-mcf5208"
	;;
    nios2)
        test_defconfig="qemu_nios2_10m50_defconfig"
	# Needs qemu >= 2.9
	test_board_dir="nios2-10m50"
	;;
    openrisc)
        test_defconfig="qemu_or1k_defconfig"
        test_board_dir="or1k"
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
    powerpc64-e5500)
        test_defconfig="qemu_ppc64_e5500_defconfig"
        test_board_dir="ppc64-e5500"
	;;
    riscv64-lp64d)
        test_defconfig="qemu_riscv64_virt_defconfig"
        test_board_dir="riscv64-virt"
        ;;
    s390x-z13)
        test_defconfig="qemu_s390x_defconfig"
        test_defconfig_extra_opts='BR2_TARGET_ROOTFS_EXT2_SIZE="120M"'
        test_board_dir="s390x"
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
        test_board_dir="sparc-ss10"
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
    x86-64)
        test_defconfig="qemu_x86_64_defconfig"
        sed -i "s/tty1/ttyS0/" ${buildroot_dir}/configs/${test_defconfig}
        test_board_dir="x86_64"
        test_qemu_append="rw console=ttyS0"
        test_qemu_args="-cpu Opteron_G1"
	;;
    x86-64-core-i7|x86-64-v2)
        test_defconfig="qemu_x86_64_defconfig"
        sed -i "s/tty1/ttyS0/" ${buildroot_dir}/configs/${test_defconfig}
        test_board_dir="x86_64"
        test_qemu_append="rw console=ttyS0"
        test_qemu_args="-cpu Nehalem"
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

    # Search for "# qemu_*_defconfig" tag in all readme.txt files.
    # Qemu command line on multilines using back slash are accepted.
    test_qemu_cmd=$(sed -r ':a; /\\$/N; s/\\\n//; s/\t/ /; ta; /# '${test_defconfig}'$/!d; s/#.*//' ${buildroot_dir}/board/qemu/${test_board_dir}/readme.txt)

    # Replace the output/ folder by the correct path
    test_qemu_cmd=$(echo ${test_qemu_cmd} | sed "s%output/%${test_build_dir}/%g")

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
    mkdir -p ${test_build_dir}/images

    cat <<-_EOF_ > "${test_build_dir}/images/start-qemu.sh"
	#!/bin/sh
	(
	BINARIES_DIR="\${0%/*}/"
	cd \${BINARIES_DIR}

	export PATH="${test_build_dir}/host/bin:\${PATH}"
	exec ${test_qemu_cmd}
	)
_EOF_

    chmod +x "${test_build_dir}/images/start-qemu.sh"

    local testbootlogfile=${test_dir}/${release_name}-test-boot.log

    echo "  booting test system ... "
    echo "  boot command: ${test_qemu_cmd}"
    cd ${test_dir}
    if ! ${buildroot_dir}/support/scripts/boot-qemu-image.py ${test_defconfig} 2>&1 | \
	       tee ${testbootlogfile}; then
        echo "  booting test system ... FAILED"
        return 1
    fi
    echo "  booting test system ... SUCCESS"
}

function build_test {
    # Create test directory for the new toolchain
    rm -rf ${test_build_dir}
    mkdir -p ${test_build_dir}
    cp -r ${base_dir}/overlay ${test_build_dir}/overlay

    # Generate the full qemu system configuration
    testconfigfile=${test_build_dir}/.config
    echo "  generating configuration"
    cp ${buildroot_dir}/configs/${test_defconfig} ${testconfigfile}
    echo ${test_defconfig_extra_opts} >> ${testconfigfile}
    echo "BR2_ROOTFS_OVERLAY=\"${test_build_dir}/overlay\"" >> ${testconfigfile}

    local fragment_file=${build_dir}/br_fragment

    if ! test -e ${fragment_file}; then
        echo "${fragment_file} missing. Exiting with code 1"
        exit 1
    fi

    cp ${fragment_file} ${test_build_dir}/br_fragment
    sed -i "s/DOWNLOAD/PREINSTALLED/" ${test_build_dir}/br_fragment
    sed -i "/^BR2_TOOLCHAIN_EXTERNAL_URL/d" ${test_build_dir}/br_fragment
    echo "BR2_TOOLCHAIN_EXTERNAL_PATH=\"${toolchain_dir}\"" >> ${test_build_dir}/br_fragment
    echo "BR2_WGET=\"wget --passive-ftp -nd -t 3 --no-check-certificate\"" >> ${test_build_dir}/br_fragment

    cat ${test_build_dir}/br_fragment >> ${testconfigfile}

    # Starting the system build
    echo "  starting test system build at $(date)"
    echo "  making old config"
    make -C ${buildroot_dir} O=${test_build_dir} olddefconfig > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        echo "olddefconfig failed"
        return 1
    fi
    make -C ${buildroot_dir} O=${test_build_dir} savedefconfig > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        echo "savedefconfig failed"
        return 1
    fi
    echo "=================== BEGIN TEST SYSTEM DEFCONFIG ======================"
    cat ${test_build_dir}/defconfig
    echo "=================== END TEST SYSTEM DEFCONFIG ======================"

    local testbuildlogfile=${test_dir}/${release_name}-test-build.log

    echo "  building test system"
    # FORCE_UNSAFE_CONFIGURE=1 to allow to build host-tar as root
    make FORCE_UNSAFE_CONFIGURE=1 -C ${buildroot_dir} O=${test_build_dir} 2>&1 | \
	    tee ${testbuildlogfile} | grep --colour=never ">>>"
    if [ $? -ne 0 ] ; then
        echo "  finished test system build at $(date) ... FAILED"
        echo "  printing the end of the logs before exiting"
        echo "=================== BEGIN LOG FILE ======================"
        tail -n 200 ${testbuildlogfile}
        echo "==================== END LOG FILE ======================="
        return 1
    fi
    echo "  finished test system build at $(date) ... SUCCESS"

    touch ${test_dir}/build-done

    return 0
}

function get_buildroot {
    if test -d ${buildroot_dir} ; then
	pushd ${buildroot_dir}
	git fetch origin
	git checkout $buildroot_tree
	br_version=$(git describe --tags)
	popd
    else
	git clone ${buildroot_repo} ${buildroot_dir}
	pushd ${buildroot_dir}
	git checkout $buildroot_tree
	br_version=$(git describe --tags)
	popd
    fi
    echo "Buildroot version: " ${br_version}
}

function extract_toolchain {
    mkdir -p ${toolchain_dir}

    if ! test -e ${build_dir}/${release_name}.tar.bz2 ; then
        echo "Artifacts ${release_name}.tar.bz2 missing"
        exit 1
    fi

    echo "Extracting toolchain tarball"
    tar --strip-components=1 -C ${toolchain_dir} -xf ${build_dir}/${release_name}.tar.bz2
}

function main {
    echo "Building ${name}"
    echo "Target: ${target}"
    echo "Buildroot tree: ${buildroot_tree}"
    echo "Version identifier: ${version}"

    if [ "$target" == "ci_debug" ]; then
	echo "ci_debug is set as target, you should see this line, but the build won't go further."
	echo "Exiting properly."
	exit 0
    fi

    get_buildroot

    echo "Runtime Testing ${name}..."

    mkdir -p ${test_dir}

    set_test_config

    if [ "${test_defconfig}" = "" ]; then
	    echo "No test defconfig for this toolchain, cannot test"
	    echo "CAN-NOT-TEST" > ${test_dir}/${release_name}-test-result.txt
	    exit 0
    fi

    echo "Building a test system using ${name}..."

    # Skip the build if already done. Useful for local testing of this
    # script.
    if ! test -f ${test_dir}/build-done; then
	extract_toolchain

	if ! build_test; then
	    echo "Build failed for this toolchain"
	    echo "SYSTEM-BUILD-FAILED" > ${test_dir}/${release_name}-test-result.txt
	    exit 1
	fi
    fi

    if [ "${test_qemu_cmd}" = "" ]; then
	    echo "No qemu command to test this toolchain"
	    echo "CAN-NOT-TEST" > ${test_dir}/${release_name}-test-result.txt
	    exit 0
    fi

    echo "Booting the test system in qemu..."
    if boot_test; then
            echo "Booting passed"
	    echo "TEST-OK" > ${test_dir}/${release_name}-test-result.txt
	    return
    else
            echo "Booting failed"
	    echo "NO-BOOT" > ${test_dir}/${release_name}-test-result.txt
	    exit 1
    fi
}

if [ $# -ne 4 ]; then
	show_help
	exit 1
fi

main
