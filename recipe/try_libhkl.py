"""Test that libhkl pre-built support is available in Python."""

import gi  # gobject-introspection, to access libhkl
assert "require_version" in dir(gi)

gi.require_version("Hkl", "5.0")
assert "Hkl" in dir(gi.repository)

from gi.repository import Hkl as libhkl
assert libhkl is not None

# access some content
diffractometer_types = libhkl.factories()
assert isinstance(diffractometer_types, dict), f"{diffractometer_types=}"
assert 5 < len(diffractometer_types) < 30, f"{diffractometer_types=}"
for i, dt in enumerate(sorted(diffractometer_types), start=1):
    print(f"{i} {dt}  {diffractometer_types[dt]}")

UserUnits = libhkl.UnitEnum.USER
assert UserUnits is not None, f"{dir(libhkl.UnitEnum)=}"

DefaultUnits = libhkl.UnitEnum.DEFAULT
assert DefaultUnits is not None, f"{dir(libhkl.UnitEnum)=}"

assert "VERSION" in dir(libhkl), f"{dir(libhkl)=}"
assert libhkl.VERSION.startswith("v5.0.0"), f"{libhkl.VERSION=}"
