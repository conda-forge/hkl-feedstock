#!/bin/bash

set -ex

printf "### \n"
printf "### (%s) start of build.sh \n" $(date -Iseconds)
printf "###  \n"

export PKG_CONFIG_PATH="${PKG_CONFIG_PATH}":"${BUILD_PREFIX}/lib/pkgconfig"

printf "### ---> (%s) Disable/remove gtk-doc from source ... \n" $(date -Iseconds)
touch gtk-doc.make  # OK if it is empty
sed -e 's/^gtkdocize/#&/' -i autogen.sh
sed '/^GTK_DOC.*/a m4_ifdef([GTK_DOC_USE_LIBTOOL], [], [AM_CONDITIONAL([GTK_DOC_USE_LIBTOOL], false)])' -i configure.ac
sed -e 's/^GTK_DOC/dnl &/' -i configure.ac
sed -r 's/--enable-gtk-doc//'  -i Makefile.am
grep gtkdocize autogen.sh
grep GTK_DOC configure.ac
grep AM_DISTCHECK_CONFIGURE_FLAGS Makefile.am

printf "### ---> (%s) Running autogen.sh ... \n" $(date -Iseconds)
bash ./autogen.sh

# Use $ORIGIN so the installed package is relocatable by conda.
# Quote/escape $ORIGIN so the shell does not expand it here.
ORIGIN_RPATH='\$ORIGIN/../lib'
# If your package installs into lib64, change to '\$ORIGIN/../lib64'
RPATH_FLAG="-Wl,-rpath,${ORIGIN_RPATH}"

# Export flags used by autotools configure
export LDFLAGS="${LDFLAGS:-} ${RPATH_FLAG}"
export CPPFLAGS="${CPPFLAGS:-} -I${PREFIX}/include"
export CFLAGS="${CFLAGS:-}"
export PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:${BUILD_PREFIX}/lib/pkgconfig"

printf "### ---> (%s) Running configure ... \n" $(date -Iseconds)
./configure \
  --prefix="${PREFIX}" \
  --disable-static \
  --disable-binoculars \
  --disable-gui \
  --disable-hkl-doc \
  --enable-introspection=yes \
  LDFLAGS="${LDFLAGS}"

# printf "### ---> DIR : %s\n" $(ls)

printf "### ---> (%s) Running make ... \n" $(date -Iseconds)
make -j "${CPU_COUNT:-1}"

printf "### ---> (%s) Running make install ... \n" $(date -Iseconds)
make install

printf "### (%s) end of build.sh \n" $(date -Iseconds)
