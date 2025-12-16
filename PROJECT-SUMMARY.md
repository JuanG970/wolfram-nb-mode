# wolfram-nb-mode - Project Summary

## What is wolfram-nb-mode?

`wolfram-nb-mode` is an Emacs major mode that allows you to edit Wolfram Language Notebook (.nb) files using a familiar org-mode interface. It provides bidirectional conversion between the Cell[...] structure of Wolfram Notebooks and org-mode syntax.

## Core Features

### 1. Parse Wolfram Notebooks
- Reads `.nb` files with `Notebook[{...}]` structure
- Extracts individual `Cell[content, style]` elements
- Handles string escaping (quotes, backslashes, newlines)
- Properly parses nested brackets

### 2. Convert to Org-mode
- Section → `* Heading`
- Subsection → `** Heading`
- Text → Paragraphs
- Item → `- List item`
- Code → `#+begin_src wolfram ... #+end_src`
- Output → `#+begin_example ... #+end_example`

### 3. Edit in Org-mode
- Full org-mode functionality (folding, navigation, etc.)
- Familiar keybindings
- Plain text editing
- Version control friendly

### 4. Save Back to Notebook Format
- Converts org structure back to Cell[...] format
- Proper string escaping for Mathematica
- Maintains notebook structure
- Can be opened in Mathematica/Wolfram Desktop

## Architecture

```
┌─────────────┐
│   .nb File  │
│  Notebook[] │
└──────┬──────┘
       │ Parse
       ↓
┌─────────────┐
│ Cell Plist  │
│ :content    │
│ :style      │
└──────┬──────┘
       │ Convert
       ↓
┌─────────────┐
│  Org Buffer │
│ * Section   │
│ - Items     │
│ #+src       │
└──────┬──────┘
       │ Edit
       ↓
┌─────────────┐
│  Org Text   │
└──────┬──────┘
       │ Parse
       ↓
┌─────────────┐
│Cell Strings │
│Cell[".."]   │
└──────┬──────┘
       │ Assemble
       ↓
┌─────────────┐
│  .nb File   │
│ Notebook[]  │
└─────────────┘
```

## Implementation Details

### Key Functions

**Parsing:**
- `wolfram-nb--parse-notebook` - Main parser for .nb files
- `wolfram-nb--parse-cell` - Parses individual Cell[...] structures
- `wolfram-nb--find-cell-end` - Finds matching brackets
- `wolfram-nb--unescape-string` - Converts Mathematica escapes to actual characters

**Conversion to Org:**
- `wolfram-nb--cell-to-org` - Converts one cell to org text
- `wolfram-nb--cells-to-org` - Converts list of cells to org buffer

**Conversion from Org:**
- `wolfram-nb--org-to-cells` - Parses org-mode tree into Cell structures
- `wolfram-nb--make-cell` - Creates a Cell[...] string
- `wolfram-nb--cells-to-notebook` - Assembles Notebook[...] wrapper
- `wolfram-nb--escape-string` - Escapes strings for Mathematica

**Interactive Commands:**
- `wolfram-nb-open` - Open a notebook file
- `wolfram-nb-create-new` - Create new notebook
- `wolfram-nb-save` - Save changes (bound to C-x C-s)
- `wolfram-nb-reparse` - Reparse current buffer
- `wolfram-nb-view-cells` - View raw Cell structures

### String Handling

Special care taken for proper escaping/unescaping:
- `\` → `\\`
- `"` → `\"`
- newline → `\n`

Order matters: escape backslashes first, unescape them last.

### Buffer-local Variables

- `wolfram-nb--cells` - Parsed cell structures
- `wolfram-nb--original-file` - Source .nb file path
- `wolfram-nb--modified` - Modification flag

## Files in this Repository

| File | Purpose |
|------|---------|
| `wolfram-nb-mode.el` | Main mode implementation (382 lines) |
| `test-mode.el` | Unit tests for core functions |
| `integration-test.el` | Full workflow integration test |
| `demo.el` | Interactive demonstration |
| `test.nb` | Simple test notebook |
| `example.nb` | Comprehensive example notebook |
| `README.md` | Project overview and quick start |
| `USAGE.md` | Detailed usage instructions |
| `INSTALL.md` | Installation guide |
| `QUICKREF.md` | Quick reference card |
| `CHANGELOG.md` | Version history |
| `PROJECT-SUMMARY.md` | This file |

## Design Decisions

### Why Org-mode?

1. **Familiar**: Most Emacs users know org-mode
2. **Powerful**: Rich editing features, folding, navigation
3. **Plain text**: Easy to understand and version control
4. **Extensible**: Can use org-mode features

### What's Preserved?

- Document structure (sections, subsections)
- Text content
- Code blocks with proper formatting
- List items
- Cell types (Section, Text, Code, etc.)

### What's Not Preserved?

- Graphics and rendered output
- Interactive widgets (Dynamic, Manipulate)
- Complex cell metadata
- Rich text formatting within cells
- Cell grouping and nesting (beyond basic structure)

### Why These Limitations?

The mode is designed for **static document editing**:
- Writing documentation
- Creating tutorial notebooks
- Editing code and explanations
- Version controlling notebooks

For dynamic content, use Mathematica directly.

## Testing

### Test Suite

1. **test-mode.el**: Unit tests
   - String escaping/unescaping
   - Cell parsing
   - Org conversion
   - Roundtrip conversion

2. **integration-test.el**: Full workflow
   - Create notebook
   - Read back
   - Modify
   - Verify format

### Running Tests

```bash
# Unit tests
emacs --batch -l test-mode.el

# Integration tests
emacs --batch -l integration-test.el

# Demo
emacs -l demo.el
```

## Use Cases

### Ideal For:

- **Documentation**: Write Wolfram documentation in Emacs
- **Tutorials**: Create tutorial notebooks with code and explanations
- **Notes**: Mathematical notes with code examples
- **Version Control**: Track notebook changes in Git
- **Batch Editing**: Make systematic changes to notebooks
- **Structure**: Focus on document structure and content

### Not Ideal For:

- **Interactive Development**: Use Mathematica REPL
- **Graphics Creation**: Need visual feedback
- **Dynamic Content**: Requires Mathematica frontend
- **Complex Notebooks**: With lots of metadata

## Future Enhancements

Potential improvements:
- Support for more cell types
- Better metadata preservation
- Integration with wolfram-mode
- Export via org-export
- Improved parsing of complex structures
- Support for cell options
- Notebook-level metadata
- Better error handling

## Related Work

- **ox-mathematica**: Exports org-mode to Wolfram Notebooks (inspiration for this project)
- **wolfram-mode**: Syntax highlighting and editing for Wolfram Language
- **ob-wolfram**: Org-babel integration for Wolfram Language

## Development

### Contributing

Contributions welcome! Areas for improvement:
- More cell types
- Better parsing
- More tests
- Documentation
- Examples

### Code Style

- Lexical binding enabled
- Docstrings for all functions
- Descriptive variable names
- Comments for complex logic
- Following Emacs Lisp conventions

## License

MIT License - Free to use, modify, and distribute.

## Author

Juan Gonzalez <juan.angel19@hotmail.com>

Created: December 2025
Version: 0.1.0

## Acknowledgments

- Inspired by ox-mathematica
- Built on org-mode
- Thanks to the Emacs and Wolfram communities
