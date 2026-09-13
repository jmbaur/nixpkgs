"""Compile the Basilisp namespaces a package installed, populating the bytecode
caches that ship with it.

Usage: precompile.py SITE_PACKAGES NAMESPACE...

Basilisp caches a namespace's bytecode next to its source the first time it is
imported, and treats a failure to do so as non-fatal, so verify that every
namespace really was cached where the package installed it rather than trusting
the import to have said so.
"""

import importlib.util
import os
import sys

import basilisp.main

basilisp.main.init()

root = os.path.realpath(sys.argv[1])
failures = []

for name in sys.argv[2:]:
    module = importlib.import_module(name)

    source = getattr(module, "__file__", None)
    if source is None or not source.endswith((".lpy", ".cljc")):
        continue

    if os.path.commonpath([root, os.path.realpath(source)]) != root:
        failures.append(f"{name}: imported {source}, which is outside {root}")
        continue

    cache = os.path.splitext(importlib.util.cache_from_source(source))[0] + ".lpyc"
    if not os.path.exists(cache):
        failures.append(f"{name}: no bytecode cache was written to {cache}")

if failures:
    print("Failed to compile Basilisp namespaces:", file=sys.stderr)
    for failure in failures:
        print(f"  {failure}", file=sys.stderr)
    sys.exit(1)
