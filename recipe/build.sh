#!/bin/bash

set -e

echo "DIAGNOSTIC environment:"
env | sort

echo "DIAGNOSTIC directory listing:"
ls -lAFgh

echo "DIAGNOSTIC pwd: $(pwd)"

TARBALL="libhkl-${PKG_VERSION}-x86_64.tar.gz"
echo "Installing from ${TARBALL}"
tar xzf "${TARBALL}" -C "${PREFIX}"
echo "DIAGNOSTIC installed directory:"
ls -lAFghR  "${PREFIX}"
