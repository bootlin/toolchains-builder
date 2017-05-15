#!/bin/bash
#

function test_config {
    echo "CONFIG OK"
}

for arch in $(ls ./configs/arch/*.config); do
    # echo "Found arch $arch"
    for libc in $(ls ./configs/libc/*.config); do
        # echo "Found libc $libc"
        for version in $(ls ./configs/version/*.config); do
            # echo "Found version $version"
            echo "Combination: $arch $libc $version"
        done
    done
done


