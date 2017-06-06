#!/bin/bash

apt-get install -y --force-yes -qq --no-install-recommends \
    build-essential locales bc ca-certificates file rsync gcc-multilib \
    git bzr cvs mercurial subversion unzip wget cpio curl git-core \
    libc6-i386 2>&1 1>/dev/null

sed -i 's/# \(en_US.UTF-8\)/\1/' /etc/locale.gen
/usr/sbin/locale-gen

if git clone https://github.com/buildroot/buildroot.git; then
    # buildroot needs patchs
    cd buildroot
    git checkout $2
    curl http://free-electrons.com/~thomas/pub/0001-mpc-mpfr-gmp-build-statically-for-the-host.patch |patch -p1
    curl http://free-electrons.com/~thomas/pub/0002-toolchain-attempt-to-fix-the-toolchain-wrapper.patch |patch -p1
    curl "https://git.buildroot.org/buildroot/patch/?id=4d1c2c82e8945a5847d636458f3825c55529835b" |patch -p1
    curl https://patchwork.ozlabs.org/patch/770835/raw/ |patch -p1
    curl https://patchwork.ozlabs.org/patch/770834/raw/ |patch -p1
    curl https://patchwork.ozlabs.org/patch/770836/raw/ |patch -p1
    cd ..
fi

TOOLCHAIN_DIR=$(pwd)
TOOLCHAIN_BUILD_DIR=${TOOLCHAIN_DIR}
TOOLCHAIN_BR_DIR=${TOOLCHAIN_DIR}/buildroot

git --git-dir=${TOOLCHAIN_BR_DIR}/.git describe > br_version

name=$1
toolchaindir=${TOOLCHAIN_BUILD_DIR}/${name}
logfile=${TOOLCHAIN_BUILD_DIR}/${name}-build.log
builddir=${TOOLCHAIN_BUILD_DIR}/output
configfile=${builddir}/.config

mkdir -p ${TOOLCHAIN_BUILD_DIR} &>/dev/null

function build {
    # Create output directory for the new toolchain
    rm -rf ${toolchaindir}
    mkdir ${toolchaindir}

    # Create build directory for the new toolchain
    rm -rf ${builddir}
    mkdir ${builddir}

    # Create the configuration
    cp ${name}.config ${configfile}
    echo "BR2_HOST_DIR=\"${toolchaindir}\"" >> ${configfile}

    echo "  starting at $(date)"

    # Generate the full configuration
    make -C ${TOOLCHAIN_BR_DIR} O=${builddir} olddefconfig > /dev/null 2>&1

    # Build
    timeout 225m make -C ${TOOLCHAIN_BR_DIR} O=${builddir} > ${logfile} 2>&1
    if [ $? -ne 0 ] ; then
        echo "  finished at $(date) ... FAILED"
        echo "  printing the end of the logs before exiting"
        echo "=================== BEGIN LOG FILE ======================"
        tail -n 200 ${logfile}
        echo "==================== END LOG FILE ======================="
        make -C ${TOOLCHAIN_BR_DIR} O=${builddir} savedefconfig > /dev/null 2>&1
        echo "=================== BEGIN DEFCONFIG ======================"
        cat ${builddir}/defconfig
        echo "==================== END DEFCONFIG ======================="
        return 1
    fi

    echo "  finished at $(date) ... SUCCESS"

    # Making legals
    echo "  making legal infos at $(date)"
    make -C ${TOOLCHAIN_BR_DIR} O=${builddir} legal-info > /dev/null 2>&1
    echo "  finished at $(date)"

    cp ${configfile} ${toolchaindir}/buildroot.config
    mv ${toolchaindir}/usr/* ${toolchaindir}/
    rmdir ${toolchaindir}/usr
    # Toolchain built
}

if [ $# -eq 2 ]; then
    echo "Generating ${name}..."
    if ! build $1; then
        echo "Error in toolchain build. Exiting"
        exit 1
    fi
else
    echo "Usage: $0 toolchain_name buildroot-tree"
    exit 1
fi


