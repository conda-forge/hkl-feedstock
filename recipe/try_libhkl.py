"""Test that libhkl pre-built support is available in Python."""

import gi  # gobject-introspection, to access libhkl

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

factory = diffractometer_types[TEST_GEOMETRY]
engine_list = factory.create_new_engine_list()
engine_names = [e.name_get() for e in engine_list.engines_get()]
assert TEST_ENGINE in engine_names

engine = engine_list.engine_get_by_name(TEST_ENGINE)
modes = engine.modes_names_get() 
assert "bissector" in modes, f"{modes=}"
assert "constant_omega" in modes, f"{modes=}"
assert "constant_chi" in modes, f"{modes=}"
assert "constant_phi" in modes, f"{modes=}"
assert "double_diffraction" in modes, f"{modes=}"
assert "psi_constant" in modes, f"{modes=}"

geometry = factory.create_new_geometry()
assert geometry.axis_names_get() == TEST_AXIS_LIST

print("All tests finished successfully.")
