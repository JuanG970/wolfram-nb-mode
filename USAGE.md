# Wolfram Notebook Mode - Usage Guide

## Quick Start

### Installation

```elisp
;; Add to your ~/.emacs or ~/.emacs.d/init.el
(add-to-list 'load-path "/path/to/wolfram-nb-mode")
(require 'wolfram-nb-mode)
```

### Opening a Notebook

There are two ways to open a `.nb` file:

**Method 1: Manual open**
```
M-x wolfram-nb-open RET /path/to/notebook.nb RET
```

**Method 2: Auto-open (if enabled)**
```elisp
;; Enable automatic opening of .nb files
(setq wolfram-nb-auto-save t)

;; Then just open any .nb file normally
C-x C-f notebook.nb RET
```

### Creating a New Notebook

```
M-x wolfram-nb-create-new RET /path/to/new-notebook.nb RET
```

## Editing

Once opened, the notebook appears as an org-mode buffer. Edit it like any org file:

### Sections and Headings

```org
* Section Title          → Cell["Section Title", "Section"]
** Subsection Title      → Cell["Subsection Title", "Subsection"]
*** Subsubsection Title  → Cell["Subsubsection Title", "Subsubsection"]
```

### Text Paragraphs

```org
This is a regular paragraph of text.

This will be another paragraph.
```

Each paragraph becomes a `Cell[..., "Text"]`.

### Lists

```org
- First item
- Second item
- Third item
```

Each item becomes a `Cell[..., "Item"]`.

### Code Blocks

```org
#+begin_src wolfram
f[x_] := x^2 + 1
Plot[f[x], {x, -5, 5}]
#+end_src
```

Becomes `Cell["f[x_] := x^2 + 1\nPlot[f[x], {x, -5, 5}]", "Code"]`.

### Output/Examples

```org
#+begin_example
Result: 42
#+end_example
```

Becomes `Cell["Result: 42", "Output"]`.

## Key Bindings

| Key       | Command                | Description                          |
|-----------|------------------------|--------------------------------------|
| `C-x C-s` | `wolfram-nb-save`      | Save buffer back to .nb format       |
| `C-c C-c` | `wolfram-nb-reparse`   | Reparse buffer (update cell mapping) |
| `C-c C-v` | `wolfram-nb-view-cells`| View raw Cell structures             |

## Complete Example

### Org-mode Buffer

```org
* My Notebook

This is an introduction to my notebook.

** Mathematical Definitions

Let's define some functions:

#+begin_src wolfram
square[x_] := x^2
cube[x_] := x^3
#+end_src

** Testing

Here are some tests:

- Test square function
- Test cube function
- Verify results

** Results

#+begin_src wolfram
square[5]
cube[3]
#+end_src

* Conclusion

This notebook demonstrates basic functionality.
```

### Saved .nb File

```mathematica
Notebook[{
Cell["My Notebook", "Section"],
Cell["This is an introduction to my notebook.", "Text"],
Cell["Mathematical Definitions", "Subsection"],
Cell["Let's define some functions:", "Text"],
Cell["square[x_] := x^2\ncube[x_] := x^3", "Code"],
Cell["Testing", "Subsection"],
Cell["Here are some tests:", "Text"],
Cell["Test square function", "Item"],
Cell["Test cube function", "Item"],
Cell["Verify results", "Item"],
Cell["Results", "Subsection"],
Cell["square[5]\ncube[3]", "Code"],
Cell["Conclusion", "Section"],
Cell["This notebook demonstrates basic functionality.", "Text"]
}]
```

## Workflow Tips

### 1. Version Control

Since `.nb` files are text-based (when using this mode), you can version control them with Git:

```bash
git add mynotebook.nb
git commit -m "Updated mathematical definitions"
```

### 2. Editing in Emacs

The workflow is:
1. Open `.nb` file → automatically converted to org-mode
2. Edit using familiar org-mode commands
3. Save with `C-x C-s` → automatically converted back to `.nb`
4. Open in Mathematica/Wolfram Desktop to execute code

### 3. Org-mode Features

You can use standard org-mode features:
- `TAB` to fold/unfold sections
- `M-RET` to create new items
- `C-c C-t` for TODO items (though these won't be preserved in .nb)
- Org export features (though saving will use .nb format)

### 4. Code Editing

For better Wolfram Language syntax highlighting in code blocks:

```elisp
;; If you have wolfram-mode installed
(setq org-src-lang-modes
      '(("wolfram" . wolfram)))
```

## Limitations

### Not Supported

- **Graphics**: Rendered graphics won't appear in the org view
- **Dynamic Content**: `Dynamic[]`, `Manipulate[]` are preserved as code but not interactive
- **Cell Metadata**: Advanced cell options/metadata are not preserved
- **Complex Styling**: Rich text formatting within cells is limited

### Workarounds

- **For Dynamic Content**: Edit structure in Emacs, add dynamic content in Mathematica
- **For Graphics**: Use code cells for plotting commands, view outputs in Mathematica
- **For Metadata**: This mode is best for static, text-heavy documents

## Troubleshooting

### Problem: "Not a valid Notebook file"

**Solution**: Make sure the file contains `Notebook[{...}]` structure. The mode expects standard Mathematica notebook format.

### Problem: Content looks garbled

**Solution**: 
1. Press `C-c C-c` to reparse the buffer
2. Check if the original `.nb` file has proper Cell structures
3. Some complex notebooks may not parse correctly

### Problem: Changes not saving

**Solution**:
1. Check that `wolfram-nb--original-file` is set: `C-h v wolfram-nb--original-file`
2. Ensure you have write permissions to the file
3. Try `M-x wolfram-nb-save` explicitly

### Problem: Lost content after round-trip

**Solution**: This mode is designed for simple, static notebooks. Complex features may be lost. Always keep backups when first using the mode.

## Advanced Configuration

```elisp
;; Customize indentation
(setq wolfram-nb-indent-level 2)

;; Enable/disable auto-saving
(setq wolfram-nb-auto-save t)

;; Add hook for additional setup
(add-hook 'wolfram-nb-mode-hook
          (lambda ()
            (visual-line-mode 1)
            (setq fill-column 80)))
```

## Examples

See the included example files:
- `test.nb` - Simple test notebook
- `example.nb` - More comprehensive example
- `demo.el` - Interactive demonstration script

## Getting Help

For issues or questions:
1. Check this usage guide
2. Read the README.md
3. Examine the source code comments
4. File an issue on GitHub

## Tips

1. **Start Simple**: Begin with basic text and code cells
2. **Test Roundtrips**: Open → Edit → Save → Reopen to verify
3. **Use Version Control**: Track changes to your notebooks
4. **Combine Tools**: Edit structure in Emacs, execute in Mathematica
5. **Keep Backups**: Especially when working with important notebooks
