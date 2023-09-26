import gi

gi.require_version("Hkl", "5.0")
from gi.repository import Hkl as libhkl
from gi.repository import GLib  # noqa: F401

# access some content
diffractometer_types = libhkl.factories()
assert isinstance(diffractometer_types, dict)
assert 5 < len(diffractometer_types) < 20

UserUnits = libhkl.UnitEnum.USER
assert UserUnits is not None

DefaultUnits = libhkl.UnitEnum.DEFAULT
assert DefaultUnits is not None

assert "VERSION" in dir(libhkl)
assert libhkl.VERSION.startswith("v5.0.0.")
