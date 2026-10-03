"""Importing this package registers every exercise definition.

Each family lives in its own module; a module that fails to import is reported and skipped so one
work-in-progress family never breaks the others.
"""
import importlib
import sys
import traceback

MODULES = ['squat', 'hinge', 'pushup', 'pull', 'overhead', 'press_lying',
           'arms', 'legs', 'core', 'cardio', 'raises_rows', 'olympic']

for _m in MODULES:
    try:
        importlib.import_module(f'{__name__}.{_m}')
    except ModuleNotFoundError as e:
        if e.name != f'{__name__}.{_m}':
            traceback.print_exc()
            print(f'[exercises] {_m} failed to import', file=sys.stderr)
    except Exception:
        traceback.print_exc()
        print(f'[exercises] {_m} failed to import', file=sys.stderr)
