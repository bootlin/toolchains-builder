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

## Manual Testing

The .gitlab-ci.yml can be used as a template to setup the build machine's apt
install list and any system configuration dependencies.

Next, commit any updates to the toolchain-builder GIT repository before running
the update_gitlab-ci.sh (the script updates the CI script and generates the
toolchain configuration fragments). The GIT repository is used as the base for
the branch generated to kick-off the CI. (i.e.)The first step is to invoke
the update script with options to generate a branch with your desired
configuration.  This example configuration used below, builds a version 1,
powerpc64-e5500 target, glibc standard library, using buildroot branch e5500,
and a stable version toolchain env/cfg. The script syntax can be reviewed by
looking at the script's help.

./update_gitlab-ci.sh -n v1 -a powerpc64-e5500 -l glibc -v stable -t no_push -b e5500

If there was a Buildroot custom branch you intended to use and you need
to add the remote, after initially running the update script (sets up the
buildroot clone), enter into the buildroot directory and add that remote.
Then re-run the update script and it should find the branch and report
success.

Now that we have a configuration captured, checkout the branch name which was
noted at the end of the update command's execution. This new branch has a
configuration fragment file checked in which our build will use.

Next the actual build can be invoked by looking at the end of the .gitlab-ci.yml
for the script it would have run as part of the CI. Execute that script manually
and append an additional arg of "local" which ignores the scripts upload steps.

./build.sh powerpc64-e5500--glibc--stable no_push e5500 v1 local

NOTE: To completely start over after a build, remove the "build" folder. This
will force the chroot to be recreated. Before doing that, make sure the proc
and buildroot bind mounts were umounted. If not, the buildroot git clone will
probably be partially deleted as it's bind mounted into the build folder. To
recover from that, umount the bind mounts and delete the buildroot folder. This
will force everything to re-setup.

