# Changelog

All notable changes to wolfram-nb-mode will be documented in this file.

## [Unreleased]

### Added
- Persistent kernel per notebook buffer (see `docs/KERNEL.md`): definitions and
  `%` carry across cells; remote kernels via `wolfram-nb-kernel-command`
- Graphics results come back as a PNG preview plus StandardForm boxes and are
  saved as real `Cell[BoxData[GraphicsBox[...]], "Output"]` cells
- `wolfram-nb-kernel-detach`: kernels run under `setsid -w` and exit by
  themselves when their input closes, so a killed Emacs does not leak a
  licence slot
- Commands `wolfram-nb-kernel-restart` (`C-c C-z`), `wolfram-nb-kernel-quit`
  (`C-c C-q`), `wolfram-nb-kernel-info`
- Tests: `test-kernel.el` (protocol, with a fake kernel), `test-output.el`,
  `test-e2e.el`, and `test-corpus.el` with a generated corpus of 13 notebooks
  in `tests/corpus` (see its README)

### Fixed
Found by running a real Front End notebook and a synthetic corpus through the
mode and having the kernel compare the original with the saved file:
- The Front End's trailing cache comment lists every cell as `Cell[...]`; the
  parser imported those as extra body cells (about as many junk cells as real
  ones), and the notebook options after the cell list, including a docked
  toolbar, were dropped. Only the notebook's own cell list is read now and the
  options are kept as they are
- Box data lost commas, spaces and operators when turned into code
  (`f[x, y]` became `f[xy]`, `Plot[Sin[x],{x,0,6}]` became
  `Plot[Sin[x]{x06}]`). A real converter now handles rows, scripts, fractions,
  roots, grids and typeset sums, products, integrals, derivatives and limits;
  anything it does not know stays verbatim rather than being guessed
- A cell that is not edited is written back exactly as it was read: its boxes,
  options, formatting and `ExpressionUUID`. Only an edited cell is rebuilt
- Cell options that the Front End wraps over several lines ended the one-line
  `#+ATTR_WOLFRAM:` keyword and left stray Text cells
- A `CellLabel` was added again on every save
- `Code` became `Input`, `Print` became `Output`, options on Text cells were
  dropped
- Text with blank lines became several cells, and a line starting with `*`,
  `-`, `1.`, `#` or `|` changed the kind of cell. Such cells are kept in a
  block that Org does not interpret
- `*`, `/` and `_` in plain text were read as formatting; plain URLs became
  `[[links]]`; `\[Dash]`-style character escapes had their backslash doubled
- Rich text: a space inside an italic span stopped it being italic, a trailing
  newline was added on every save, hyperlinks and inline cells were dumped as
  raw Wolfram code (they are now kept as `[wnb:N]` tokens and put back), and
  bold text in a headline lost its formatting
- Nested list items (`Item`, `Subitem`, `Subsubitem`) each repeated the text of
  their sub-items
- Seeded fuzzing (`tests/test-fuzz.el`, about 50,000 generated cells) found
  more ways to lose text, all fixed and pinned in `tests/test-edge.el`:
  - a block whose text began with `,*` or `,#+` lost a comma (Org already
    removes one)
  - a line holding just `*`, `** text`, `:END:` or `#+NAME:` changed the kind of
    cell, or was swallowed by the line before it; Org itself is now asked
    whether text survives as one paragraph or one list item
  - a headline lost a leading `TODO`/`DONE`, a trailing `:tag:`, a `[#A]`
    priority or a `COMMENT` prefix; the whole line is read instead
  - Org objects the converter did not know (subscripts such as `begin_src`,
    footnote references, targets, macros, a trailing `\\`) were dropped
  - text ending in `\>` lost its last character
  - a bracket link was rewritten (`[[a][b]]` became `[[fuzzy:a][b]]`)
  - bold or italic text holding a link or target kept only part of its text
  - a `Title` in the middle of a notebook was moved to the top
  - a `Subitem` with no `Item` before it came back as an `Item`; empty items
    and items with a newline, `foo :: bar` or `[ ]` broke the list; a leading
    `-` or `1.` in an item's text was stripped
  - a cell copied in Org kept its `ExpressionUUID`, giving two cells one id
