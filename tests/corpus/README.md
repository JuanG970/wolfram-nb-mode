# Notebook corpus

Synthetic notebooks for `tests/test-corpus.el`. They are made by
`generate.wls` with a real kernel, so the boxes have the shapes the Front End
writes, and each file has the Front End's header and its trailing cache
comment (which lists look-alikes of `Cell[...]`).

| File | What it covers |
|---|---|
| `structure.nb` | every cell style, three levels of `CellGroupData`, nested list items, unusual styles |
| `richtext.nb` | styled text, hyperlinks, inline cells, named characters, blank lines, text that looks like Org syntax, literal `*` and `/` |
| `code.nb` | 40 code cells from `MakeBoxes`: fractions, powers, sums, integrals, derivatives, limits, strings, rules, multi-statement cells |
| `graphics.nb` | plots, 3D graphics, images, tables, quantities, dynamic and raster boxes |
| `options.nb` | multi-line cell options, tags, labels, notebook options with `TaggingRules` and a docked toolbar |
| `unicode.nb`, `unicode-raw.nb` | escaped and raw UTF-8 characters |
| `edge.nb`, `empty.nb`, `options-only.nb` | empty groups, odd styles, no cells, only options |
| `eval-*.nb` | notebooks the tests evaluate: state, errors, graphics |

`manifest.txt` has the true number of cells and notebook options of each
file, written by the generator, so the tests do not depend on the parser they
test. `compare.wl` loads two notebook files and compares them as Wolfram
expressions.

To regenerate (deterministic for one Wolfram Language version):

    wolframscript -file tests/corpus/generate.wls

`graphics-large.nb` (about 900 KB) is generated the same way but not stored.
