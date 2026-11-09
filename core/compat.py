"""
Compatibility layer for running Django 2.2 on Python 3.10 / 3.12+ (Vercel runtime).
Handles collections.abc, distutils removal (PEP 632), and six meta path importer (PEP 451).
"""
import sys
import types
import re
import collections
import collections.abc
from importlib.machinery import ModuleSpec

# 1. Python 3.10+ collections.abc aliases
for attr in ('MutableSet', 'MutableMapping', 'MutableSequence', 'Mapping', 'Sequence', 'Iterable', 'Callable', 'Iterator'):
    if not hasattr(collections, attr):
        setattr(collections, attr, getattr(collections.abc, attr, None))

# 2. Python 3.12+ distutils removal shim
if 'distutils' not in sys.modules:
    class LooseVersion:
        def __init__(self, vstring=None):
            self.vstring = vstring
            self.version = []
            if vstring:
                self.version = [int(x) if x.isdigit() else x for x in re.split(r'(\d+)', str(vstring)) if x and x != '.']
        def __str__(self): return str(self.vstring)
        def __repr__(self): return f'LooseVersion ({self.vstring})'
        def __lt__(self, other): return self.version < getattr(other, 'version', [])
        def __le__(self, other): return self.version <= getattr(other, 'version', [])
        def __eq__(self, other): return self.version == getattr(other, 'version', [])
        def __ge__(self, other): return self.version >= getattr(other, 'version', [])
        def __gt__(self, other): return self.version > getattr(other, 'version', [])

    d = types.ModuleType('distutils')
    dv = types.ModuleType('distutils.version')
    dv.LooseVersion = LooseVersion
    d.version = dv
    sys.modules['distutils'] = d
    sys.modules['distutils.version'] = dv

# 3. Python 3.12+ django.utils.six PEP 451 meta path importer shim
try:
    import django.utils.six as six
    cls = six._SixMetaPathImporter
    if not hasattr(cls, 'find_spec'):
        cls.find_spec = lambda self, fullname, path=None, target=None: ModuleSpec(fullname, self) if fullname in self.known_modules else None
        cls.create_module = lambda self, spec: self.load_module(spec.name)
        cls.exec_module = lambda self, module: None
except Exception:
    pass
