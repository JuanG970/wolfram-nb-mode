# Getting Started with wolfram-nb-mode

## Installation (2 minutes)

1. **Add to your Emacs config** (`~/.emacs` or `~/.emacs.d/init.el`):
   ```elisp
   (add-to-list 'load-path "/Users/juangonzalez/PersonalProjects/wolfram-nb-mode")
   (require 'wolfram-nb-mode)
   (setq wolfram-nb-auto-save t)
   ```

2. **Restart Emacs** or run `M-x eval-buffer`

3. **Verify installation**:
   ```
   M-x wolfram-nb-open
   ```
   If the command is available, you're ready!

## Your First Notebook (5 minutes)

### Create a New Notebook

1. Open Emacs
2. Run: `M-x wolfram-nb-create-new`
3. Enter filename: `~/my-first.nb`
4. You'll see a buffer with starter content

### Edit the Content

Replace the starter content with:

```org
* My First Wolfram Notebook

Welcome! This is a simple notebook created in Emacs.

** Basic Math

Let's do some simple calculations:

#+begin_src wolfram
2 + 2
5 * 8
10^3
#+end_src

** Functions

Define a simple function:

#+begin_src wolfram
square[x_] := x^2
Map[square, Range[10]]
#+end_src

** Summary

Key features:
- Edit in Emacs using org-mode
- Save to .nb format
- Open in Mathematica
```

### Save the Notebook

Press `C-x C-s` (or `M-x wolfram-nb-save`)

You'll see: "Saved to ~/my-first.nb"

### Verify in Mathematica

Open `~/my-first.nb` in Mathematica or Wolfram Desktop. You should see your sections, text, and code!

## Opening Existing Notebooks (2 minutes)

### Try the Examples

1. Run: `M-x wolfram-nb-open`
2. Navigate to: `/Users/juangonzalez/PersonalProjects/wolfram-nb-mode/example.nb`
3. Press Enter

You'll see the notebook content as org-mode text!

### Edit and Save

1. Make some changes (add text, edit code, etc.)
2. Press `C-x C-s` to save
3. The changes are written back to the .nb file

## Key Concepts

### Cells Map to Org Elements

| What You Type | What It Becomes |
|---------------|-----------------|
| `* Section` | Section cell |
| `** Subsection` | Subsection cell |
| Text paragraph | Text cell |
| `- Item` | Item cell |
| Code block | Code cell |

### Example Mapping

**Your org-mode text:**
```org
* Introduction
This is some text.

- Point one
- Point two
```

**Becomes in .nb:**
```mathematica
Cell["Introduction", "Section"]
Cell["This is some text.", "Text"]
Cell["Point one", "Item"]
Cell["Point two", "Item"]
```

## Common Tasks

### Task 1: Add a New Section

```org
* My New Section

Content goes here...
```

Save with `C-x C-s`

### Task 2: Add Code

```org
#+begin_src wolfram
Print["Hello from Emacs!"]
#+end_src
```

### Task 3: Create a List

```org
- First item
- Second item
- Third item
```

### Task 4: View Raw Cells

Press `C-c C-v` to see the Cell[...] structures

### Task 5: Reparse Buffer

If something looks wrong, press `C-c C-c`

## Tips for Success

1. **Start Simple**: Begin with just sections and text
2. **Save Often**: Press `C-x C-s` frequently
3. **Test in Mathematica**: Open your .nb file to verify
4. **Use Org Features**: Tab to fold/unfold, M-RET for new items
5. **Keep Backups**: When learning, keep copies of important notebooks

## Troubleshooting

### "Not a valid Notebook file"

The file needs to have `Notebook[{...}]` structure. If you're creating a new file, use `M-x wolfram-nb-create-new` instead of opening an empty file.

### Content Looks Strange

Press `C-c C-c` to reparse the buffer.

### Can't Save

Make sure you opened the file with `wolfram-nb-open` or `wolfram-nb-create-new`, not just a regular file open.

## Next Steps

### Learn More

- Read [USAGE.md](USAGE.md) for detailed features
- Check [QUICKREF.md](QUICKREF.md) for quick reference
- See [README.md](README.md) for overview

### Try Advanced Features

1. **Nested Sections**:
   ```org
   * Section
   ** Subsection
   *** Subsubsection
   ```

2. **Multiple Code Blocks**:
   ```org
   #+begin_src wolfram
   x = 5
   #+end_src

   #+begin_src wolfram
   y = x + 3
   #+end_src
   ```

3. **Mixed Content**:
   ```org
   * Analysis

   Here's the problem:

   - Data is messy
   - Need to clean it

   Solution:

   #+begin_src wolfram
   CleanData[data_] := Select[data, NumberQ]
   #+end_src
   ```

### Workflow Example

1. **Morning**: Open your notebook in Emacs
2. **Edit**: Add sections, notes, code structure
3. **Save**: `C-x C-s` to save as .nb
4. **Afternoon**: Open in Mathematica
5. **Execute**: Run the code, see outputs
6. **Evening**: Back to Emacs for more editing

## Real-World Example

Let's create a complete notebook:

```org
* Linear Regression Analysis

This notebook performs basic linear regression.

** Data Preparation

First, generate some sample data:

#+begin_src wolfram
data = Table[{x, 2*x + 3 + RandomReal[{-1, 1}]}, {x, 0, 10, 0.5}]
#+end_src

** Visualization

Plot the data:

#+begin_src wolfram
ListPlot[data, PlotStyle -> Red]
#+end_src

** Regression

Fit a linear model:

#+begin_src wolfram
fit = LinearModelFit[data, x, x]
Show[ListPlot[data], Plot[fit[x], {x, 0, 10}]]
#+end_src

** Results

Key findings:
- Slope: approximately 2
- Intercept: approximately 3
- Good fit to data

** Conclusion

Linear regression successfully applied.
```

Save this, open in Mathematica, and execute the cells!

## Practice Exercise

Create a notebook about the Fibonacci sequence:

1. Section explaining what Fibonacci numbers are
2. Code to generate first 20 Fibonacci numbers
3. Code to plot them
4. List of interesting properties
5. Conclusion section

## Help & Resources

- [USAGE.md](USAGE.md) - Detailed usage guide
- [QUICKREF.md](QUICKREF.md) - Quick reference
- [INSTALL.md](INSTALL.md) - Installation help
- Example files: `example.nb`, `test.nb`

## Summary

You now know how to:
- ✓ Install wolfram-nb-mode
- ✓ Create new notebooks
- ✓ Open existing notebooks
- ✓ Edit content using org-mode
- ✓ Save back to .nb format
- ✓ Use basic features

**Start creating your notebooks in Emacs today!**
