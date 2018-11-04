#!/bin/bash
#

base_dir=$(pwd)
br_path=${base_dir}/buildroot
frag_dir=${base_dir}/frags

git_current_branch=$(git symbolic-ref -q --short HEAD)
common_config="./configs/common.config"
gitlab_base=".gitlab-ci.yml.in"
git_build_branch="builds-$(date +%s)"

debug=0
opt_arch="*"
opt_libc="*"
opt_variant="*"
opt_target="no_push"
opt_brtree="2017.05-toolchains-1"
opt_version=""

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
Usage: $0 -n version [-a arch] [-l libc] [-v variant] [-t target] [-dh]

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

    -b tree-ish checkout Buildroot to that tree-ish object (default is
                ${opt_brtree})
    -n version  version string appended to tarball name

    -a arch     specify architecture to build (see \`ls configs/arch/*\`)
    -l libc     specify libc to use (see \`ls configs/libc/*\`)
    -v variant  specify variant to build (see \`ls configs/version/*\`)

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
    v) opt_variant=$OPTARG
        ;;
    b) opt_brtree=$OPTARG
        ;;
    t) opt_target=$OPTARG
        ;;
    n) opt_version=$OPTARG
        ;;
    *|h|\?)
        show_help
        exit 0
        ;;
    esac
done

if [ $debug -eq 0 ]; then exec 2>/dev/null; fi

if [ -z $opt_version ] ; then
	echo "ERROR: -n option is mandatory"
	exit 1
fi

function check_config {
    cp ${config_file} ${br_path}/.config
    make -C ${br_path} olddefconfig 2>&1 1>/dev/null

    libc_name=$(grep "^BR2_TOOLCHAIN_BUILDROOT_LIBC=\".*\"" ${br_path}/.config |
                    sed 's/BR2_TOOLCHAIN_BUILDROOT_LIBC="\(.*\)"/\1/')
    release_name="${arch_name}--${libc_name}--${variant_name}"

    sort ${br_path}/.config > /tmp/sorted.config
    sort ${config_file} > /tmp/sortedfragmentfile
    rejects_file=$(mktemp)
    comm -23 /tmp/sortedfragmentfile /tmp/sorted.config > ${rejects_file}

    # If the reject file is empty, the configuration is valid
    if [ $(cat ${rejects_file} | wc -l) -eq 0 ]; then
        rm ${rejects_file}
        return 0
    fi

    # Check if the reject matches an exception file. If so, the
    # configuration is considered valid.
    for exception in $(ls -1 configs/exceptions/); do
        exception_m=${exception%.config}
        if [[ $name = $exception_m ]]; then
            if cmp -s configs/exceptions/${exception} ${rejects_file}; then
                rm ${rejects_file}
                return 0
            fi
        fi
    done

    if [ $debug -eq 1 ]; then
        echo ""
        cat ${rejects_file}
    fi

    rm ${rejects_file}
    return 1
}

# Get buildroot if it's not done to check the configurations
if [ ! -d ${br_path} ] ; then
       git clone https://github.com/bootlin/buildroot-toolchains.git ${br_path}
fi

cd ${br_path}
git fetch origin
git reset --hard ${opt_brtree}
cd ${base_dir}

git branch -D ${git_build_branch}
git checkout -b ${git_build_branch}

cp ${gitlab_base} .gitlab-ci.yml

mkdir ${frag_dir}

function add_to_ci {
    arch_name=$(basename ${arch} .config)
    libc_name=$(basename ${libc} .config)
    variant_name=$(basename ${variant} .config)
    name="${arch_name}-${libc_name}-${variant_name}"
    extras=""
    optionals=""
    config_file=${frag_dir}/${name}
    printf "| %20s | %7s | %14s |" ${arch_name} ${libc_name} ${variant_name}
    cat ${arch} ${libc} ${variant} ${common_config} > ${config_file}
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
    - ./build.sh ${release_name} ${opt_target} ${opt_brtree} ${opt_version}

EOF
        mv .gitlab-ci.yml.tmp .gitlab-ci.yml
       printf " %50s | OK\n" "${optionals}"
    else
       printf " %50s | NOK\n" # ${optionals}
        rm ${config_file}
    fi
}

function add_special {
	special_name=$(basename ${special} .config)
	cp ${special} ${frag_dir}/
	cat .gitlab-ci.yml - > .gitlab-ci.yml.tmp <<EOF
${special_name}:
  script:
    - ./build.sh ${special_name} ${opt_target} ${opt_brtree} ${opt_version}

EOF
	mv .gitlab-ci.yml.tmp .gitlab-ci.yml
}

if test "${opt_variant}" = "special" ; then
	for special in $(ls ./configs/special/*.config); do
		add_special
	done
else
	printf "| %20s | %7s | %14s | %30s | %50s | status\n" "arch" "libc" "variant" "extras" "optionals"
	echo

	for arch in $(ls ./configs/arch/${opt_arch}.config); do
		for libc in $(ls ./configs/libc/${opt_libc}.config); do
			for variant in $(ls ./configs/version/${opt_variant}.config); do
				add_to_ci
			done
		done
	done
fi

git add .
git add -f .gitlab-ci.yml
git commit -m "Build bot: trigger new builds"
if [ "$opt_target" != "no_push" ]; then
    git remote add gitlab git@gitlab.com:bootlin/toolchains-builder.git
    git push -u -f gitlab ${git_build_branch}
fi

git checkout $git_current_branch

