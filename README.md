# Toolchains builder

The goal of this project is to automatize the build of a wide range of toolchains using [Buildroot](https://buildroot.org).

Since making a per-toolchain configuration is not viable, some scripts have been made to allow a more flexible configuration.
You can find all the config fragments in the [configs](configs) folder.


## update_gitlab-ci.sh

This script simply makes the different valid fragments from all the possible combinations
of architecture, libc, and version, found in the `configs` folder.

It autocommits the generated fragments in a `builds` branch. The fragments are in the `frags`
folder, and a `.gitlab-ci.yaml` file is created to trigger the builds if pushed to a well
configured Gitlab hosted project.

## build.sh

This is the main script handling the build, the test, and the packaging of the toolchain. If 
you typically want to recreate the whole build process, just run that as root (for `chroot`). 
It is wise to do that in some sort of container, and not on your bare system.

## build_chroot.sh

This is the script called in the `chroot` environment, that simply builds the toolchain without 
testing it or packaging anything. If you simply want to reproduce the build for debugging, it's 
probably this script your looking for.


All these scripts can be called without arguments to get their usage informations.


# Hosted Toolchains Build Process

The automated process for the toolchains hosted at [Bootlin](https://toolchains.bootlin.com/)
begins with git clones of [bootlin toolchains-builder](https://github.com/bootlin/toolchains-builder)
and [bootlin buildroot-toolchains](https://github.com/bootlin/buildroot-toolchains). Once the
repositories are cloned, the tags specified by the CI configuration are checked out and the CI
starts the builds. After the build is completed, a qemu test is run to verify the toolchains. The
toolchains are then archived, the sha256 are posted alongside the tarballs of the toolchains, and
build logs are published.

The chain of trust can be verified with multiple steps. The sha256 of the tarball can be compared
with the listed sha256. The timestamps of the tarball and sha256 file can be compared. The build
log can be compared with the summary.csv that is included in the tarball to verify the buildroot
version used.
