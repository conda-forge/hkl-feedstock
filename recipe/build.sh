#!/bin/bash

set -ex

printf "### \n"
printf "### (%s) start of build.sh \n" $(date -Iseconds)
printf "###  \n"

# Detect Windows target up front; the build flow there is simpler:
#   - autotools_clang_conda (sourced via bld.bat) provides bash +
#     autoconf/automake/libtool/make/sed + clang + lld, configured to
#     produce MSVC-compatible binaries
#   - no rpath, no Mach-O linker flags, no native-pre-build dance
#   - introspection is dropped entirely on Windows for now (GI cross-
#     build machinery is not yet adapted to MinGW/clang-on-windows)
IS_WIN=0
case "${target_platform:-}" in
    win-*) IS_WIN=1 ;;
esac
if [ "$IS_WIN" = 1 ]; then
    printf "### ---> (%s) Windows target detected; using simplified build flow.\n" $(date -Iseconds)
fi

if [ "$IS_WIN" = 0 ]; then

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

fi  # IS_WIN==0

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
# Note: use `sed -i.bak -e ...` form for portability between GNU sed
# (Linux) and BSD sed (macOS native build hosts). BSD sed requires a
# backup-suffix argument immediately after -i and rejects the
# `<expr> -i <file>` ordering accepted by GNU sed. Also use -E (POSIX
# extended regex) instead of -r (GNU-only). The .bak files are inside
# the build tree and discarded automatically.
sed -i.bak -e 's/^gtkdocize/#&/' autogen.sh
sed -i.bak -e '/^GTK_DOC.*/a\
m4_ifdef([GTK_DOC_USE_LIBTOOL], [], [AM_CONDITIONAL([GTK_DOC_USE_LIBTOOL], false)])' configure.ac
sed -i.bak -e 's/^GTK_DOC/dnl &/' configure.ac
sed -i.bak -E 's/--enable-gtk-doc//' Makefile.am
grep gtkdocize autogen.sh
grep GTK_DOC configure.ac
grep AM_DISTCHECK_CONFIGURE_FLAGS Makefile.am

# On macOS, Apple Clang does not accept GCC's -ftrack-macro-expansion=0.
# configure.ac unconditionally sets DATATYPE99_CFLAGS to include this flag.
# Strip it on macOS; it's only useful for prettier preprocessor error
# messages with the datatype99 sum-type library, which is disabled here.
if [[ "${HOST:-$(uname -m)-unknown-$(uname -s | tr A-Z a-z)}" == *darwin* ]]; then
    printf "### ---> (%s) Stripping GCC-only -ftrack-macro-expansion=0 on macOS ... \n" $(date -Iseconds)
    sed -i.bak -e 's/-ftrack-macro-expansion=0//g' configure.ac
    grep -n 'track-macro' configure.ac || echo "  (flag removed)"
fi

# On Windows, autotools_clang_conda ships m2-autoconf 2.71; configure.ac
# requires 2.72 via AC_PREREQ. Newer AC_PREREQ-2.72-only features are
# not actually used in this configure.ac (verified by grep), so bumping
# the prereq down to 2.71 is safe. Drop this sed once conda-forge ships
# a 2.72 m2-autoconf wrapper that autotools_clang_conda picks up.
if [ "$IS_WIN" = 1 ]; then
    printf "### ---> (%s) Patching AC_PREREQ down to 2.71 for Windows m2-autoconf ... \n" $(date -Iseconds)
    sed -i.bak -e 's/AC_PREREQ(\[2\.72\])/AC_PREREQ([2.71])/' configure.ac
    grep -n 'AC_PREREQ' configure.ac
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

if [ "$IS_WIN" = 0 ]; then
    # Make installed binaries find their sibling libraries via $ORIGIN.
    # Not applicable on Windows (no rpath concept; DLL search uses PATH
    # / SxS / app-local-side-by-side instead).
    ORIGIN_RPATH='\$ORIGIN/../lib'
    RPATH_FLAG="-Wl,-rpath,${ORIGIN_RPATH}"
    export LDFLAGS="${LDFLAGS:-} ${RPATH_FLAG}"
fi
export CPPFLAGS="${CPPFLAGS:-} -I${PREFIX}/include"
export CFLAGS="${CFLAGS:-}"
if [ "$IS_WIN" = 0 ]; then
    export PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:${BUILD_PREFIX}/lib/pkgconfig"
fi

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
if [ "$IS_WIN" = 1 ]; then
    # On Windows, $PKG_CONFIG was not exported above; use the one that
    # autotools_clang_conda has put on PATH (it lives in
    # %BUILD_PREFIX%\Library\bin\pkg-config but bash's PATH translation
    # makes plain `pkg-config` find it).
    PKG_CONFIG=pkg-config
