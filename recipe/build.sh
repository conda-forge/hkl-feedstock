#!/bin/bash

set -e

echo "DIAGNOSTIC environment:"
env | sort

echo "DIAGNOSTIC directory listing (pwd):"
ls -lAFgh

echo "DIAGNOSTIC pwd: $(pwd)"

echo "DIAGNOSTIC directory listing (source cache):"
ls -lAFgh/home/conda/feedstock_root/build_artifacts/src_cache

TARBALL="libhkl-v${PKG_VERSION}-x86_64.tar.gz"
echo "Installing from ${TARBALL}"
tar xzf "${TARBALL}" -C "${PREFIX}"
echo "DIAGNOSTIC installed directory:"
# ls -lAFghR  "${PREFIX}"

ls -lAFgh ${PREFIX}/lib/libhkl.*
