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
frag_dir=${base_dir}/frags
build_dir=${main_dir}/build
buildroot_dir=${main_dir}/buildroot
fragment_file=${build_dir}/br_fragment
output_dir=${build_dir}/output
release_name=${name}-${version}
toolchain_dir=${build_dir}/${release_name}
logfile=${build_dir}/${name}-build.log
base_url="http://toolchains.bootlin.com/downloads/${target}"
arch_name=$(echo "${name}" |sed "s/--/\t/" |cut -f 1)
version_name=$(echo "${name}" |sed "s/--/\t/" |cut -f 3)

function show_help {
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
}

function build_toolchain {
    rm -rf ${build_dir}
    mkdir -p ${build_dir}
    mkdir -p ${output_dir} ${toolchain_dir}

    # Create the configuration
    cp ${frag_dir}/${name}.config ${output_dir}/.config
    echo "BR2_HOST_DIR=\"${toolchain_dir}\"" >> ${output_dir}/.config

    echo "  starting at $(date)"

    # Generate the full configuration
    make -C ${buildroot_dir} O=${output_dir} olddefconfig > ${logfile} 2>&1
    if [ $? -ne 0 ] ; then
	    echo "  failure during olddefconfig"
	    return 1
    fi

    # Generate fragment to ship in the README
    make -C ${buildroot_dir} O=${output_dir} savedefconfig > ${logfile} 2>&1
    if [ $? -ne 0 ] ; then
	    echo "  failure during savedefconfig"
	    return 1
    fi

    echo "=================== BEGIN DEFCONFIG ======================"
    cat ${output_dir}/defconfig
    echo "==================== END DEFCONFIG ======================="

    # Build
    # FORCE_UNSAFE_CONFIGURE=1 to allow to build host-tar as root
    timeout 225m make FORCE_UNSAFE_CONFIGURE=1 -C ${buildroot_dir} O=${output_dir} 2>&1 | tee ${logfile} | grep --colour=never ">>>"
    if [ $? -ne 0 ] ; then
        echo "  finished at $(date) ... FAILED"
        echo "=================== BEGIN LOG FILE ======================"
        tail -n 200 ${logfile}
        echo "==================== END LOG FILE ======================="
        return 1
    fi

    echo "  finished at $(date) ... SUCCESS"

    # Making legals
    echo "  making legal infos at $(date)"
    make -C ${buildroot_dir} O=${output_dir} legal-info 2>&1 | tee ${logfile}
    if [ $? -ne 0 ] ; then
	    return 1
    fi
    echo "  finished at $(date)"

    make -C ${buildroot_dir} O=${output_dir} sdk 2>&1 | tee ${logfile}
    if [ $? -ne 0 ] ; then
	return 1
    fi
    rm ${toolchain_dir}/usr

    touch ${build_dir}/build-done
}

