#!/bin/bash

ls -lAFgh ${PREFIX}/lib/libhkl.*
test -f ${PREFIX}/lib/libhkl.so

echo "source directory contents"
ls -lAFgh ${SRC_DIR}

echo "references these dynamic libraries"
ldd ${PREFIX}/lib/libhkl.so

test ! -f ${PREFIX}/lib/libhkl.a

echo "libhkl test starting"
test -f ${RECIPE_DIR}/try_libhkl.py
python ${RECIPE_DIR}/try_libhkl.py
echo "libhkl test finished"
