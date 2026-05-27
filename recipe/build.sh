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

ORIGIN_RPATH='\$ORIGIN/../lib'
RPATH_FLAG="-Wl,-rpath,${ORIGIN_RPATH}"

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

# -----------------------------------------------------------------------------
# Rewrite the GObject-Introspection typelib so it stores the *absolute* path
# to libhkl.so.5 instead of the bare SONAME.
#
# Why:
#   The installed typelib normally records `shared-library="libhkl.so.5"`.
#   When `gi.repository.Hkl` is imported, libgirepository calls
#   `dlopen("libhkl.so.5", ...)` -- a *bare* name, which bypasses the
#   importing process's RPATH and is resolved only via LD_LIBRARY_PATH and
#   the system ld.so cache. In a conda env where neither is set to
#   ${CONDA_PREFIX}/lib, dlopen finds (or fails to find) the wrong library
#   -- typically an older system libhkl/libgobject -- producing errors like:
#
#       ImportError: .../libgobject-2.0.so.0: undefined symbol:
#                    g_pointer_bit_unlock_and_set
#
#   This is the root cause of the LD_LIBRARY_PATH workaround documented in
#       https://github.com/bluesky/hklpy2/issues/69
#       https://github.com/bluesky/hklpy2/issues/413
#       https://bluesky.github.io/hklpy2/faq.html#import-gi
#
#   Recording the absolute path makes dlopen open exactly the libhkl that
#   ships in this package, and its RPATH ($ORIGIN/.) picks the correct
#   sibling libgobject/libglib/libgsl from the same conda env. The path
#   contains ${PREFIX}, which conda-build will detect (via has_prefix) and
#   rewrite to the user's actual prefix at install time.
# -----------------------------------------------------------------------------
printf "### ---> (%s) Rewriting Hkl typelib with absolute libhkl path ... \n" $(date -Iseconds)
GIR_FILE="${PREFIX}/share/gir-1.0/Hkl-5.0.gir"
TYPELIB_FILE="${PREFIX}/lib/girepository-1.0/Hkl-5.0.typelib"
LIBHKL_ABS="${PREFIX}/lib/libhkl.so.5"
if [ ! -f "${GIR_FILE}" ] || [ ! -f "${TYPELIB_FILE}" ] || [ ! -f "${LIBHKL_ABS}" ]; then
    echo "ERROR: expected GIR / typelib / libhkl files are missing:" >&2
    ls -l "${GIR_FILE}" "${TYPELIB_FILE}" "${LIBHKL_ABS}" >&2 || true
    exit 1
fi
g-ir-compiler --shared-library="${LIBHKL_ABS}" \
    -o "${TYPELIB_FILE}" "${GIR_FILE}"
printf "### ---> typelib now references: "
strings "${TYPELIB_FILE}" | grep -E 'libhkl\.so' | head -1

printf "### (%s) end of build.sh \n" $(date -Iseconds)
