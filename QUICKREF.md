# wolfram-nb-mode Quick Reference

## Installation

```elisp
(add-to-list 'load-path "/path/to/wolfram-nb-mode")
(require 'wolfram-nb-mode)
(setq wolfram-nb-auto-save t)  ; Optional: auto-open .nb files
```

## Commands

| Command | Key | Description |
|---------|-----|-------------|
| `wolfram-nb-open` | - | Open a .nb file |
| `wolfram-nb-create-new` | - | Create new notebook |
| `wolfram-nb-save` | `C-x C-s` | Save to .nb format |
| `wolfram-nb-reparse` | `C-c C-c` | Reparse buffer |
| `wolfram-nb-view-cells` | `C-c C-v` | View raw cells |

## Syntax Mapping

| Org Syntax | Cell Type | Example |
|------------|-----------|---------|
| `* Title` | Section | `Cell["Title", "Section"]` |
| `** Title` | Subsection | `Cell["Title", "Subsection"]` |
| `*** Title` | Subsubsection | `Cell["Title", "Subsubsection"]` |
| Text paragraph | Text | `Cell["text", "Text"]` |
| `- Item` | Item | `Cell["Item", "Item"]` |
| `#+begin_src wolfram` | Code | `Cell["code", "Code"]` |
| `#+begin_example` | Output | `Cell["output", "Output"]` |

## Example Workflow

```org
* My Notebook

This is some text.

** Math Section

#+begin_src wolfram
f[x_] := x^2
Plot[f[x], {x, 0, 10}]
#+end_src

** Summary

Key points:
- Point one
- Point two
```

## Tips

1. **Use org-mode features**: Folding (`TAB`), navigation, etc.
2. **Save often**: `C-x C-s` converts and saves
3. **Preview cells**: `C-c C-v` shows raw Cell structures
4. **Version control**: .nb files are text, use git
5. **Test roundtrips**: Open → Edit → Save → Verify

## Variables

```elisp
wolfram-nb-indent-level      ; Indentation (default: 2)
wolfram-nb-auto-save          ; Auto-open .nb files (default: t)
wolfram-nb--original-file     ; Buffer-local: source file
wolfram-nb--cells             ; Buffer-local: parsed cells
```

## Limitations

- No interactive widgets (Dynamic, Manipulate)
- No graphics rendering
- Complex cell options not preserved
- Best for static documents

## Common Issues

**"Not a valid Notebook file"**
→ File must contain `Notebook[{...}]`

**Content looks wrong**
→ Try `C-c C-c` to reparse

**Can't save**
→ Check `wolfram-nb--original-file` is set

## See Also

- [README.md](README.md) - Overview
- [USAGE.md](USAGE.md) - Detailed usage
- [INSTALL.md](INSTALL.md) - Installation guide
- [CHANGELOG.md](CHANGELOG.md) - Version history