function make_br_fragment {
    local configfile=${output_dir}/.config

    echo "INFO: making BR fragment to use the toolchain"

    local gcc_version=$(grep '^BR2_TOOLCHAIN_GCC_AT_LEAST=' ${configfile} | \
			    sed -e 's/BR2_TOOLCHAIN_GCC_AT_LEAST="\([^"]*\)"/\1/;s/\./_/')
    local linux_version=$(grep "^BR2_KERNEL_HEADERS_" ${configfile} | \
			      sed 's/BR2_KERNEL_HEADERS_\(.*\)=./\1/')
    local locale=$(grep "^BR2_TOOLCHAIN_BUILDROOT_LOCALE" ${configfile} | \
		       sed 's/BR2_TOOLCHAIN_BUILDROOT_LOCALE=\(.\)/\1/')
    local libc=$(grep "^BR2_TOOLCHAIN_BUILDROOT_LIBC=\".*\"" ${configfile} | \
		     sed 's/BR2_TOOLCHAIN_BUILDROOT_LIBC="\(.*\)"/\1/')

    if test -z "${gcc_version}"; then
	echo "ERROR: cannot get gcc version"
	return 1
    fi

    if test -z "${linux_version}"; then
	echo "ERROR: cannot get linux headers version"
	return 1
    fi

    if test -z "${libc}"; then
	echo "ERROR: cannot get libc"
	return 1
    fi

    rm -f ${fragment_file}

    if [[ "${version_name}" =~ "special-" ]]; then
	cat ${base_dir}/configs/special/${name}.config | grep -v "^BR2_TOOLCHAIN_BUILDROOT" | grep -v "^BR2_KERNEL_HEADERS" >> ${fragment_file}
    else
	cat ${base_dir}/configs/arch/${arch_name}.config >> ${fragment_file}
    fi
    echo "BR2_TOOLCHAIN_EXTERNAL=y" >> ${fragment_file}
    echo "BR2_TOOLCHAIN_EXTERNAL_CUSTOM=y" >> ${fragment_file}
    echo "BR2_TOOLCHAIN_EXTERNAL_DOWNLOAD=y" >> ${fragment_file}
    echo "BR2_TOOLCHAIN_EXTERNAL_URL=\"${base_url}/toolchains/${arch_name}/tarballs/${release_name}.tar.bz2\"" >> ${fragment_file}
    echo "BR2_TOOLCHAIN_EXTERNAL_GCC_${gcc_version}=y" >> ${fragment_file}
    echo "BR2_TOOLCHAIN_EXTERNAL_HEADERS_${linux_version}=y" >> ${fragment_file}
    if [ "${locale}" == "y" ]; then
        echo "BR2_TOOLCHAIN_EXTERNAL_LOCALE=y" >> ${fragment_file}
    else
        echo "# BR2_TOOLCHAIN_EXTERNAL_LOCALE is not set" >> ${fragment_file}
    fi
    if grep -q "BR2_TOOLCHAIN_BUILDROOT_CXX=y" ${configfile}; then
        echo "BR2_TOOLCHAIN_EXTERNAL_CXX=y" >> ${fragment_file}
    else
        echo "# BR2_TOOLCHAIN_EXTERNAL_CXX is not set" >> ${fragment_file}
    fi
    if grep -q "BR2_TOOLCHAIN_BUILDROOT_FORTRAN=y" ${configfile}; then
        echo "BR2_TOOLCHAIN_EXTERNAL_FORTRAN=y" >> ${fragment_file}
    else
        echo "# BR2_TOOLCHAIN_EXTERNAL_FORTRAN is not set" >> ${fragment_file}
    fi
    if grep -q "BR2_TOOLCHAIN_HAS_SSP=y" ${configfile}; then
        echo "BR2_TOOLCHAIN_EXTERNAL_HAS_SSP=y" >> ${fragment_file}
    else
        echo "# BR2_TOOLCHAIN_EXTERNAL_HAS_SSP is not set" >> ${fragment_file}
    fi
    if grep -q "BR2_PTHREAD_DEBUG is not set" ${configfile}; then
        echo "# BR2_TOOLCHAIN_EXTERNAL_HAS_THREADS_DEBUG is not set" >> ${fragment_file}
    else
        echo "BR2_TOOLCHAIN_EXTERNAL_HAS_THREADS_DEBUG=y" >> ${fragment_file}
    fi
    if ! grep -q "BR2_TOOLCHAIN_HAS_THREADS=y" ${configfile}; then
	echo "# BR2_TOOLCHAIN_EXTERNAL_HAS_THREADS is not set" >> ${fragment_file}
    else
	echo "BR2_TOOLCHAIN_EXTERNAL_HAS_THREADS=y" >> ${fragment_file}
    fi
    if ! grep -q "BR2_TOOLCHAIN_HAS_THREADS_NPTL=y" ${configfile}; then
        echo "# BR2_TOOLCHAIN_EXTERNAL_HAS_THREADS_NPTL is not set" >> ${fragment_file}
    else
        echo "BR2_TOOLCHAIN_EXTERNAL_HAS_THREADS_NPTL=y" >> ${fragment_file}
    fi
    if grep -q "BR2_TOOLCHAIN_HAS_NATIVE_RPC=y" ${configfile}; then
        echo "BR2_TOOLCHAIN_EXTERNAL_INET_RPC=y" >> ${fragment_file}
    else
        echo "# BR2_TOOLCHAIN_EXTERNAL_INET_RPC is not set" >> ${fragment_file}
    fi
    if [ "${libc}" == "glibc" ]; then
        echo "BR2_TOOLCHAIN_EXTERNAL_CUSTOM_GLIBC=y" >> ${fragment_file}
    elif [ "${libc}" == "musl" ]; then
        echo "BR2_TOOLCHAIN_EXTERNAL_CUSTOM_MUSL=y" >> ${fragment_file}
    else
        echo "BR2_TOOLCHAIN_EXTERNAL_CUSTOM_UCLIBC=y" >> ${fragment_file}
    fi

    echo "INFO: toolchain fragment follows"
    cat ${fragment_file}
    echo "INFO: toolchain fragment ends"
}

