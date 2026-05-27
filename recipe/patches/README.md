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
