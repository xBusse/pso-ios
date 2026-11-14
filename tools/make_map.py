#!/usr/bin/env python3
"""Turn the decomp's symbols.txt into a DolRecomp name map.

Each output line is "ADDRESS SIZE NAME" in hex, one per function, which
`dolrecomp --map` reads to name the generated functions.
"""
import re
import sys

LINE = re.compile(r"(\S+) = \.\w+:0x([0-9A-Fa-f]+); // type:function size:0x([0-9A-Fa-f]+)")

src, dst = sys.argv[1], sys.argv[2]
count = 0
with open(src) as f, open(dst, "w") as out:
    for line in f:
        m = LINE.match(line)
        if m:
            out.write(f"{m[2]} {m[3]} {m[1]}\n")
            count += 1
print(f"wrote {count} function names to {dst}")
