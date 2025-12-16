# wolfram-nb-mode

An Emacs major mode for editing Wolfram Language Notebook (.nb) files using an org-mode interface.

## Overview

`wolfram-nb-mode` provides a seamless way to edit Wolfram Notebook files in Emacs by translating the `Cell[...]` structure into familiar org-mode syntax. The mode maintains the backend Cell structure, allowing you to save changes back to proper `.nb` format that can be opened in Mathematica or Wolfram Desktop.

## Features

- **Org-mode Interface**: Edit notebooks using org-mode syntax (headlines, lists, code blocks)
- **CellGroupData Support**: Automatically unwraps nested cell groups (Chapters, Sections)
- **Cell Mapping**: Maintains bidirectional mapping between org elements and Cell structures
- **Multiple Cell Types**: Supports Title, Chapter, Section, Subsection, Text, Item, Code/Input, and Output cells
- **Code Evaluation**: Evaluate Wolfram Language code using wolframscript
- **Input/Output Pairs**: Automatic output insertion after code evaluation
- **Complex Notebooks**: Tested with 42,000+ line production notebooks
- **Transparent Saving**: Saves changes back to `.nb` format automatically
- **Live Preview**: View the raw Cell structures at any time

## Installation

1. Clone or download this repository:
   ```bash
   git clone https://github.com/juang970/wolfram-nb-mode.git
   ```

2. Add to your Emacs configuration:
   ```elisp
   (add-to-list 'load-path "/path/to/wolfram-nb-mode")
   (require 'wolfram-nb-mode)
   ```

3. Optionally, enable auto-loading for .nb files:
   ```elisp
   (setq wolfram-nb-auto-save t)
   ```

## Usage

### Opening Notebooks

```elisp
M-x wolfram-nb-open RET /path/to/notebook.nb RET
```

Or, if auto-mode is enabled, simply open a `.nb` file.

### Creating New Notebooks

```elisp
M-x wolfram-nb-create-new RET /path/to/new-notebook.nb RET
```

### Editing

Edit the buffer as you would edit any org-mode file:

- Use `*`, `**`, `***` for Section, Subsection, Subsubsection
- Write plain text as paragraphs
- Use `-` for bullet lists (Item cells)
- Use `#+begin_src wolfram ... #+end_src` for code (Code/Input cells)
- Use `#+begin_example ... #+end_example` for output

### Key Bindings

- `C-x C-s` - Save changes back to `.nb` format
- `C-c C-c` - Evaluate current source block (requires wolframscript)
- `C-c C-b` - Evaluate all source blocks in buffer
- `C-c C-k` - Clear all output blocks
- `C-c C-r` - Reparse buffer to update cell mappings
- `C-c C-v` - View raw Cell structures

## Cell Type Mapping

| Org Element | Wolfram Cell Type |
|-------------|-------------------|
| `* Heading` | `Cell[..., "Section"]` |
| `** Heading` | `Cell[..., "Subsection"]` |
| `*** Heading` | `Cell[..., "Subsubsection"]` |
| Paragraph | `Cell[..., "Text"]` |
| List item | `Cell[..., "Item"]` |
| Source block | `Cell[..., "Code"]` |
| Example block | `Cell[..., "Output"]` |

## Example

### Org-mode representation:
```org
* Introduction

This is a sample notebook.

** Getting Started

Here are some key points:
- Easy to edit
- Familiar org syntax
- Seamless conversion

** Example Code

#+begin_src wolfram
f[x_] := x^2 + 1
Plot[f[x], {x, -5, 5}]
#+end_src
```

### Saved as .nb file:
```mathematica
Notebook[{
Cell["Introduction", "Section"],
Cell["This is a sample notebook.", "Text"],
Cell["Getting Started", "Subsection"],
Cell["Here are some key points:", "Text"],
Cell["Easy to edit", "Item"],
Cell["Familiar org syntax", "Item"],
Cell["Seamless conversion", "Item"],
Cell["Example Code", "Subsection"],
Cell["f[x_] := x^2 + 1\nPlot[f[x], {x, -5, 5}]", "Code"]
}]
```

## Limitations

- **Static Content Focus**: This mode is designed for static documents (text, code, structure)
- **Dynamic Content**: `Dynamic[]`, `Manipulate[]`, and interactive elements are preserved as code but not rendered
- **Complex Cells**: Cells with complex options or special formatting may lose some metadata
- **Graphics**: Output graphics are not displayed (consider this a pure text editor)

## Configuration

```elisp
;; Indentation level for nested structures
(setq wolfram-nb-indent-level 2)

;; Auto-parse .nb files on open
(setq wolfram-nb-auto-save t)
```

## Compatibility

- Tested with Emacs 26.1+
- Requires org-mode
- Works with Wolfram Mathematica and Wolfram Desktop notebooks

## Related Projects

- [ox-mathematica](https://github.com/juang970/ox-mathematica) - Export org-mode documents to Mathematica notebooks

## License

MIT License

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## Author

Juan Gonzalez <juan.angel19@hotmail.com>