fi
export GSL_CFLAGS="$(${PKG_CONFIG} --cflags gsl)"
export GSL_LIBS="$(${PKG_CONFIG} --libs gsl)"
printf "### ---> GSL_CFLAGS=%s\n" "${GSL_CFLAGS}"
printf "### ---> GSL_LIBS=%s\n" "${GSL_LIBS}"

# ----------------------------------------------------------------------------
# Cross-compilation native-build dance for GObject-Introspection.
#
# g-ir-scanner introspects a C library by compiling AND running a small
# probe binary linked against it. In a cross-build, the probe binary is
# target-arch and cannot run on the build host -- the host-prefix's
# g-ir-scanner ends up failing the introspection step.
#
# Standard conda-forge solution (used by harfbuzz, pango, gdk-pixbuf, atk):
# do a *separate* native build of the package first, with all CC/AR/NM
# pointing at $CC_FOR_BUILD, installing into $BUILD_PREFIX. During that
# native build, set GI_CROSS_LAUNCHER=$BUILD_PREFIX/libexec/gi-cross-
# launcher-save.sh, which captures the probe binary's stdout/files into
# $SRC_DIR/saved-<basename>. Then for the cross build, set
# GI_CROSS_LAUNCHER=$BUILD_PREFIX/libexec/gi-cross-launcher-load.sh,
# which replays the saved output instead of trying to run the
# (non-runnable) target binary.
#
# Assumption: the introspected symbol set is the same for native and
# cross builds. True for hkl: no platform-conditional public API.
# ----------------------------------------------------------------------------
if [[ "${CONDA_BUILD_CROSS_COMPILATION:-0}" == "1" ]]; then
    printf "### ---> (%s) Cross-build detected; running native pre-build for g-ir-scanner ... \n" $(date -Iseconds)
    (
        mkdir -p native-build
        cd native-build

        # Override the cross-compile environment with a native-build one.
        # Must override every toolchain binary, not just CC -- libtool also
        # uses RANLIB (otherwise the target ranlib runs on the build-host
        # archive and silently corrupts it: e.g. x86_64-apple-darwin13-ranlib
        # on a Linux ar archive writes BSD `__.SYMDEF SORTED` (`/`) as the
        # first member, which subsequent libtool `ar x` extractions choke on
        # with "illegal output pathname for archive member: /").
        export CC="${CC_FOR_BUILD}"
        export AR="$(${CC_FOR_BUILD} -print-prog-name=ar)"
        export NM="$(${CC_FOR_BUILD} -print-prog-name=nm)"
        export RANLIB="$(${CC_FOR_BUILD} -print-prog-name=ranlib)"
        export STRIP="$(${CC_FOR_BUILD} -print-prog-name=strip)"
        export LD="$(${CC_FOR_BUILD} -print-prog-name=ld)"
        # Drop target-specific CFLAGS/CPPFLAGS; build host doesn't need
        # them and they may include incompatible flags (e.g.
        # -mmacosx-version-min for the compiler).
        unset CFLAGS
        unset CPPFLAGS
        # Replace target LDFLAGS (Mach-O-only -Wl,-headerpad_max_install_names
        # and -Wl,-dead_strip_dylibs that GNU ld rejects with
        # "unable to disambiguate") with build-host-appropriate ones.
        # Must still include -L$BUILD_PREFIX/lib and rpath so that
        # AM_PATH_GLIB_2_0's compile-and-run test finds the build-prefix
        # glib instead of the AlmaLinux system glib (glib2-2.68.4),
        # which produces "pkg-config returned 2.88.1, but GLIB (2.68.4)"
        # and leaves GLIB_MKENUMS empty -> later make failures.
        export LDFLAGS="-L${BUILD_PREFIX}/lib -Wl,-rpath,${BUILD_PREFIX}/lib"
        # Tell configure this is a native build (avoid the autoconf
        # cross-compile guessing that fires when build != host).
        export host_alias="${build_alias}"
        # PKG_CONFIG_PATH=$BUILD_PREFIX so .pc files come from the
        # build-side gsl/glib/etc., with native paths baked into them.
        export PKG_CONFIG_PATH="${BUILD_PREFIX}/lib/pkgconfig"

        # Recompute GSL_LIBS/GSL_CFLAGS in the native env (different prefix).
        export GSL_CFLAGS="$(${PKG_CONFIG} --cflags gsl)"
        export GSL_LIBS="$(${PKG_CONFIG} --libs gsl)"
        printf "### ---> (native) GSL_CFLAGS=%s\n" "${GSL_CFLAGS}"
        printf "### ---> (native) GSL_LIBS=%s\n" "${GSL_LIBS}"

        printf "### ---> (%s) (native) Running ../configure ... \n" $(date -Iseconds)
        ../configure \
            --prefix="${BUILD_PREFIX}" \
            --disable-static \
            --disable-binoculars \
            --disable-gui \
            --disable-hkl-doc \
            --enable-introspection=yes \
            GSL_CFLAGS="${GSL_CFLAGS}" \
            GSL_LIBS="${GSL_LIBS}" \
            LDFLAGS="${LDFLAGS}"

        # Tell g-ir-scanner to *save* the probe binary's output for the
        # later cross-build to replay.
        export GI_CROSS_LAUNCHER="${BUILD_PREFIX}/libexec/gi-cross-launcher-save.sh"

        printf "### ---> (%s) (native) Running make ... \n" $(date -Iseconds)
        make -j "${CPU_COUNT:-1}"

        printf "### ---> (%s) (native) Running make install ... \n" $(date -Iseconds)
        make install
    )
    # After the native build completes, the saved introspection data
    # lives in $SRC_DIR/saved-Hkl-5.0.gir/. Switch the cross-build to
    # replay-mode for g-ir-scanner.
    export GI_CROSS_LAUNCHER="${BUILD_PREFIX}/libexec/gi-cross-launcher-load.sh"
    printf "### ---> Native pre-build done; cross build will use GI_CROSS_LAUNCHER=%s\n" "${GI_CROSS_LAUNCHER}"

    # Patch the build-prefix g-ir-scanner to drop "-Wl,--no-as-needed"
    # when building the probe binary, for macOS cross-targets only.
    #
    # gobject-introspection's giscanner/ccompiler.py guards this flag
    # with `if sys.platform != 'darwin':` -- but sys.platform is the
    # *scanner's* platform (Linux, the build host), not the *target*'s.
    # When cross-compiling Linux -> macOS, the scanner is run on Linux
    # and so adds --no-as-needed, which Apple ld then rejects:
    #
    #     ld: unknown option: --no-as-needed
    #     x86_64-apple-darwin13.4: error: linker command failed
    #
    # Reported upstream; until that is fixed we patch the installed
    # ccompiler.py in-place to disable the flag-add. The native pre-build
    # above ran with the flag *intact* (Linux ld needs it for the ldd-
    # based symbol introspection), so this patch only affects the cross
    # build's scanner invocation.
    if [[ "${HOST:-}" == *darwin* ]]; then
        CCOMPILER_PY="${BUILD_PREFIX}/lib/gobject-introspection/giscanner/ccompiler.py"
        if [ -f "${CCOMPILER_PY}" ]; then
            printf "### ---> (%s) Disabling -Wl,--no-as-needed in g-ir-scanner for macOS target ... \n" $(date -Iseconds)
            # Replace both occurrences of the guard so neither branch
            # appends the flag. Use a sed expression that is idempotent.
            sed -i.bak -e "s|if sys.platform != 'darwin':|if False:  # hkl-feedstock cross-compile workaround: was 'sys.platform != darwin'|g" "${CCOMPILER_PY}"
            # Verify the patch took effect (and that --no-as-needed is
            # no longer reachable via the now-False branch).
            if grep -nF "if sys.platform != 'darwin'" "${CCOMPILER_PY}"; then
                echo "ERROR: ccompiler.py patch did not apply -- guard still present" >&2
                exit 1
            fi
            grep -n 'no-as-needed' "${CCOMPILER_PY}" || echo "  (already had no occurrences -- ok)"
        else
            echo "WARNING: ${CCOMPILER_PY} not found; --no-as-needed workaround skipped" >&2
        fi
    fi
