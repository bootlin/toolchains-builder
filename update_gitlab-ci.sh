#!/bin/bash
#

base_dir=$(pwd)
br_path=${base_dir}/buildroot

git_current_branch=$(git symbolic-ref -q --short HEAD)
common_config="./configs/common.config"
gitlab_base=".gitlab-ci.yml.in"
git_build_branch="builds"

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

for arch in $(ls ./configs/arch/*.config); do
    for libc in $(ls ./configs/libc/*.config); do
        for version in $(ls ./configs/version/*.config); do
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
    - ./build.sh ${release_name}

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