- A single line of tens of thousands of characters froze Emacs; such cells are
  kept aside like large graphics, and evaluation output is cut to
  `wolfram-nb-max-output-length` and `wolfram-nb-max-output-line-length`
- Saving wrote straight over the notebook, so a failure halfway could
  truncate it; the file is now written beside the notebook and renamed
- Graphics cells (`GraphicsBox`, `FormBox`, ...) were written back as quoted
  strings; they are now kept verbatim
- A cell style could be read from a string inside the box data (a plot's
  `"DefaultMeshStyle"` option became the style); the style is now the second
  top-level argument of `Cell[...]`
- Cell options on BoxData and TextData cells (`ExpressionUUID`, ...) were
  lost because the match data was read after other calls overwrote it
- `wolfram-nb-eval-buffer` used stale positions after the first output was
  inserted
- Second fuzz round (rich text judged by the kernel, mixed notebooks, group
  tests of at least 3000 cases per cell style), all pinned in
  `tests/test-edge.el`:
  - a backslash followed by a character that Org or the file format treats as
    an escape (`\\`, `\"`, `\[`) came back changed; an escaped backslash that
    cannot be told apart from the text after it is marked internally and the
    mark is dropped on write and before evaluation
  - two styled spans that touched (`**a**/b/`) merged or lost their style; a
    zero-width separator now keeps them apart in the cell
  - an inline cell or link next to a URL, a `\begin{...}` or a `=verbatim=`
    string was read as part of the text, leaving a `[wnb:N]` token in the saved
    cell
  - an indented `#+begin_src` in one cell was closed by the `#+end_src` of a
    later cell, swallowing the cells in between
  - evaluation sent a literal `\` + mark to the kernel when a code cell
    contained the internal backslash mark
  - a paragraph starting with `#`, `:word:` at the end of a line, or
    `\begin{` / `\end{` changed the kind of cell
- Found by trying the mode in a GUI Emacs installed with straight:
  - the kernel never started: the bootstrap script `wolfram-nb-kernel-boot.wl`
    was missing from the build directory (only the .el files are linked), the
    error was swallowed, and the kernel waited for input that was never sent
    until the 120 s timeout. The script is now also looked for next to the
    source the library was linked from, and a missing script is an error
    before any process starts
  - a cell with statements on separate lines (`x = 5;` newline `y = 10;`
    newline `x + y`) broke the reply, because the lines came back as three
    values spliced into one list. Lines now run as one sequence and the result
    is the last value
- Wolfram highlighting was applied to the whole buffer, so capitalised words
  in text, headlines and lists were painted as type names and words such as
  "function" as built-ins, while the code blocks themselves were repainted by
  Org and showed no highlighting. It now applies only inside `wolfram` source
  blocks, after Org's own fontification, and matches case-sensitively
