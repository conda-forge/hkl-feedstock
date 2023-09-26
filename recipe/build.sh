#!/bin/bash

set -e

# # echo "CONDA_PREFIX=${CONDA_PREFIX}"
# echo "environment:"
# env | sort

# echo "directory listing:"
# ls -lAFgh

# echo "pwd: $(pwd)"

tar xzf "libhkl-${PKG_VERSION}-x86_64.tar.gz" -C "${PREFIX}"
