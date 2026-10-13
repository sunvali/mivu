#!/usr/bin/env python3
"""Read NUL-separated changed paths; unknown or empty changes fail closed."""
import sys

paths = [path for path in sys.stdin.buffer.read().split(b'\0') if path]
docs_only = paths and all(path.startswith(b'docs/') or path.endswith(b'.md') for path in paths)
print('false' if docs_only else 'true')
