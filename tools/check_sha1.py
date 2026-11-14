#!/usr/bin/env python3
"""Exit non-zero unless a file's SHA-1 matches the expected value."""
import hashlib
import sys

path, expected = sys.argv[1], sys.argv[2].lower()
digest = hashlib.sha1(open(path, "rb").read()).hexdigest()
if digest != expected:
    sys.exit(f"error: {path} has SHA-1 {digest}, expected {expected} (needs USA v1.02, GPOE8P)")
print(f"{path}: SHA-1 OK")
