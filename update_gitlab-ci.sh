#!/bin/bash
#

base_dir=$(pwd)
br_path=${base_dir}/buildroot
frag_dir=${base_dir}/frags

git_current_branch=$(git symbolic-ref -q --short HEAD)
common_config="./configs/common.config"
gitlab_base=".gitlab-ci.yml.in"
git_build_branch="builds"

debug=0
opt_arch="*"
opt_libc="*"
opt_version="*"
opt_target="no_push"
opt_brtree="2017.05-toolchains-1"
opt_number=""

function clean_up {
    echo "Catching signal, cleaning up"
    cd ${base_dir}
    rm -rf ${frag_dir}
    echo "Checkouting to original branch: ${git_current_branch}"
    git checkout $git_current_branch
    echo "Exiting with code 1"
    exit 1
}

trap clean_up SIGHUP SIGINT SIGTERM

function show_help {
    cat - <<EOF
Usage: $0 -n number [-a arch] [-l libc] [-v version] [-t target] [-dh]

    -h          show this help and exit
    -d          debug output

    -t target   defines what to do:
           no_push:         just prepare the config files and the commit in
                            the build branch, but don't push (do not trigger the
                            Gitlab CI). Useful for debugging.
           ci_debug:        just launch the ci jobs, but does not really
                            compiles the toolchains. Useful for CI debugging.
           <folder_name>:   launch the ci jobs and compiles the toolchains, then
                            send them in the <folder_name>.
                            The webpage searches for toolchains in 'releases'.
           This option defaults to no_push in order not to trigger builds
           by accident or misuse.

    -n number   specify a version number that will be appended to the buildroot
                version (mandatory)

    -b tree-ish checkout Buildroot to that tree-ish object (default is
                ${opt_brtree})

    -a arch     specify architecture to build (see \`ls configs/arch/*\`)
    -l libc     specify libc to use (see \`ls configs/libc/*\`)
    -v version  specify version to build (see \`ls configs/version/*\`)

EOF
}

while getopts "a:l:v:t:b:n:dh" opt; do
    case "$opt" in
    d) debug=1
        ;;
    a) opt_arch=$OPTARG
        ;;
    l) opt_libc=$OPTARG
        ;;
    v) opt_version=$OPTARG
        ;;
    b) opt_brtree=$OPTARG
        ;;
    t) opt_target=$OPTARG
        ;;
    n) opt_number=$OPTARG
        ;;
    *|h|\?)
        show_help
        exit 0
        ;;
    esac
done

if [ "${opt_number}" = "" ]; then
    echo "You MUST specify a version number with -n <number>"
    show_help
    exit 1
fi


if [ $debug -eq 0 ]; then exec 2>/dev/null; fi

function check_config {
    cp ${config_file} ${br_path}/.config
    cd ${br_path}
    make olddefconfig 2>&1 1>/dev/null
    sort .config > /tmp/sorted.config
    sort ${config_file} > /tmp/sortedfragmentfile
    if [ $(comm -23 /tmp/sortedfragmentfile /tmp/sorted.config |wc -l) -gt 0 ]; then
        if [ $debug -eq 1 ]; then
            echo ""
            comm -23 /tmp/sortedfragmentfile /tmp/sorted.config
        fi
        cd ${base_dir}
        return 1
    fi
    libc_name=$(grep "^BR2_TOOLCHAIN_BUILDROOT_LIBC=\".*\"" .config | sed 's/BR2_TOOLCHAIN_BUILDROOT_LIBC="\(.*\)"/\1/')
    release_name="${arch_name}--${libc_name}--${version_name}"
    cd ${base_dir}
    return 0
}

# Get buildroot if it's not done to check the configurations
if [ ! -d ${br_path} ] ; then
       git clone https://github.com/free-electrons/buildroot-toolchains.git ${br_path}
fi

cd ${br_path}
git fetch origin
git reset --hard origin/${opt_brtree}
cd ${base_dir}

git branch -D ${git_build_branch}
git checkout -b ${git_build_branch}

cp ${gitlab_base} .gitlab-ci.yml

mkdir ${frag_dir}

function add_to_ci {
    arch_name=$(basename ${arch} .config)
    libc_name=$(basename ${libc} .config)
    version_name=$(basename ${version} .config)
    name="${arch_name}-${libc_name}-${version_name}"
    extras=""
    optionals=""
    config_file=${frag_dir}/${name}
    printf "| %20s | %7s | %14s |" ${arch_name} ${libc_name} ${version_name}
    cat ${arch} ${libc} ${version} ${common_config} > ${config_file}
    for extra in $(ls -1 ${base_dir}/configs/extra/); do
        extra_m=${extra%.config}
        if [[ $name = $extra_m ]]; then
           extras="${extras} ${extra}"
            cat "${base_dir}/configs/extra/$extra" >> ${config_file}
        fi
    done
    printf " %30s |" "${extras}"
    if check_config; then
        for optional in $(ls -1 ${base_dir}/configs/optionals/); do
            optional_m=${optional%.config}
            if [[ $name = $optional_m ]]; then
               optionals="${optionals} ${optional}"
                cat "${base_dir}/configs/optionals/$optional" >> ${config_file}
            fi
        done
        mv ${config_file} ${frag_dir}/${release_name}.config
        cat .gitlab-ci.yml - > .gitlab-ci.yml.tmp <<EOF
${release_name}:
  script:
    - ./build.sh ${release_name} ${opt_target} ${opt_brtree} ${opt_number}

EOF
        mv .gitlab-ci.yml.tmp .gitlab-ci.yml
       printf " %50s | OK\n" "${optionals}"
    else
       printf " %50s | NOK\n" # ${optionals}
        rm ${config_file}
    fi
}

printf "| %20s | %7s | %14s | %30s | %50s | status\n" "arch" "libc" "version" "extras" "optionals"
echo

for arch in $(ls ./configs/arch/${opt_arch}.config); do
    for libc in $(ls ./configs/libc/${opt_libc}.config); do
        for version in $(ls ./configs/version/${opt_version}.config); do
            add_to_ci
        done
    done
done

git add .
git add -f .gitlab-ci.yml
git commit -m "Build bot: trigger new builds"
if [ "$opt_target" != "no_push" ]; then
    git remote add gitlab git@gitlab.com:free-electrons/toolchains-builder.git
    git push -u -f gitlab ${git_build_branch}
fi

git checkout $git_current_branch

