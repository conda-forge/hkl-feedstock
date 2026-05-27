#!/bin/bash

set -ex

printf "### \n"
printf "### (%s) start of build.sh \n" $(date -Iseconds)
printf "###  \n"

# Cross-compilation pkg-config plumbing.
#
# On a cross-build, both ${BUILD_PREFIX}/bin and ${PREFIX}/bin contain a
# pkg-config wrapper named ${HOST}-pkg-config that delegates to a sibling
# pkg-config.bin. The host-prefix pkg-config.bin is built for the target
# (e.g. Mach-O on osx-64) and cannot be exec'd from the build host (Linux),
# producing "cannot execute binary file: Exec format error". autoconf's
# AC_CHECK_TOOL search finds the host-prefix wrapper first and breaks.
#
# Fix (mirrors harfbuzz-feedstock): explicitly point PKG_CONFIG at the
# build-prefix unprefixed wrapper, which uses the build-native pkg-config.bin
# and reads PKG_CONFIG_PATH for target .pc files.
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkg-config"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${BUILD_PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
export PKG_CONFIG_PATH_FOR_BUILD="${BUILD_PREFIX}/lib/pkgconfig"

# macOS-specific CFLAGS additions.
#
# hkl/ccan/coroutine/coroutine.c uses ucontext.h (getcontext/makecontext/
# setcontext/swapcontext). On macOS, <ucontext.h> hides these routines
# (they are POSIX 2008-deprecated on Darwin) unless _XOPEN_SOURCE is
# defined. Without it the build fails:
#
#     ucontext.h: error: The deprecated ucontext routines require
#                        _XOPEN_SOURCE to be defined
#
# Also define _DARWIN_C_SOURCE because _XOPEN_SOURCE alone disables
# several Darwin extensions that other code in hkl/glib expects.
if [[ "${HOST:-$(uname -m)-unknown-$(uname -s | tr A-Z a-z)}" == *darwin* ]]; then
    export CFLAGS="${CFLAGS:-} -D_XOPEN_SOURCE -D_DARWIN_C_SOURCE"
fi

printf "### ---> (%s) Disable/remove gtk-doc from source ... \n" $(date -Iseconds)
touch gtk-doc.make  # OK if it is empty
sed -e 's/^gtkdocize/#&/' -i autogen.sh
sed '/^GTK_DOC.*/a m4_ifdef([GTK_DOC_USE_LIBTOOL], [], [AM_CONDITIONAL([GTK_DOC_USE_LIBTOOL], false)])' -i configure.ac
sed -e 's/^GTK_DOC/dnl &/' -i configure.ac
sed -r 's/--enable-gtk-doc//'  -i Makefile.am
grep gtkdocize autogen.sh
grep GTK_DOC configure.ac
grep AM_DISTCHECK_CONFIGURE_FLAGS Makefile.am

# On macOS, Apple Clang does not accept GCC's -ftrack-macro-expansion=0.
# configure.ac unconditionally sets DATATYPE99_CFLAGS to include this flag.
# Strip it on macOS; it's only useful for prettier preprocessor error
# messages with the datatype99 sum-type library, which is disabled here.
if [[ "${HOST:-$(uname -m)-unknown-$(uname -s | tr A-Z a-z)}" == *darwin* ]]; then
    printf "### ---> (%s) Stripping GCC-only -ftrack-macro-expansion=0 on macOS ... \n" $(date -Iseconds)
    sed -i 's/-ftrack-macro-expansion=0//g' configure.ac
    grep -n 'track-macro' configure.ac || echo "  (flag removed)"
fi

printf "### ---> (%s) Running autogen.sh ... \n" $(date -Iseconds)
# Make sure autoreconf/aclocal find autoconf-archive's m4 macros (AX_PATH_GSL,
# AX_CFLAGS_WARN_ALL, etc.) from the build prefix. Without this, aclocal
# silently misses them on cross-builds where the host prefix is searched
# first, leaving e.g. GSL_LIBS empty in the generated Makefiles and
# producing "Undefined symbols: _gsl_*" at link time on macOS.
export ACLOCAL_PATH="${BUILD_PREFIX}/share/aclocal${ACLOCAL_PATH:+:${ACLOCAL_PATH}}"
printf "### ---> ACLOCAL_PATH=%s\n" "${ACLOCAL_PATH}"
bash ./autogen.sh

