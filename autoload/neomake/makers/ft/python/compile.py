#!/usr/bin/env python

from __future__ import print_function
from sys import argv, exit


if len(argv) != 2:
    exit(64)

try:
    compile(open(argv[1]).read(), argv[1], 'exec', 0, 1)
except SyntaxError as err:
    print('%s:%s:%s: %s' % (err.filename, err.lineno, err.offset, err.msg))
    exit(1)
