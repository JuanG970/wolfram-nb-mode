# Real notebooks

`roundtrip.el`, `compare.wls` and `summary.py` run every notebook of a list
through the mode and ask the kernel whether the saved copy means the same.
The Wolfram Engine ships about a thousand notebooks written by the Front End
(stylesheets, palettes, component notebooks), which makes a corpus nobody
here had to invent.

They are Wolfram's files, so they are not stored here, only the runner:

    D=/usr/local/Wolfram/WolframEngine/15.0      # $InstallationDirectory
    find $D -name '*.nb' -size +0 | sort > /tmp/rt/list.txt
    cd tests
    emacs --batch -Q -L .. -L . -l real/roundtrip.el /tmp/rt/list.txt /tmp/rt > /tmp/rt/emacs.log
    wolframscript -file real/compare.wls /tmp/rt/list.txt /tmp/rt > /tmp/rt/compare.log
    python3 real/summary.py /tmp/rt/list.txt /tmp/rt

It takes about 45 minutes. Run it on a machine you can leave alone; the
largest notebooks are 20 MB.

To use several cores, give each Emacs a range of the list (`FIRST LAST`, the
numbers stay those of the list) and join the logs before `summary.py`:

    emacs --batch -Q -L .. -L . -l real/roundtrip.el /tmp/rt/list.txt /tmp/rt 1 400 > /tmp/rt/emacs-1.log
    emacs --batch -Q -L .. -L . -l real/roundtrip.el /tmp/rt/list.txt /tmp/rt 401 800 > /tmp/rt/emacs-2.log
    cat /tmp/rt/emacs-*.log > /tmp/rt/emacs.log

## Results

Wolfram Engine 15.0, 1,030 notebooks, 2026-10-30. Only counts are kept here.

Cells left as they were (a notebook opened and saved):

| check | notebooks |
|---|---|
| processed without an error | 1030 / 1030 |
| cells identical to the original, as the kernel reads both | 1030 / 1030 |
| cell groups and their Open / Closed state | 1030 / 1030 |
| notebook options | 1030 / 1030 |

Every cell converted as if it had been edited, which is far harder than an
edit of one cell: 477 notebooks come back with identical cells, 986 with the
same groups, 1019 with the same formatting of their text. The difference is
almost all in cells that Org cannot show (cached graphics, interactive
boxes, custom styles) or in a result cell that lost its place in its group.

