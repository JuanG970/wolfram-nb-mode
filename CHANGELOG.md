# Changelog

All notable changes to wolfram-nb-mode will be documented in this file.

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
