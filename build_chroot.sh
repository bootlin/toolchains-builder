#!/bin/bash

# This script runs inside a chroot, and is responsible for building a
# toolchain.
#
# Script inputs:
#  - Runs in a minimal Debian chroot
#  - Script is installed as /opt/build_chroot.sh, and executed with
#    ${toolchain name} as argument
#  - Buildroot source code is bind-mounted in /opt/buildroot
#
# Script outputs:
#  - Toolchain in /opt/${toolchain name}
#  - Buildroot output in /opt/output

set -o pipefail

function show_help {
    cat - <<EOF
    Usage: $0 toolchain_name

toolchain_name:
        This is a path to a toolchain fragment. '.config' will be appended to
        that path, and it will be copied as is to Buildroot's '.config' file.
EOF
}

function prepare_system {
    apt-get install -y --force-yes -qq --no-install-recommends \
	    build-essential locales bc ca-certificates file rsync gcc-multilib \
	    git bzr cvs mercurial subversion unzip wget cpio curl git-core \
	    libc6-i386 python3 python-argparse 2>&1 1>/dev/null || return 1
    sed -i 's/# \(en_US.UTF-8\)/\1/' /etc/locale.gen
    /usr/sbin/locale-gen || return 1
}

function build_toolchain {
    # Create the configuration
    cp /opt/${name}.config ${output_dir}/.config
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

    cp ${output_dir}/.config ${toolchain_dir}/buildroot.config

    # Different versions of buildroot don't always product the same thing with
    # usr. Old version make usr to be a folder containing the toolchain, newer
    # version just make it a symbolic link for compatibility.
    if ! [ -L ${toolchain_dir}/usr ]; then
        mv ${toolchain_dir}/usr/* ${toolchain_dir}/
        rmdir ${toolchain_dir}/usr
    else
        make -C ${buildroot_dir} O=${output_dir} sdk 2>&1 | tee ${logfile}
        if [ $? -ne 0 ] ; then
		return 1
        fi
        rm ${toolchain_dir}/usr
    fi
}

if ! [ $# -eq 2 ]; then
    show_help
    exit 1
fi

name=$1
version=$2

buildroot_dir=/opt/buildroot
output_dir=/opt/output
toolchain_dir=/opt/${name}-${version}
logfile=/opt/${name}-build.log

mkdir -p ${output_dir} ${toolchain_dir}

if ! prepare_system; then
    echo "ERROR: cannot prepare the system"
    exit 1
fi

if ! build_toolchain $1; then
    echo "ERROR: cannot build toolchain"
    exit 1
fi
