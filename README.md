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
