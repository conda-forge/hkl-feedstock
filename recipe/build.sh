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

printf "### ---> (%s) Running configure ... \n" $(date -Iseconds)
./configure \
  --prefix="${PREFIX}" \
  --disable-static \
  --disable-binoculars \
  --disable-gui \
  --disable-hkl-doc \
  --enable-introspection=yes
# printf "### ---> DIR : %s\n" $(ls)

printf "### ---> (%s) Running make ... \n" $(date -Iseconds)
make -j "${CPU_COUNT:-1}"

printf "### ---> (%s) Running make install ... \n" $(date -Iseconds)
make install

printf "### (%s) end of build.sh \n" $(date -Iseconds)
