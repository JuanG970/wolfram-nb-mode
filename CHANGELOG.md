# Changelog

All notable changes to wolfram-nb-mode will be documented in this file.

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
