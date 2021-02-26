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
test_dir=${main_dir}/test
test_build_dir=${test_dir}/output
release_name=${name}-${version}

ssh_server="gitlabci@toolchains.bootlin.com"
upload_root_folder="www/downloads"
upload_folder=${upload_root_folder}/${target}/toolchains/${arch_name}

function main {
    # Create directories on the server, where the different artefacts
    # will be uploaded.
    for d in fragments tarballs readmes summaries \
                       build_test_logs boot_test_logs \
                       build_fragments test_system_defconfigs \
                       available_toolchains test-system; do
	ssh ${ssh_server} mkdir -p ${upload_folder}/${d}
    done

    local testbuildlogfile=${test_build_dir}/${release_name}-test.log

    # If there was a test build, upload its log and configuration file
    if test -f ${testbuildlogfile}; then
	echo "Upload test build log and config file"
	rsync ${testbuildlogfile} ${ssh_server}:${upload_folder}/build_test_logs/
	rsync ${test_build_dir}/defconfig \
	      ${ssh_server}:${upload_folder}/test_system_defconfigs/${release_name}.defconfig
    fi

    local testbootlogfile=${test_build_dir}/${release_name}-test-boot.log

    if test -f ${testbootlogfile}; then
	echo "Upload test boot log file"
	rsync ${testbootlogfile} \
	      ${ssh_server}:${upload_folder}/boot_test_logs/${release_name}.log
    fi

    for i in ${test_build_dir}/images/* ; do
	echo "Upload test image $i"
	rsync $i ${ssh_server}:${upload_folder}/test-system/${release_name}-$(basename $i)
    done

    # README file
    rsync ${build_dir}/README.txt \
	  ${ssh_server}:${upload_folder}/readmes/${release_name}.txt
    # Summary file
    rsync ${build_dir}/summary.csv \
	  ${ssh_server}:${upload_folder}/summaries/${release_name}.csv
    # Toolchain tarball
    rsync ${build_dir}/${release_name}.tar.bz2 \
	  ${ssh_server}:${upload_folder}/tarballs/
    # Toolchain tarball checksum
    rsync ${build_dir}/${release_name}.sha256 \
	  ${ssh_server}:${upload_folder}/tarballs/
    # BR fragment file
    rsync ${build_dir}/br_fragment \
	  ${ssh_server}:${upload_folder}/fragments/${release_name}.frag
    # Build fragment
    rsync -r ${build_dir}/output/defconfig \
	  ${ssh_server}:${upload_folder}/build_fragments/${release_name}.defconfig
    # License files for host packages
    rsync -r ${build_dir}/output/legal-info/host-licenses/ \
	  ${ssh_server}:${upload_root_folder}/${target}/licenses/
    # Source code of host packages
    rsync -r ${build_dir}/output/legal-info/host-sources/ \
	  ${ssh_server}:${upload_root_folder}/${target}/sources/
    # License files for target packages
    rsync -r ${build_dir}/output/legal-info/licenses/ \
	  ${ssh_server}:${upload_root_folder}/${target}/licenses/
    # Source code for target packages
    rsync -r ${build_dir}/output/legal-info/sources/ \
	  ${ssh_server}:${upload_root_folder}/${target}/sources/
    # Make the toolchain as available
    ssh ${ssh_server} touch ${upload_folder}/available_toolchains/${release_name}
    # And ask the webpage to refresh
    ssh ${ssh_server} touch ${upload_root_folder}/NEED_REFRESH
}

if [ $# -ne 4 ]; then
	show_help
	exit 1
fi

main
