
buildroot_repo=https://github.com/bootlin/buildroot-toolchains.git

function show_help {
    cat - <<EOF
    Usage: $0 name target buildroot_treeish

name:
        This is the name of the toolchain you are compiling. The name should at
        least begin with "architecture-name--whatever". The double dash is mandatory
        for it is used a splitting token.

target:
        The folder in which to upload the toolchains. 'releases' is the
        production one, so be careful.

buildroot_treeish:
        A git tree-ish object in which to checkout Buildroot for any of its uses
        accross the process.

version:
	Version identifier.
EOF
}
