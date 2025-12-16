# wolfram-nb-mode v0.2.0 - Evaluation Features

## What's New

Version 0.2.0 adds **code evaluation** capabilities, allowing you to execute Wolfram Language code directly from Emacs and see results inline.

## Major Features Added

### 1. Code Evaluation Engine

Execute Wolfram Language code using wolframscript:

```org
#+begin_src wolfram
2 + 2
#+end_src
```

Press `C-c C-c` and get:

```org
#+begin_src wolfram
2 + 2
#+end_src

#+begin_example
4
#+end_example
```

### 2. New Commands

| Command | Key | Function |
|---------|-----|----------|
| `wolfram-nb-eval-block` | `C-c C-c` | Evaluate current source block |
| `wolfram-nb-eval-buffer` | `C-c C-b` | Evaluate all blocks |
| `wolfram-nb-clear-outputs` | `C-c C-k` | Clear all outputs |

### 3. Input/Output Support

Proper handling of Input and Output cell pairs:

- **Input cells**: Created from `#+begin_src wolfram` blocks
- **Output cells**: Created from `#+begin_example` blocks
- Both preserved in roundtrip conversion

### 4. Configuration Options

```elisp
;; Path to wolframscript
(setq wolfram-nb-wolframscript-path "wolframscript")

;; Evaluation timeout (seconds)
(setq wolfram-nb-eval-timeout 30)
```

### 5. Smart Output Handling

- **Numeric results**: Displayed directly
- **Graphics**: Shows placeholder with instructions
- **Errors**: Gracefully handled with error messages
- **Multiple statements**: Supports compound expressions

## Examples

### Simple Math

```org
#+begin_src wolfram
factorial[10]
#+end_src
```
→ Output: `3628800`

### Function Definition

```org
#+begin_src wolfram
square[x_] := x^2;
Map[square, Range[5]]
#+end_src
```
→ Output: `{1, 4, 9, 16, 25}`

### Symbolic Math

```org
#+begin_src wolfram
Expand[(x + y)^3]
#+end_src
```
→ Output: `x^3 + 3*x^2*y + 3*x*y^2 + y^3`

## Requirements

To use evaluation features, install wolframscript:

- **Free**: [Wolfram Engine](https://www.wolfram.com/engine/)
- **Or**: Mathematica/Wolfram Desktop (includes wolframscript)

Verify installation:
```bash
wolframscript -code "2+2"
# Should output: 4
```

## Workflow

1. **Write code** in org-mode syntax
2. **Evaluate** with `C-c C-c`
3. **See results** immediately
4. **Save** with `C-x C-s`
5. **Open in Mathematica** - all inputs/outputs preserved

## Files Added

- `EVALUATION.md` - Complete evaluation guide
- `test-eval.el` - Evaluation test suite
- `eval-demo.nb` - Example notebook with outputs
- `eval-demo.el` - Interactive demonstration
- `test-all.sh` - Comprehensive test script

## Documentation Updates

- `README.md` - Added evaluation features
- `QUICKREF.md` - Updated command reference
- `CHANGELOG.md` - Version 0.2.0 details

## Key Binding Changes

⚠️ **Breaking Change**: 

- `C-c C-c` now **evaluates** the current block (was: reparse)
- `C-c C-r` now **reparses** the buffer (was: C-c C-c)

This change makes evaluation more accessible (C-c C-c is the standard org-mode binding for code execution).

## Limitations

**Evaluated in wolframscript, not Emacs:**

- Graphics shown as placeholders (view in Mathematica)
- No Dynamic[] or Manipulate[] interaction
- Each block evaluated independently (no session persistence)

**Workarounds:**

- Group related code in one block for context
- Use Mathematica for graphics and interactive content
- Use Emacs for text, structure, and quick evaluations

## Testing

All tests pass:

```bash
./test-all.sh
```

Results:
- ✓ Unit tests (5/5)
- ✓ Integration tests (5/5)
- ✓ Evaluation tests (3/3)
- ✓ Example parsing

## Demo

Try the interactive demo:

```bash
emacs -l eval-demo.el
```

Or in Emacs:
```elisp
M-x wolfram-nb-open RET eval-demo.nb RET
C-c C-b  ; Evaluate all blocks
```

## Upgrade Path

If upgrading from v0.1.0:

1. **Pull changes**: `git pull`
2. **Reload mode**: `M-x eval-buffer` in your init file
3. **Learn new bindings**: 
   - `C-c C-c` → Evaluate (was reparse)
   - `C-c C-r` → Reparse (new)
4. **Optional**: Install wolframscript for evaluation

## Use Cases

### Perfect For:

- **Quick calculations** while writing documentation
- **Exploring ideas** without leaving Emacs
- **Teaching** - write and execute examples inline
- **Testing code snippets** before using in projects
- **Mathematical notes** with executable examples

### Still Use Mathematica For:

- Complex graphics and visualization
- Interactive widgets (Manipulate, etc.)
- Heavy computations
- Final polishing of notebooks

## What's Next?

Future enhancements may include:

- Persistent REPL session
- Inline image display
- Async evaluation
- Better graphics support
- More cell types
- Enhanced error reporting

## Summary

v0.2.0 transforms wolfram-nb-mode from a **static editor** into an **interactive development environment**, while maintaining its core strength: simple, text-based notebook editing in Emacs.

---

**Upgrade today and start evaluating Wolfram Language code in your favorite editor!**
