#!/usr/bin/env python3
"""Validate the PR title used for a Conventional Commit squash merge."""
import re
import sys

title = sys.stdin.read()
pattern = r'(feat|fix|perf|refactor|docs|test|build|ci|chore|style|revert)(\([^\r\n():]+\))?!?: [^\s][^\r\n]*'
if not re.fullmatch(pattern, title):
    sys.exit('Use a Conventional Commit PR title, for example: fix(coach): preserve meal edits')
