# Evaluation Guide

## Overview

wolfram-nb-mode supports evaluating Wolfram Language code directly within Emacs using `wolframscript`. This allows you to write code in org-mode syntax, evaluate it, and see results inline.

## Requirements

### Installing wolframscript

To use evaluation features, you need wolframscript installed:

1. **Free Wolfram Engine**: https://www.wolfram.com/engine/
   - Download and install the Wolfram Engine
   - Includes wolframscript

2. **Mathematica/Wolfram Desktop**: 
   - If you have Mathematica, wolframscript is already installed

3. **Verify Installation**:
   ```bash
   which wolframscript
   # Should show: /usr/local/bin/wolframscript (or similar)
   
   wolframscript -code "2+2"
   # Should output: 4
   ```

### Configuration

If wolframscript is not in your PATH:

```elisp
(setq wolfram-nb-wolframscript-path "/path/to/wolframscript")
```

Set evaluation timeout (default 30 seconds):

```elisp
(setq wolfram-nb-eval-timeout 60)  ; 60 seconds
```

## Basic Usage

### Evaluate a Single Block

1. Create a source block:
   ```org
   #+begin_src wolfram
   2 + 2
   #+end_src
   ```

2. Place cursor in the block

3. Press `C-c C-c`

4. Output appears below:
   ```org
   #+begin_src wolfram
   2 + 2
   #+end_src

   #+begin_example
   4
   #+end_example
   ```

### Evaluate All Blocks

Press `C-c C-b` to evaluate all wolfram source blocks in the buffer.

### Clear Outputs

Press `C-c C-k` to remove all output blocks.

## Examples

### Simple Arithmetic

```org
#+begin_src wolfram
2 + 2
#+end_src
```
Output: `4`

### Function Definition

```org
#+begin_src wolfram
square[x_] := x^2
Map[square, Range[5]]
#+end_src
```
Output: `{1, 4, 9, 16, 25}`

### List Operations

```org
#+begin_src wolfram
Total[Range[100]]
#+end_src
```
Output: `5050`

### Symbolic Math

```org
#+begin_src wolfram
Expand[(x + y)^3]
#+end_src
```
Output: `x^3 + 3*x^2*y + 3*x*y^2 + y^3`

### Multiple Statements

```org
#+begin_src wolfram
a = 5;
b = 10;
a + b
#+end_src
```
Output: `15`

## Working with Input/Output Cells

### Creating Input Cells

Input cells in notebooks are created from source blocks:

```org
#+begin_src wolfram
Plot[Sin[x], {x, 0, 2 Pi}]
#+end_src
```

Saved as: `Cell["Plot[Sin[x], {x, 0, 2 Pi}]", "Input"]`

### Output Cells

After evaluation, output is stored in example blocks:

```org
#+begin_example
-Graphics-
#+end_example
```

Saved as: `Cell["-Graphics-", "Output"]`

### Notebook Round-trip

1. Edit in Emacs with evaluation
2. Save with `C-x C-s` (preserves Input/Output pairs)
3. Open in Mathematica
4. All code and results are preserved

## Graphics and Complex Output

### Graphics

Graphics outputs show a placeholder:

```org
#+begin_src wolfram
Plot[x^2, {x, 0, 10}]
#+end_src

#+begin_example
-Graphics-
; Graphics output (view in Mathematica)
#+end_example
```

To view graphics:
1. Save the notebook (`C-x C-s`)
2. Open in Mathematica
3. Graphics will be rendered

### Images

```org
#+begin_src wolfram
Image[RandomReal[1, {100, 100}]]
#+end_src

#+begin_example
-Image-
; Graphics output (view in Mathematica)
#+end_example
```

## Advanced Evaluation

### Multi-line Expressions

```org
#+begin_src wolfram
data = Table[{x, x^2}, {x, 1, 10}];
fit = Fit[data, {1, x, x^2}, x];
fit
#+end_src
```

### Function Libraries

```org
#+begin_src wolfram
Needs["GeneralUtilities`"]
PrintDefinitions[Map]
#+end_src
```

### Error Handling

If evaluation fails, an error message appears:

```org
#+begin_src wolfram
1/0
#+end_src

#+begin_example
Error: Power::infy: Infinite expression 1/0 encountered.
#+end_example
```

## Workflow Examples

### Example 1: Mathematical Exploration

```org
* Fibonacci Numbers

