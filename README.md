# toolchains-builder

The goal of this project is to automatize the build of a wide range of toolchains using [Buildroot](https://buildroot.org).

Since making a per-toolchain configuration is not viable, some scripts have been made to allow a more flexible configuration.
You can find all the config fragments in the [configs](configs) folder.

Using `./update_gitlab-ci.sh`, which can accept some options for tuning, you can generate a `.gitlab-ci.yml` with all the fragments
combinations representing all the valid configuration (validated by a local Buildroot). It then commits everything in the `builds`
branch and push it to Gitlab where the builds are run.