fi

printf "### ---> (%s) Running configure ... \n" $(date -Iseconds)
# Drop --enable-introspection on Windows: the GObject-Introspection
# cross-build machinery in this recipe is not yet adapted to clang-on-
# windows (g-ir-scanner/Makefile.introspection invokes libtool with
# Unix paths and assumes ELF/Mach-O). For win-64 we ship the libhkl
# DLL + headers + import lib + pkg-config only; introspection support
# can be layered in once the basic Windows build is verified.
INTROSPECTION_FLAG="--enable-introspection=yes"
if [ "$IS_WIN" = 1 ]; then
    INTROSPECTION_FLAG="--enable-introspection=no"
fi
./configure \
  --prefix="${PREFIX}" \
  --disable-static \
  --disable-binoculars \
  --disable-gui \
  --disable-hkl-doc \
  ${INTROSPECTION_FLAG} \
  GSL_CFLAGS="${GSL_CFLAGS}" \
  GSL_LIBS="${GSL_LIBS}" \
  LDFLAGS="${LDFLAGS}"

# printf "### ---> DIR : %s\n" $(ls)

printf "### ---> (%s) Running make ... \n" $(date -Iseconds)
# Always override INTROSPECTION_SCANNER / _COMPILER to use the build-prefix
# binaries rather than the host-prefix ones. Two reasons:
#
#   1. (Cross-builds) On Linux -> macOS cross-builds, the host-prefix
#      g-ir-scanner targets the wrong arch/OS and would fail.
#
#   2. (Native linux-64) The host-prefix g-ir-scanner script has
#      `#!/usr/bin/env python3`. conda-build's cross-build PATH puts
#      $BUILD_PREFIX/bin first, so `env python3` resolves to the
#      build-env Python (e.g. 3.14) while the host-env's _giscanner
#      C extension was built for the host-env Python (e.g. 3.11).
#      Python version mismatch -> ModuleNotFoundError: giscanner._giscanner.
#      Using the build-prefix scanner aligns the Python interpreter
#      with the C extension's ABI tag.
#
# GI_CROSS_LAUNCHER (set earlier when CONDA_BUILD_CROSS_COMPILATION=1)
# tells the scanner to replay the saved native-build probe output instead
# of trying to run a target binary.
make_extra=()
if [ "$IS_WIN" = 0 ]; then
    # Always use the build-prefix introspection tools rather than
    # host-prefix ones (Python-ABI mismatch via `env python3` on cross-
    # build PATH; macOS-vs-Linux scanner targeting issues). Not needed
    # on Windows where introspection is disabled.
    make_extra+=("INTROSPECTION_SCANNER=${BUILD_PREFIX}/bin/g-ir-scanner")
    make_extra+=("INTROSPECTION_COMPILER=${BUILD_PREFIX}/bin/g-ir-compiler")