** Definition

Define the Fibonacci function:

#+begin_src wolfram
fib[0] = 0;
fib[1] = 1;
fib[n_] := fib[n-1] + fib[n-2]
#+end_src

** First 10 Numbers

#+begin_src wolfram
Table[fib[n], {n, 0, 9}]
#+end_src

** Golden Ratio

#+begin_src wolfram
N[GoldenRatio, 20]
#+end_src
```

### Example 2: Data Analysis

```org
* Data Analysis

** Generate Data

#+begin_src wolfram
data = RandomReal[NormalDistribution[0, 1], 100]
#+end_src

** Statistics

#+begin_src wolfram
{Mean[data], StandardDeviation[data]}
#+end_src

** Histogram

#+begin_src wolfram
Histogram[data]
#+end_src
```

### Example 3: Symbolic Computation

```org
* Calculus

** Derivative

#+begin_src wolfram
D[x^3 + 2*x^2 + x, x]
#+end_src

** Integral

#+begin_src wolfram
Integrate[x^2 + 1, x]
#+end_src

** Limit

#+begin_src wolfram
Limit[Sin[x]/x, x -> 0]
#+end_src
```

## Tips and Best Practices

### 1. Incremental Evaluation

Evaluate blocks one at a time during development:
- Write code
- Press `C-c C-c`
- Check output
- Refine
- Repeat

### 2. Clear Old Outputs

Before re-evaluating everything:
- Press `C-c C-k` to clear
- Press `C-c C-b` to evaluate all

### 3. Save Frequently

- Save after evaluating: `C-x C-s`
- Outputs are preserved in the notebook

### 4. Use Comments

```org
#+begin_src wolfram
(* This is a Wolfram comment *)
result = 2 + 2  (* inline comment *)
#+end_src
```

### 5. Organize with Sections

```org
* Setup
Define functions and load packages

** Helper Functions
#+begin_src wolfram
helper[x_] := x + 1
#+end_src

* Analysis
Run the analysis

** Step 1
#+begin_src wolfram
step1Result = helper[10]
#+end_src
```

## Limitations

### Not Evaluated in Emacs

- **Graphics**: Only placeholders shown
- **Dynamic**: Dynamic[], Manipulate[] not interactive
- **Notebooks UI**: Special notebook features unavailable

### Evaluation Environment

- Each block is evaluated independently
- No persistent session between blocks
- Variables defined in one block won't persist to the next
- Use compound expressions for related computations

### Workaround for Persistence

Put related code in one block:

```org
#+begin_src wolfram
x = 5;
y = 10;
result = x + y;
result
#+end_src
```

## Troubleshooting

### "wolframscript not found"

**Solution**: Install Wolfram Engine or set path:
```elisp
(setq wolfram-nb-wolframscript-path "/Applications/Mathematica.app/Contents/MacOS/wolframscript")
```

### Evaluation Hangs

**Solution**: Increase timeout:
```elisp
(setq wolfram-nb-eval-timeout 60)
```

Or kill Emacs and restart.

### Syntax Errors

**Check**:
- Wolfram Language syntax
- Matched brackets
- Semicolons for multiple statements

### Output Not Appearing

**Check**:
- Cursor is in source block
- Block is `#+begin_src wolfram` (not `mathematica`)
- No errors in *Messages* buffer

## Integration with Mathematica

### Workflow

1. **Draft in Emacs**:
   - Write structure
   - Write code
   - Evaluate for quick checks

2. **Polish in Mathematica**:
   - Open .nb file
   - Add graphics
   - Add interactive elements
   - Final evaluation

3. **Edit in Emacs**:
   - Update text
   - Update code
   - Re-save

### Best of Both Worlds

- **Emacs**: Text editing, structure, version control
- **Mathematica**: Graphics, dynamics, full evaluation

## Command Reference

| Command | Key | Description |
|---------|-----|-------------|
| `wolfram-nb-eval-block` | `C-c C-c` | Evaluate current block |
| `wolfram-nb-eval-buffer` | `C-c C-b` | Evaluate all blocks |
| `wolfram-nb-clear-outputs` | `C-c C-k` | Clear all outputs |

## See Also

- [USAGE.md](USAGE.md) - General usage guide
- [QUICKREF.md](QUICKREF.md) - Quick reference
- [Wolfram Engine](https://www.wolfram.com/engine/) - Free computational engine
