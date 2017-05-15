#!/bin/bash
#

base_dir=$(pwd)
br_path=${base_dir}/buildroot

git_current_branch=$(git symbolic-ref -q --short HEAD)
common_config="./configs/common.config"
gitlab_base=".gitlab-ci.yml.in"
git_build_branch="builds"

function show_help {
    cat - <<EOF
Usage: $0 [-a arch] [-l libc] [-v version] [-dh]

    -h          show this help
    -d          debug output

    -t target   defines what to do:
           ci_debug:    just launch the ci jobs, but does not really 
                        compiles the toolchains. Useful for CI debugging.
           build_debug: launch the ci jobs and compiles the toolchains, 
                        but doesn't send them as releases.
           release:     launch the ci jobs and compiles the toolchains, 
                        then send them as releases and trigger the web page 
                        update.
            This option defaults to ci_debug in order not to eat all the CPU
            by accident or misuse.

    -a arch      specify architecture to build (see \`ls configs/arch/*\`)
    -l libc      specify libc to use (see \`ls configs/libc/*\`)
    -v version   specify version to build (see \`ls configs/version/*\`)

EOF
}

debug=0
opt_arch="*"
opt_libc="*"
opt_version="*"
opt_target="ci_debug"

while getopts "a:l:v:dh" opt; do
    case "$opt" in
    d) debug=1
        ;;
    a) opt_arch=$OPTARG
        ;;
    l) opt_libc=$OPTARG
        ;;
    v) opt_version=$OPTARG
        ;;
    t) opt_target=$OPTARG
        ;;
    *|h|\?)
        show_help
        exit 0
        ;;
    esac
done

if [ $debug -eq 0 ]; then exec 2>/dev/null; fi

function check_config {
    cp ${config_file} ${br_path}/.config
    cd ${br_path}
    make olddefconfig 1>&2
    make savedefconfig 1>&2
    if ! diff ${base_dir}/${config_file} defconfig 1>&2; then
        echo "CONFIG does not work" 1>&2
        cd ${base_dir}
        return 1
    fi
    echo "CONFIG OK" 1>&2
    libc_name=$(grep "^BR2_TOOLCHAIN_BUILDROOT_LIBC=\".*\"" .config | sed 's/BR2_TOOLCHAIN_BUILDROOT_LIBC="\(.*\)"/\1/')
    release_name="${arch_name}--${libc_name}--${version_name}"
    printf "${release_name} ... "
    cd ${base_dir}
    return 0
}

# Get buildroot if it's not done to check the configurations
git clone git://git.buildroot.net/buildroot ${br_path}

git branch -D ${git_build_branch}
git checkout -b ${git_build_branch}

cp ${gitlab_base} .gitlab-ci.yml

for arch in $(ls ./configs/arch/${opt_arch}.config); do
    for libc in $(ls ./configs/libc/${opt_libc}.config); do
        for version in $(ls ./configs/version/${opt_version}.config); do
            arch_name=$(basename ${arch} .config)
            libc_name=$(basename ${libc} .config)
            version_name=$(basename ${version} .config)
            name="${arch_name}-${libc_name}-${version_name}"
            config_file=${name}.config
            printf "Generating .gitlab-ci.yml for $name ... "
            cat ${arch} ${libc} ${version} ${common_config} > ${config_file}
            if check_config; then
                mv ${config_file} ${release_name}.config
                cat .gitlab-ci.yml - > .gitlab-ci.yml.tmp <<EOF
${release_name}:
  script:
    - ./build.sh ${release_name} ${opt_target}

EOF
                mv .gitlab-ci.yml.tmp .gitlab-ci.yml
                echo "OK"
            else
                echo "FAIL: This combination does not work"
                rm ${config_file}
            fi
        done
    done
done

git add .
git add -f .gitlab-ci.yml
git commit -m "Build bot: trigger new builds"
git push -u -f gitlab ${git_build_branch}

git checkout $git_current_branch