fi
# Pass _XOPEN_SOURCE / _DARWIN_C_SOURCE to ccan's configurator probes via
# CCAN_CFLAGS (the make var referenced by hkl/ccan/Makefile.am's
# `configurator ... $(CCAN_CFLAGS)` invocation). Without this, the
# HAVE_UCONTEXT probe fails on macOS because <ucontext.h> #errors out
# unless _XOPEN_SOURCE is defined, which then leaves COROUTINE_AVAILABLE=0
# and generator.h fires `#error Generators require coroutines`. The flags
# are otherwise already in CFLAGS (set above for darwin), but configurator
# probes do not pick up CFLAGS -- they receive only what is on their
# command line.
if [[ "${HOST:-$(uname -m)-unknown-$(uname -s | tr A-Z a-z)}" == *darwin* ]]; then
    make_extra+=("CCAN_CFLAGS=-D_XOPEN_SOURCE -D_DARWIN_C_SOURCE")
fi
make -j "${CPU_COUNT:-1}" "${make_extra[@]}"

printf "### ---> (%s) Running make install ... \n" $(date -Iseconds)
make install "${make_extra[@]}"

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
# Windows: no introspection was built, so no typelib to rewrite, and
# no shared-library SONAME concept. Just verify the DLL is installed.
if [ "$IS_WIN" = 1 ]; then
    printf "### ---> (%s) Windows target; skipping typelib block. \n" $(date -Iseconds)
    # autotools+libtool's MSVC-compat output names: hkl-5.dll + hkl.lib
    # (import lib) under $LIBRARY_BIN / $LIBRARY_LIB respectively.
    # Check that *something* libhkl-shaped landed in the install.
    ls -l "${PREFIX}"/Library/bin/*hkl*.dll "${PREFIX}"/Library/lib/*hkl*.lib 2>&1 || true
    ls -l "${PREFIX}"/Library/lib/pkgconfig/hkl.pc 2>&1 || true
# Gate on the *target* platform, not the build host: on cross-builds
# `uname -s` would return Linux even when targeting macOS, taking the
# wrong branch.
elif [[ "${HOST:-$(uname -m)-unknown-$(uname -s | tr A-Z a-z)}" != *darwin* ]]; then
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
    # macOS target: just verify the expected install layout.
    printf "### ---> (%s) macOS target; skipping typelib absolute-path rewrite. \n" $(date -Iseconds)
    LIBHKL_DYLIB="${PREFIX}/lib/libhkl.5.dylib"
    TYPELIB_FILE="${PREFIX}/lib/girepository-1.0/Hkl-5.0.typelib"
    if [ ! -f "${LIBHKL_DYLIB}" ] || [ ! -f "${TYPELIB_FILE}" ]; then
        echo "ERROR: expected libhkl dylib / typelib missing:" >&2
        ls -l "${LIBHKL_DYLIB}" "${TYPELIB_FILE}" >&2 || true
        exit 1
    fi
fi

printf "### (%s) end of build.sh \n" $(date -Iseconds)
