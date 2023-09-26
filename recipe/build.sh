#!/bin/bash

set -e

# echo "CONDA_PREFIX=${CONDA_PREFIX}"
echo "environment:"
env | sort

echo "directory listing:"
ls -lAFgh

echo "pwd: $(pwd)"
