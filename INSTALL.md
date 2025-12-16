# Installation Guide

## Requirements

- **Emacs**: Version 26.1 or higher
- **Org-mode**: Built-in with Emacs (usually version 9.0+)
- **Optional**: wolfram-mode for better syntax highlighting

## Installation Methods

### Method 1: Manual Installation (Recommended for Testing)

1. Clone or download this repository:
   ```bash
   git clone https://github.com/yourusername/wolfram-nb-mode.git
   cd wolfram-nb-mode
   ```

2. Add to your Emacs init file (`~/.emacs` or `~/.emacs.d/init.el`):
   ```elisp
   (add-to-list 'load-path "/path/to/wolfram-nb-mode")
   (require 'wolfram-nb-mode)
   ```

3. Restart Emacs or evaluate the configuration:
   ```
   M-x eval-buffer
   ```

### Method 2: use-package (For use-package users)

```elisp
(use-package wolfram-nb-mode
  :load-path "/path/to/wolfram-nb-mode"
  :commands (wolfram-nb-open wolfram-nb-create-new)
  :config
  (setq wolfram-nb-auto-save t))
```

### Method 3: straight.el

```elisp
(straight-use-package
 '(wolfram-nb-mode :type git :host github
                   :repo "yourusername/wolfram-nb-mode"))
```

## Post-Installation Setup

### Enable Automatic Opening of .nb Files

Add to your init file:

```elisp
;; Automatically open .nb files with wolfram-nb-mode
(setq wolfram-nb-auto-save t)
```

### Optional: Syntax Highlighting

If you have wolfram-mode installed:

```elisp
(setq org-src-lang-modes
      (append '(("wolfram" . wolfram))
              org-src-lang-modes))
```

### Optional: Key Bindings

Add global key bindings for quick access:

```elisp
(global-set-key (kbd "C-c n o") 'wolfram-nb-open)
(global-set-key (kbd "C-c n n") 'wolfram-nb-create-new)
```

## Verification

### Quick Test

1. Open Emacs
2. Run: `M-x wolfram-nb-open`
3. Select a `.nb` file (or use the included `test.nb`)
4. You should see an org-mode buffer with the notebook content

### Run Test Suite

```bash
cd /path/to/wolfram-nb-mode
emacs --batch -l test-mode.el
```

Expected output: All tests pass ✓

### Run Integration Test

```bash
emacs --batch -l integration-test.el
```

This creates a test notebook and verifies the full workflow.

## Example Configuration

Here's a complete example configuration:

```elisp
;; wolfram-nb-mode configuration
(add-to-list 'load-path "~/emacs-packages/wolfram-nb-mode")
(require 'wolfram-nb-mode)

;; Enable automatic opening
(setq wolfram-nb-auto-save t)

;; Customize indentation
(setq wolfram-nb-indent-level 2)

;; Key bindings
(global-set-key (kbd "C-c n o") 'wolfram-nb-open)
(global-set-key (kbd "C-c n n") 'wolfram-nb-create-new)

;; Hook for additional setup
(add-hook 'wolfram-nb-mode-hook
          (lambda ()
            ;; Enable visual line mode for better readability
            (visual-line-mode 1)
            ;; Set fill column
            (setq fill-column 80)
            ;; Enable auto-fill for text
            (auto-fill-mode 1)))

;; If you have wolfram-mode
(when (require 'wolfram-mode nil t)
  (setq org-src-lang-modes
        (append '(("wolfram" . wolfram))
                org-src-lang-modes)))
```

## Troubleshooting Installation

### Problem: "Cannot open load file: wolfram-nb-mode"

**Solution**: Make sure the path in `add-to-list` is correct:
```elisp
;; Check the path
(file-exists-p "/path/to/wolfram-nb-mode/wolfram-nb-mode.el")
```

### Problem: Mode not loading automatically for .nb files

**Solution**: Ensure auto-mode-alist is set:
```elisp
;; Check if the association exists
(assoc "\\.nb\\'" auto-mode-alist)

;; It should return something like ("\\.nb\\'" . wolfram-nb-open-auto)
```

### Problem: Commands not available

**Solution**: Make sure the package is properly loaded:
```elisp
;; Check if functions are defined
(fboundp 'wolfram-nb-open)  ; Should return t
```

## Uninstallation

To remove wolfram-nb-mode:

1. Remove the configuration from your init file
2. Remove the mode directory
3. Restart Emacs

## Next Steps

After installation:

1. Read [USAGE.md](USAGE.md) for detailed usage instructions
2. Try opening the example notebooks (`test.nb`, `example.nb`)
3. Run the demo: `emacs -l demo.el`
4. Check the [README.md](README.md) for feature overview

## Getting Help

If you encounter issues:

1. Check this installation guide
2. Review [USAGE.md](USAGE.md)
3. Run the test suite to verify functionality
4. Check the GitHub issues page
5. File a new issue with:
   - Emacs version: `M-x emacs-version`
   - Org-mode version: `M-x org-version`
   - Error messages
   - Steps to reproduce

## Development Setup

For contributing or development:

```bash
# Clone the repository
git clone https://github.com/yourusername/wolfram-nb-mode.git
cd wolfram-nb-mode

# Run tests
emacs --batch -l test-mode.el

# Run integration tests
emacs --batch -l integration-test.el

# Load for development
emacs -Q -l wolfram-nb-mode.el -l demo.el
```
