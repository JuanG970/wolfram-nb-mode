#!/usr/bin/env python3
"""Summarise a run of roundtrip.el and compare.wls.

    summary.py LIST OUTDIR

LIST is the file of notebook paths given to roundtrip.el; OUTDIR holds its
emacs.log and compare.log.  Prints counts, and the notebooks that were not
read back exactly, grouped by what differed.  Only paths and counts are
printed, never notebook content.
"""
import collections
import re
import sys


def main(list_file, out_dir):
    paths = [line.rstrip("\n") for line in open(list_file) if line.strip()]
    emacs = open(f"{out_dir}/emacs.log", errors="replace").read().splitlines()
    done = {}
    for line in emacs:
        m = re.match(r"^(OK|ERR) (\d+) (\S+) ?(.*)$", line)
        if m:
            done[int(m.group(2))] = (m.group(1), m.group(3), m.group(4))
    errors = {n: v for n, v in done.items() if v[0] == "ERR"}
    print(f"notebooks: {len(paths)}   processed: {len(done)}   errors: {len(errors)}")
    for n, (_, msg, rest) in sorted(errors.items())[:8]:
        print(f"  ERR {n:04d} {msg[:70]} {paths[n - 1].split('/15.0/')[-1][:60]}")

    stats = {"U": collections.Counter(), "E": collections.Counter()}
    bad = {"U": collections.defaultdict(list), "E": collections.defaultdict(list)}
    totals = collections.Counter()
    for line in open(f"{out_dir}/compare.log", errors="replace"):
        m = re.match(r"^(\d{4}) ([UE]) (.*)$", line.strip())
        if not m:
            continue
        n, kind, body = int(m.group(1)), m.group(2), m.group(3)
        totals[kind] += 1
        fields = dict(f.split("=", 1) for f in body.split(";") if "=" in f)
        if not fields:
            bad[kind]["no comparison (%s)" % body[:30]].append(n)
            continue
        for key in ("exact", "styles", "groups", "nbopts"):
            if fields.get(key) == "True":
                stats[kind][key] += 1
            else:
                bad[kind][key + " differs"].append(n)
        for key in ("cells", "gfx", "text", "styled", "code", "opts"):
            value = fields.get(key, "0/0")
            a, b = value.split("/")
            stats[kind][key + "_full"] += (a == b)
            if a != b:
                bad[kind][key + " differs"].append(n)
    for kind, label in (("U", "cells left as they were"), ("E", "every cell converted")):
        t = totals[kind]
        print(f"\n{label}: {t} compared")
        for key in ("exact", "styles", "groups", "nbopts", "cells_full", "gfx_full",
                    "text_full", "styled_full", "code_full", "opts_full"):
            print(f"  {key:12s} {stats[kind][key]:5d} / {t}")
        for what, ns in sorted(bad[kind].items(), key=lambda kv: -len(kv[1]))[:6]:
            sample = ", ".join(paths[n - 1].split("/15.0/")[-1][-48:] for n in ns[:2])
            print(f"  {what}: {len(ns)}   e.g. {sample}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
