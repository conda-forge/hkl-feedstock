#!/bin/bash

set -e

echo "CONDA_PREFIX=${CONDA_PREFIX}"
echo "g-ir-scanner location: $(which g-ir-scanner)"

test -d m4 || mkdir m4
# gtkdocize || exit 1

export ACLOCAL_PATH="$PREFIX/share/aclocal"
aclocal --print-ac-dir

export HDF5_CFLAGS=" -I${CONDA_PREFIX}/include"
export HDF5_LIBS=" -L${CONDA_PREFIX}/lib -lhdf5"

autoreconf -ivf

./configure \
    --disable-static \
    --disable-gui \
    --enable-introspection=yes \
    --prefix=$PREFIX
make -j ${CPU_COUNT}
make install
