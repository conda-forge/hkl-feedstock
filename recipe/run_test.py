"""Test that library (libhkl) is available in Python."""

import os
import pathlib
import sys

# On Windows the recipe does not currently build GObject-Introspection
# (see recipe/build.sh's IS_WIN branch). Skip the gi-based tests and
# just verify the DLL + import lib + pkg-config landed in the install.
if sys.platform == "win32":
    prefix = pathlib.Path(os.environ["PREFIX"])
    bin_dir = prefix / "Library" / "bin"
    lib_dir = prefix / "Library" / "lib"
    pkgconfig = lib_dir / "pkgconfig" / "hkl.pc"
    dlls = list(bin_dir.glob("*hkl*.dll"))
    imp_libs = list(lib_dir.glob("*hkl*.lib"))
    assert dlls, f"no hkl DLL found in {bin_dir}"
    assert imp_libs, f"no hkl import library found in {lib_dir}"
    assert pkgconfig.is_file(), f"hkl.pc missing at {pkgconfig}"
    print(f"Windows install layout OK: dlls={dlls!r} libs={imp_libs!r}")
    sys.exit(0)

# Regression guard for the LD_LIBRARY_PATH workaround in hklpy2's FAQ.
# See: https://github.com/bluesky/hklpy2/issues/69   (original report)
#      https://github.com/bluesky/hklpy2/issues/413  (tracking the fix)
# The conda recipe rewrites Hkl-5.0.typelib so its shared-library entry is an
# absolute path to ${PREFIX}/lib/libhkl.so.5. That way `gi.repository.Hkl`
# dlopens libhkl by absolute path and no longer depends on the user setting
# LD_LIBRARY_PATH=${CONDA_PREFIX}/lib before launching Python / queueserver.
#
# Verify the typelib carries an absolute path before we even try to import.
if sys.platform.startswith("linux"):
    prefix = pathlib.Path(os.environ["PREFIX"])
    typelib = prefix / "lib" / "girepository-1.0" / "Hkl-5.0.typelib"
    blob = typelib.read_bytes()
    expected = bytes(prefix / "lib" / "libhkl.so.5")
    assert expected in blob, (
        f"Hkl typelib does not embed absolute libhkl path; expected to find "
        f"{expected!r} inside {typelib}. The build.sh post-install step "
        f"that rewrites the typelib with `g-ir-compiler --shared-library=...` "
        f"appears to have been skipped or reverted. Without it, importing "
        f"gi.repository.Hkl will require LD_LIBRARY_PATH=${{CONDA_PREFIX}}/lib."
    )
    # Make extra sure the bare SONAME is *not* what the loader will see:
    # the only `libhkl.so` substring in the typelib must be inside our
    # absolute path -- i.e. there must be no second, bare occurrence.
    assert blob.count(b"libhkl.so") == 1, (
        "Hkl typelib contains more than one libhkl.so reference; expected "
        "exactly one (the absolute path)."
    )

# Import with LD_LIBRARY_PATH explicitly emptied so we exercise the
# absolute-path dlopen path the typelib fix is meant to enable.
os.environ.pop("LD_LIBRARY_PATH", None)

import gi  # gobject-introspection, to access libhkl  # noqa: E402

gi.require_version("Hkl", "5.0")
from gi.repository import Hkl as libhkl  # noqa: E402

# access some content
assert "VERSION" in dir(libhkl)
print(f"{libhkl.VERSION=}")

diffractometer_types = libhkl.factories()
assert isinstance(diffractometer_types, dict)
assert 5 < len(diffractometer_types) < 50
for i, dt in enumerate(sorted(diffractometer_types), start=1):
    print(f"{i}\t{dt}")

UserUnits = libhkl.UnitEnum.USER
assert UserUnits is not None

DefaultUnits = libhkl.UnitEnum.DEFAULT
assert DefaultUnits is not None

TEST_GEOMETRY = "E4CV"
TEST_AXIS_LIST = "omega chi phi tth".split()
TEST_ENGINE = "hkl"
TEST_MODES = """
    bissector
    constant_omega
    constant_chi
    constant_phi
    double_diffraction
    psi_constant
""".strip().split()

factory = diffractometer_types[TEST_GEOMETRY]
engine_list = factory.create_new_engine_list()
engine_names = [e.name_get() for e in engine_list.engines_get()]
assert TEST_ENGINE in engine_names

engine = engine_list.engine_get_by_name(TEST_ENGINE)
assert engine.modes_names_get() == TEST_MODES, f"{engine.modes_names_get()=}"

geometry = factory.create_new_geometry()
assert geometry.axis_names_get() == TEST_AXIS_LIST

print(f"All tests (in {__file__!r}) finished successfully.")