function package {
    local readme_file=${toolchain_dir}/README.txt
    local summary_file=${toolchain_dir}/summary.csv

    echo "INFO: Preparing the packaging of ${release_name}"

    # Keep the original configuration file
    cp ${frag_dir}/${name}.config ${toolchain_dir}/buildroot.config

    # Summary
    tail -n +1 ${build_dir}/output/legal-info/manifest.csv >> ${summary_file}
    tail -n +2 ${build_dir}/output/legal-info/host-manifest.csv >> ${summary_file}

    # Make the README
    printf "${release_name}\n\n" > ${readme_file}
    cat ${base_dir}/readme_base.txt >> ${readme_file}
    printf "\n" >> ${readme_file}

    local host_manifest=${build_dir}/output/legal-info/host-manifest.csv
    local target_manifest=${build_dir}/output/legal-info/manifest.csv

    local gcc_version=$(cat ${host_manifest} | \
				grep '^"gcc-final' | sed 's/","/\t/g' | cut -f2)
    local gdb_version=$(cat ${host_manifest} | \
				grep '^"gdb' | sed 's/","/\t/g' | cut -f2)
    local binutils_version=$(cat ${host_manifest} | \
				     grep '^"binutils' | sed 's/","/\t/g' | cut -f2)
    if grep -q '^"musl"' ${target_manifest}; then
	    local libc_name="musl"
    elif grep -q '^"glibc"' ${target_manifest}; then
	    local libc_name="glibc"
    elif grep -q '^"uclibc"' ${target_manifest}; then
	    local libc_name="uclibc"
    fi

    local libc_version=$(cat ${target_manifest} | \
				 grep "^\"${libc_name}" | sed 's/","/\t/g' | cut -f2)

    printf "This toolchain is based on:\n\n" >> ${readme_file}
    printf "    %-20s version %10s\n" "gcc" "${gcc_version}" >> ${readme_file}
    printf "    %-20s version %10s\n" "binutils" "${binutils_version}" >> ${readme_file}
    printf "    %-20s version %10s\n" "gdb" "${gdb_version}" >> ${readme_file}
    printf "    %-20s version %10s\n" "${libc_name}" "${libc_version}" >> ${readme_file}
    printf "\n" >> ${readme_file}

    cat - >> ${readme_file} <<EOF
For those who would like to reproduce the toolchain, you can just
follow these steps:

    git clone ${buildroot_repo} buildroot
    cd buildroot
    git checkout ${buildroot_tree}

    curl ${base_url}/toolchains/${arch_name}/build_fragments/${release_name}.defconfig > .config
    make olddefconfig
    make
    make sdk
EOF

    # Make the tarball
    echo "Packaging the toolchain as ${release_name}.tar.bz2"
    cd ${build_dir}
    tar cjf `basename ${release_name}`.tar.bz2 `basename ${toolchain_dir}`
    sha256sum ${release_name}.tar.bz2 > ${release_name}.sha256

    cp ${readme_file} ${build_dir}/README.txt
    cp ${summary_file} ${build_dir}/summary.csv
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

    # Skip the build if already done. Useful for local testing of this
    # script.
    if ! test -f ${build_dir}/build-done; then
	build_toolchain
	if test $? -ne 0; then
            echo "Toolchain build failed, not going further"
            exit 1
	fi
    fi

    toolchain_dir="${build_dir}/${release_name}"

    make_br_fragment

    # Everything works, package the toolchain
    package
}

if [ $# -ne 4 ]; then
	show_help
	exit 1
fi

main
