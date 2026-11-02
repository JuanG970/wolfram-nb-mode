# wolfram-nb-mode

Edit Wolfram Language Notebooks (.nb files) in Emacs using org-mode syntax.

## Overview

`wolfram-nb-mode` translates Wolfram Mathematica notebooks into org-mode format for editing in Emacs. Changes are automatically saved back to native `.nb` format.

## Features

- **Org-mode Interface** - Edit using familiar syntax (headlines, lists, code blocks)
- **CellGroupData Support** - Handles nested structures (Chapters, Sections)  
- **Multiple Cell Types** - Title, Section, Subsection, Text, Item, Code, Input, Output
- **Code Evaluation** - Execute Wolfram Language via wolframscript
- **Production Ready** - Tested with 600+ cells, 42,000+ lines
- **Bidirectional** - Preserves structure on save

## Installation

```elisp
(add-to-list 'load-path "/path/to/wolfram-nb-mode")
(require 'wolfram-nb-mode)
```

## Quick Start

```elisp
;; Open a notebook
M-x wolfram-nb-open RET notebook.nb RET

;; Edit as org-mode, then save
C-x C-s
```

## Usage

### Key Bindings

- `C-x C-s` - Save to .nb format
- `C-c C-c` - Evaluate code block
- `C-c C-b` - Evaluate all blocks
- `C-c C-k` - Clear outputs
- `C-c C-r` - Reparse buffer
- `C-c C-v` - View raw cells

### Editing

```org
* Section

This is text.

** Subsection

- List item
- Another item

#+begin_src wolfram
Plot[x^2, {x, -5, 5}]
#+end_src
```

### Cell Mapping

| Org          | Wolfram Cell   |
|--------------|----------------|
| `* Heading`  | `"Section"`    |
| `** Heading` | `"Subsection"` |
| Paragraph    | `"Text"`       |
| List item    | `"Item"`       |
| Source block | `"Code"`       |

## Examples

See [examples/](examples/) directory for sample notebooks.

## Testing

```bash
cd tests/
./test-all.sh
```

See [docs/TESTING.md](docs/TESTING.md) for details.

## Documentation

- [CHANGELOG](docs/CHANGELOG.md) - Version history
- [TESTING](docs/TESTING.md) - Test suite guide

## Limitations

- Static content focus (text, code, structure)
- Dynamic/Manipulate preserved but not rendered
- Graphics output not displayed in Emacs

## Requirements

- Emacs 26.1+
- org-mode
- wolframscript (optional, for code evaluation)

## Related

- [ox-mathematica](https://github.com/juang970/ox-mathematica) - Export org to Mathematica

## License

MIT License

## Author

Juan Gonzalez <juan.angel19@hotmail.com>