ORIGIN_RPATH='\$ORIGIN/../lib'
RPATH_FLAG="-Wl,-rpath,${ORIGIN_RPATH}"

export LDFLAGS="${LDFLAGS:-} ${RPATH_FLAG}"
export CPPFLAGS="${CPPFLAGS:-} -I${PREFIX}/include"
export CFLAGS="${CFLAGS:-}"
export PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:${BUILD_PREFIX}/lib/pkgconfig"

printf "### ---> (%s) Running configure ... \n" $(date -Iseconds)
# configure.ac uses AX_PATH_GSL from autoconf-archive to discover GSL,
# but conda-forge's autoconf-archive 2021.02.19 does not ship that
# macro -- aclocal silently leaves it unexpanded, so configure ends up
# treating "AX_PATH_GSL" as a shell command ("command not found") and
# GSL_LIBS / GSL_CFLAGS remain empty. On Linux this happens to link
# anyway because of as-needed semantics, but on macOS the strict linker
# fails with "Undefined symbols: _gsl_*".
#
# Bypass the missing macro by populating GSL_CFLAGS / GSL_LIBS from
# pkg-config (gsl ships gsl.pc) before configure runs. configure.ac's
# fragment is:
#     AX_PATH_GSL
# which AC_SUBSTs both vars; when AX_PATH_GSL fails to expand, the vars
# are still substituted by autoconf as empty unless we pre-set them in
# the environment (and they're then preserved by `./configure`).
export GSL_CFLAGS="$(${PKG_CONFIG} --cflags gsl)"
export GSL_LIBS="$(${PKG_CONFIG} --libs gsl)"
printf "### ---> GSL_CFLAGS=%s\n" "${GSL_CFLAGS}"
printf "### ---> GSL_LIBS=%s\n" "${GSL_LIBS}"

./configure \
  --prefix="${PREFIX}" \
  --disable-static \
  --disable-binoculars \
  --disable-gui \
  --disable-hkl-doc \
  --enable-introspection=yes \
  GSL_CFLAGS="${GSL_CFLAGS}" \
  GSL_LIBS="${GSL_LIBS}" \
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
# Why (Linux only):
#   The installed typelib normally records `shared-library="libhkl.so.5"`.
#   When `gi.repository.Hkl` is imported, libgirepository calls
#   `dlopen("libhkl.so.5", ...)` -- a *bare* name, which on Linux bypasses
#   the importing process's RPATH and is resolved only via LD_LIBRARY_PATH
#   and the system ld.so cache. In a conda env where neither is set to
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
#
#   macOS dyld behaves differently for bare-name dlopens (it honors @rpath
#   from the caller), so the rewrite is not known to be needed there; we
#   skip it on macOS and let run_test.py's import test verify behavior.
# -----------------------------------------------------------------------------
if [[ "$(uname -s)" == "Linux" ]]; then
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
else
    # On non-Linux (macOS): just verify the expected install layout.
    printf "### ---> (%s) Non-Linux platform; skipping typelib absolute-path rewrite. \n" $(date -Iseconds)
    LIBHKL_DYLIB="${PREFIX}/lib/libhkl.5.dylib"
    TYPELIB_FILE="${PREFIX}/lib/girepository-1.0/Hkl-5.0.typelib"
    if [ ! -f "${LIBHKL_DYLIB}" ] || [ ! -f "${TYPELIB_FILE}" ]; then
        echo "ERROR: expected libhkl dylib / typelib missing:" >&2
        ls -l "${LIBHKL_DYLIB}" "${TYPELIB_FILE}" >&2 || true
        exit 1
    fi
fi

printf "### (%s) end of build.sh \n" $(date -Iseconds)
