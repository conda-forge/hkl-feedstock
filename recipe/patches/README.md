# Recipe patches for hkl-feedstock

Patches applied via `source.patches:` in `recipe/meta.yaml`. Each entry
below should describe the patch, why it's needed, and the upstream
status. Drop a patch from this list when its upstream fix is in the
pinned commit.

## 0001-ccan-configurator-build-host-binary.patch

**Need:** Cross-builds (e.g. conda-forge `osx-64` and `osx-arm64` built
on a `linux-64` host) fail at `make` time with:

```
./configurator x86_64-apple-darwin13.4.0-clang > ccan_config.h.tmp
/bin/sh: line 1: ./configurator: cannot execute binary file:
                                 Exec format error
```

`hkl/ccan/configurator.c` is a build-time helper that compiles, runs on
the build host, and writes `hkl/ccan/ccan_config.h` from the probed
features of the target compiler. Upstream `hkl/ccan/Makefile.am` builds
it via `noinst_PROGRAMS=configurator`, which makes automake use `$(CC)`
(the target cross-compiler). The resulting binary is target-arch and
cannot be exec'd on the build host.

**Fix:** Build `configurator` with `$(CC_FOR_BUILD)`, falling back to
`$(CC)` when unset (native builds). Conda-build sets `CC_FOR_BUILD` for
cross-compiles; native builds are unaffected.

**Upstream status:** Reported to `picca@synchrotron-soleil.fr` on
2026-05-26 (see `/tmp/opencode/hkl-author-message-2026-05-26.md` for the
covering message; this patch is the concrete fix referenced there).
Drop this patch from `source.patches:` once an upstream-fixed commit is
pinned in `meta.yaml`.

## 0002-coroutine-bump-min-stksz-for-macos.patch

**Need:** Cross-builds for `osx-64` fail at compile time with:

```
coroutine/coroutine.c:63:2: error: array size is negative
   63 |    BUILD_ASSERT(COROUTINE_MIN_STKSZ >= MINSIGSTKSZ);
```

`COROUTINE_MIN_STKSZ` is hard-coded to `2048` in
`hkl/ccan/coroutine/coroutine.h`, while macOS 11 SDK defines
`MINSIGSTKSZ=32768`. The doc-comment for `COROUTINE_MIN_STKSZ`
explicitly promises it is "guaranteed to be at least as large as
MINSTKSZ" -- so the literal is a ccan bug, not a deliberate value.

**Fix:** Bump the literal to `32768`. Larger stacks are always safe;
impact is a small per-coroutine memory increase.

**Upstream status:** Reported in the same 2026-05-26 message to
`picca@synchrotron-soleil.fr` (will be folded into the same upstream
discussion as 0001). Drop this patch once a fix lands upstream and a
fixed commit is pinned in `meta.yaml`.

## 0003-make-api2-optional-on-no-ucontext.patch

**Need:** Building on Windows (and natively on macOS 11+) fails because
`hkl/api2/hkl2.h` unconditionally pulls in
`hkl/ccan/generator/generator.h`, which contains:

```c
#if !COROUTINE_AVAILABLE
#error Generators require coroutines
#endif
```

`COROUTINE_AVAILABLE` is true iff `HAVE_UCONTEXT` is true. Windows
has no `<ucontext.h>`; macOS 11+ has it but the routines are POSIX
2008-deprecated and the ccan probe binary aborts. Without the
api2 subdir + coroutine/generator ccan modules, the rest of libhkl
(diffractometer engines, GObject-Introspection, hkl.h public surface)
builds correctly.

**Fix:** Add a configure-time check for `<ucontext.h>` and gate the
`api2/` subdir (in `hkl/Makefile.am`) and the `coroutine/*.c` +
`generator/*.c` sources (in `hkl/ccan/Makefile.am`) on
`AM_CONDITIONAL([HAVE_API2], ...)`. Linux still builds api2 (because
ucontext.h is present); Windows skips it; the cross-build of macOS
from linux happens to detect ucontext.h via the linux host headers
and so api2 IS built (matching today's behavior for macOS cross-builds).

**Upstream status:** Same 2026-05-26 discussion thread to
`picca@synchrotron-soleil.fr`. The upstream-preferred alternative
would be to add a Win32 Fibers backend to `ccan/coroutine` so that
generators work natively on Windows too; either approach renders this
patch unnecessary. Drop this patch once an upstream solution lands.

**Caveat:** This patch removes the `trajectory_gen` API on Windows
builds. Downstream packages that depend on `libhkl2.la` (the api2
sublibrary) won't be able to use it on Windows. `hklpy2`'s
`hkl_soleil` backend currently does NOT use trajectory_gen, so it
should remain functional on Windows once this patch is applied and
the other Windows-specific recipe work lands.
