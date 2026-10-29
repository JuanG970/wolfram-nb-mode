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
  raw Wolfram code (they are now kept as `⟦wnb:N⟧` tokens and put back), and
  bold text in a headline lost its formatting
- Nested list items (`Item`, `Subitem`, `Subsubitem`) each repeated the text of
  their sub-items
- Graphics cells (`GraphicsBox`, `FormBox`, ...) were written back as quoted
  strings; they are now kept verbatim
- A cell style could be read from a string inside the box data (a plot's
  `"DefaultMeshStyle"` option became the style); the style is now the second
  top-level argument of `Cell[...]`
- Cell options on BoxData and TextData cells (`ExpressionUUID`, ...) were
  lost because the match data was read after other calls overwrote it
- `wolfram-nb-eval-buffer` used stale positions after the first output was
  inserted

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