- Opening and saving now work like any file (found by going through Dired and
  Evil's `:w` in a headless Emacs on the remote box):
  - a `.nb` opened with `find-file` or from Dired showed the raw
    `Notebook[{...` text, because only `wolfram-nb-open` converted it. The
    conversion now happens when the file is visited
  - saving failed with "No associated .nb file" in that buffer, and with
    "Please specify a file name" under Evil's `:w` in a `wolfram-nb-open`
    buffer, which had no file. Notebook buffers now visit their file, so
    `save-buffer`, `C-x C-s` (no longer bound by the mode), `:w`, `write-file`
    and `revert-buffer` all work, and Emacs does not report the file as changed
    behind its back after a save
  - `wolfram-nb-open` is now `find-file` for a notebook and reuses the buffer
    if the file is already open; `wolfram-nb-create-new` makes a buffer that
    visits the new file
  - the tables that let unedited cells be written back exactly, and the kernel
    of the buffer, survive `normal-mode` and `M-x wolfram-nb-mode`
  - a notebook whose cell list is not closed was shown as an empty buffer that
    a save would then write over the file; it is now an error, the buffer
    stays read-only with the file's text, and saving it is refused
- Results are kept the way org-babel keeps them. Evaluating a block puts the
  output under a `#+RESULTS:` line, and the notebook's own Output and Print
  cells that follow an Input cell are shown under one too. Evaluating the block
  again replaces all of them. Before, only a bare example block right after
  the source block was replaced, so outputs that came with a notebook (they
  carry a `CellLabel` or other options, and `Print` comes as a cell of its own)
  stayed and the new result appeared above them. `wolfram-nb-clear-outputs`
  removes the labels and attributes with the blocks. The label is only a view:
  it is not written to the `.nb`, and a buffer without it still works
- Cell groups survive a visit in Emacs. Saving flattened every `CellGroupData`,
  so a notebook came back without its sections folding, its `Input`/`Output`
  groups or any `Closed` group. The nesting and each group's `Open`/`Closed` is
  now read when the notebook is opened and written back, and a cell is found
  again by its content or, when it was edited, by its `ExpressionUUID` (a cell
  that led a group and was edited keeps leading it). Cells that are new get the
  groups the Front End gives them: an Input with its results becomes a group,
  a heading opens a section group, items group with their sub-items. A notebook
  without any groups stays without. This follows the Front End's own
  `CellGroupingRules`; 1,595 of 1,595 recorded groupings of realistic cell lists
  (`tests/corpus/fe-groups.txt`, made by the Front End) are reproduced, apart
  from consecutive `Print`, `Title` or `Subtitle` cells
- A notebook written by the Front End (`tests/corpus/fe-grouped.nb`, with the
  `CellLabel`, `ExpressionUUID`, cache comments and `OutputFormData` results)
  was not written back unchanged: a `CellLabel` such as `" In[1]:="` lost its
  leading blank, because Org trims the `#+NAME:` it was copied to, and
  `OutputFormData[...]` was saved as a quoted string. Both fixed; the kernel now
  reads the saved file as the same cells and the same groups
- Evaluation results are written the way the Front End writes them. What the
  block printed, each message and the value were one string `Output` cell,
  so a `Print` was glued to the value; they are now a `Print` cell, a
  `Message` cell (`"MSG"`) per message and an `Output` cell, under the one
  `#+RESULTS:` line. The value is saved as typeset `BoxData` (`1/2 + x^2` as a
  fraction and a power, not as a text picture), from the StandardForm boxes
  the kernel returns and keeps for the cell under a new `ExpressionUUID`; if
  the text of the result is edited it is saved as a string cell instead. A
  result over 100,000 characters of boxes stays a string. Checked by opening
  the saved files in the Front End: it reads a notebook saved by Emacs as
  the same cells and groups as the original (`tests/corpus/fe-reads.wls`), and
  an evaluated notebook as Section > Input, Print, Message, Output
- Two more losses found by round-tripping a real 9.6 MB, 107-cell notebook with
  33 cell groups, 19 graphics and real options (opens in 3.8 s, saves in 2 s):
  - the Front End wraps long strings with a backslash and a newline, which
    splits an `ExpressionUUID`; a cell whose UUID was wrapped was not found
    again and its boxes were rewritten as a string. The wrap is ignored when
    reading a UUID. The kernel now reads the saved file as exactly the same
    cells, options and groups, and the Front End as the same notebook
  - a plain text cell holding Markdown-like lines (`* Cover *all* reports.`,
    `_quirks_`), once edited, came back with bold and underlined words: Org
    reads such lines as headlines, where it sees no markup, so the cell took
    the rich-text path. A plain string now never does
- Cells the parser could not turn into an Org cell and back were dropped or
  rewritten, with no message: a cell with no style (`Cell[BoxData[...]]`,
  `Cell["text"]`, or only options after the content) was dropped or given a
  style, top-level `DynamicModuleBox` content became the text
  `[Dynamic content]`, and `Cell[Sin[x], "Input"]` became the string
  `"Sin[x]"`. Such a cell is now kept as the whole cell it was, shown in a raw
  block (the cell itself when short, a description when large) that can be
  edited, and opening the notebook says which cells they are:
  `Opened n.nb (13 cells); 6 cells kept as they are: cell 2 (it has no style), ...`.
  The kernel and the Front End read the saved file as the same cells
- Errors say where: an unclosed cell list gives the line the notebook starts
  on; an evaluation error names the block by its line; evaluating a whole buffer
  lists the lines of the blocks that failed instead of only counting them
- A new notebook is saved with cell groups. One made with
  `wolfram-nb-create-new`, one visited at a path that does not exist yet, and an
  empty file get the groups the Front End would make (sections nested by level,
  an Input with its results, items with sub-items); before they were saved flat.
  A notebook opened from a file that has no groups is still written without, so
  an unedited flat file comes back as it was. The Front End's own grouping of the
  same cells equals ours on the notebooks checked, items and a Print result
  included
- Evaluated cells are labelled `In[n]:=` and `Out[n]=`, from the `$Line` the kernel
  now reports (the third field of `DONE`). A new kernel starts at `In[1]`, and a
  plot is `Out[n]=` like any other value. Evaluating again moves the labels
- Edited text is written with the forms that work in Mathematica. The default
  stylesheet defines no style named `"Bold"`, `"Italic"`, `"Underlined"` or
  `"Courier"`, so the `StyleBox[x, "Bold"]` written before showed nothing; it is
  now `FontWeight->Bold`, `FontSlant->Italic`, `FontVariations->{"Underline"->True}`
  and `FontFamily->"Courier"`, which is what the Front End writes. Every form is
  read, including several at once. What Org cannot show, such as a colour or a
  size on a span, is kept while that text is not edited
- A saved notebook starts with the Front End's Content-type and magic comments
  (`wolfram-nb-write-header`); the cache information, whose byte offsets must be
  exact, is not written
- A result whose boxes hold dynamic content (a `Manipulate`, an `Animate`) is always
  saved as boxes, whatever its size, so it stays interactive
- `tests/real/` runs every notebook of a list through the mode and has the kernel judge
  the saved copy; the Wolfram Engine's own 1,030 notebooks are the corpus, and
  all of them come back with the same cells, groups and options
- Starting a kernel whose program is not there signals `wolfram-nb-kernel-error`
  on every Emacs; Emacs 28.2 (the CI version) starts such a process and reports
  an exit status later, which the first run of the suite on 28.2 showed
- A cell group whose state is an expression over several lines (`Dynamic[...]`)
  keeps it; it was read as `Open`
- Dropping a repeated `ExpressionUUID` from the middle of a cell's options keeps
  the comma between the others, and `$CellContext`ExpressionUUID` is not taken
  for the identifier
- Known limits: trailing blanks of an edited headline are trimmed; literal
  markup in a plain-string headline is read as formatting once the cell is
  edited; a colour or size on a span is dropped once the text of that span is
  edited; a tab after an Org object becomes a space

### Changed
- Reorganized repository structure following Emacs package best practices
  - Tests moved to `tests/` directory
  - Documentation moved to `docs/` directory
  - Examples moved to `examples/` directory
- Simplified README for clarity
- Consolidated redundant documentation files
- Added .gitignore and CONTRIBUTING.md

## [0.3.0] - 2025-12-16

### Added
- **CellGroupData Unwrapping**: Recursive extraction of cells from CellGroupData structures
  - Automatically unwraps nested cell groups (Chapters, Sections, etc.)
  - Maintains document hierarchy while extracting content
  - Successfully tested with 42,653-line production notebook
- **Title Support**: `Cell["text", "Title"]` → `#+TITLE: text`
- **Chapter Support**: `Cell["text", "Chapter"]` → `* text`
- **Subitem Support**: Proper indentation for Subitem and Subsubitem cells
- **Improved BoxData Detection**: Better regex to avoid false matches
- **DynamicModuleBox Detection**: Identifies and marks dynamic content

### Changed
- Enhanced `wolfram-nb--parse-cell` with better pattern matching
- Cell style validation: Only accepts styles starting with capital letter
- Recursive cell extraction for nested structures

### Fixed
- False positive matches on BoxData internal structure
- Parser now correctly identifies 20+ cell types
- Eliminates spurious cells with styles like ",", "]", "}"

### Performance
- Parses 644 cells from complex notebook in ~9 seconds (69 cells/sec)
- Successfully handles notebooks with thousands of cells

### Testing
- New test: `test-cellgroupdata.el` - Comprehensive CellGroupData tests
- Verified with real production notebook (JuanWeeklyReports.nb)
- All existing tests still passing

## [0.2.0] - 2025-12-16

### Added
- **Code Evaluation**: Evaluate Wolfram Language code using wolframscript
  - `wolfram-nb-eval-block` (C-c C-c) - Evaluate current source block
  - `wolfram-nb-eval-buffer` (C-c C-b) - Evaluate all blocks in buffer
  - `wolfram-nb-clear-outputs` (C-c C-k) - Clear all output blocks
- **Input/Output Support**: Proper handling of Input and Output cell pairs
- **Output Formatting**: Automatic formatting of evaluation results
- **Graphics Detection**: Placeholder for graphics output with instructions
- **Error Handling**: Graceful handling of evaluation errors
- **Configuration**: 
  - `wolfram-nb-wolframscript-path` - Path to wolframscript
  - `wolfram-nb-eval-timeout` - Evaluation timeout in seconds
- **Test Suite**: Comprehensive evaluation tests (test-eval.el)
- **Documentation**: Complete evaluation guide (EVALUATION.md)
- **Examples**: eval-demo.nb with Input/Output examples

### Changed
- **Key Binding**: C-c C-c now evaluates block (was reparse)
- **Key Binding**: C-c C-r now reparses buffer (was C-c C-c)
- Updated README with evaluation features
- Updated QUICKREF with new commands

## [0.1.0] - 2025-12-16

### Added
- Initial release of wolfram-nb-mode
- Parse Wolfram Notebook (.nb) files into org-mode representation
- Convert org-mode buffers back to Notebook format
- Support for standard cell types:
  - Section, Subsection, Subsubsection (from org headlines)
  - Text (from org paragraphs)
  - Item (from org list items)
  - Code/Input (from org source blocks)
  - Output (from org example blocks)
- Interactive commands:
  - `wolfram-nb-open` - Open a .nb file
  - `wolfram-nb-create-new` - Create a new notebook
  - `wolfram-nb-save` - Save changes back to .nb format
  - `wolfram-nb-reparse` - Reparse buffer contents
  - `wolfram-nb-view-cells` - View raw Cell structures
- Proper string escaping/unescaping for Mathematica format
- Bidirectional conversion preserves content structure
- Comprehensive test suite
- Documentation and examples

### Features
- Edit notebooks using familiar org-mode syntax
- Automatic conversion on save
- Live preview of Cell structures
- Preserves code formatting and structure
- Compatible with Mathematica and Wolfram Desktop

### Known Limitations
- Dynamic content (Dynamic[], Manipulate[]) preserved as code but not interactive
- Graphics not rendered in Emacs view
- Complex cell metadata not preserved
- Best suited for static, text-heavy documents

## Future Plans

### Potential Features for Future Releases
- Better handling of cell options and metadata
- Support for more cell types
- Integration with wolfram-mode for syntax highlighting
- Automatic formatting and prettification
- Support for notebook-level metadata
- Export to other formats via org-export
- Improved parsing of complex nested structures
