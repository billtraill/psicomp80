#!/usr/bin/env python3
"""Print a PL/0 example as the lines of a test session: each numbered line
with \\r after it.  Comment lines (starting with {) and blank lines are left
out, as the web page leaves them out when it types an example in.

    python3 pl0/tools/typein.py pl0/examples/life.pl0
"""
import sys

for line in open(sys.argv[1]):
    line = line.rstrip()
    if line.strip() and not line.lstrip().startswith("{"):
        print(line + "\\r")
