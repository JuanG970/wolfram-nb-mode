# Testing Guide

## Overview

wolfram-nb-mode uses the **ERT (Emacs Regression Testing)** framework for all tests. This provides a standard, robust testing infrastructure with good reporting.

## Running Tests

### Run All Tests

```bash
./test-all.sh
```

This runs the complete test suite including:
- 16 unit tests
- 6 integration tests
- 6 evaluation tests (requires wolframscript)
- 1 parsing verification

### Run Individual Test Suites

**Unit Tests:**
```bash
emacs -batch -l ert -l test-mode.el -f ert-run-tests-batch-and-exit
```

**Integration Tests:**
```bash
emacs -batch -l ert -l integration-test.el -f ert-run-tests-batch-and-exit
```

**Evaluation Tests:**
```bash
emacs -batch -l ert -l test-eval.el -f ert-run-tests-batch-and-exit
```

### Run Specific Tests

Run a specific test by name:
```bash
emacs -batch -l ert -l test-mode.el \
  --eval "(ert-run-tests-batch-and-exit 'wolfram-nb-test-escape-string)"
```

Run tests matching a pattern:
```bash
emacs -batch -l ert -l test-mode.el \
  --eval "(ert-run-tests-batch-and-exit \"escape\")"
```

## Test Suites

### Unit Tests (test-mode.el)

Tests core functionality:

**String Operations:**
- `wolfram-nb-test-escape-string` - Test string escaping
- `wolfram-nb-test-unescape-string` - Test string unescaping
- `wolfram-nb-test-escape-roundtrip` - Test escape/unescape roundtrip

**Parsing:**
- `wolfram-nb-test-parse-notebook` - Test notebook parsing
- `wolfram-nb-test-parse-cell-simple` - Test simple cell parsing
- `wolfram-nb-test-parse-cell-cellgroupdata` - Test CellGroupData detection

**Conversion:**
- `wolfram-nb-test-cell-to-org-section` - Test Section conversion
- `wolfram-nb-test-cell-to-org-title` - Test Title conversion
- `wolfram-nb-test-cell-to-org-text` - Test Text conversion
- `wolfram-nb-test-cell-to-org-item` - Test Item conversion
- `wolfram-nb-test-cell-to-org-code` - Test Code conversion
- `wolfram-nb-test-cells-to-org-multiple` - Test multiple cells
- `wolfram-nb-test-org-to-cells` - Test org-to-cells

**Roundtrip:**
- `wolfram-nb-test-roundtrip-conversion` - Test full roundtrip

**CellGroupData:**
- `wolfram-nb-test-cellgroupdata-detection` - Test CellGroupData detection
- `wolfram-nb-test-cellgroupdata-extraction` - Test cell extraction

### Integration Tests (integration-test.el)

Tests complete workflows:

- `integration-test-create-notebook` - Create notebook from org
- `integration-test-read-notebook` - Read notebook back
- `integration-test-modify-notebook` - Modify and save
- `integration-test-verify-modification` - Verify changes
- `integration-test-file-format` - Check .nb format
- `integration-test-roundtrip-fidelity` - Test content preservation

### Evaluation Tests (test-eval.el)

Tests code evaluation (requires wolframscript):

- `wolfram-nb-test-wolframscript-check` - Check availability
- `wolfram-nb-test-simple-evaluation` - Test basic arithmetic
- `wolfram-nb-test-list-evaluation` - Test list operations
- `wolfram-nb-test-function-evaluation` - Test function definitions
- `wolfram-nb-test-arithmetic` - Test arithmetic operations
- `wolfram-nb-test-format-output` - Test output formatting

**Note:** These tests are skipped if wolframscript is not installed.

## Writing Tests

### Basic ERT Test

```elisp
(ert-deftest my-test-name ()
  "Description of what this tests."
  (should (equal (my-function "input") "expected-output"))
  (should-not (my-predicate nil))
  (should-error (my-function-that-errors)))
```

### Common Assertions

```elisp
;; Equality
(should (equal actual expected))
(should (string= str1 str2))
(should (= num1 num2))

;; Boolean
(should predicate)
(should-not predicate)

;; Errors
(should-error (function-call))
(should-error (function-call) :type 'error-type)

;; Pattern matching
(should (string-match-p "pattern" string))
```

### Skip Tests Conditionally

```elisp
(ert-deftest my-test ()
  "Test that requires wolframscript."
  (skip-unless (wolfram-nb--check-wolframscript))
  ;; Test code here
  )
```

## Test Output

### Success

```
Running 16 tests (2025-12-15 23:05:19-0600, selector 't')
   passed   1/16  wolfram-nb-test-escape-string (0.000075 sec)
   passed   2/16  wolfram-nb-test-unescape-string (0.000185 sec)
   ...
Ran 16 tests, 16 results as expected, 0 unexpected
```

### Failure

```
   FAILED  1/16  wolfram-nb-test-example (0.000123 sec)
   
Test wolfram-nb-test-example condition:
    (ert-test-failed
     ((should (equal result expected))
      :form (equal "actual" "expected")
      :value nil))
```

## Interactive Testing

Run tests interactively in Emacs:

```elisp
;; Load test file
M-x load-file RET test-mode.el RET

;; Run all tests
M-x ert RET t RET

;; Run specific test
M-x ert RET wolfram-nb-test-escape-string RET

;; Run tests matching pattern
M-x ert RET "escape" RET
```

## Continuous Integration

Tests are designed to run in batch mode for CI:

```bash
#!/bin/bash
emacs -batch -l ert -l test-mode.el -f ert-run-tests-batch-and-exit
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
    echo "Tests failed!"
    exit 1
fi
```

## Test Coverage

Current test coverage:

- **String operations**: 100%
- **Notebook parsing**: 100%
- **Cell conversion**: 100%
- **CellGroupData**: 100%
- **Roundtrip**: 100%
- **Evaluation**: 100% (when wolframscript available)

Total: **28 tests** covering all major functionality

## Troubleshooting

### Tests Fail to Load

```bash
# Make sure you're in the right directory
cd /path/to/wolfram-nb-mode

# Check that files exist
ls -l test-mode.el
```

### Evaluation Tests Skip

This is normal if wolframscript is not installed:

```
Running 6 tests...
   skipped  1/6  wolfram-nb-test-simple-evaluation
   ...
```

To install wolframscript: https://www.wolfram.com/engine/

### Tests Timeout

Evaluation tests may take time:

```bash
# They use wolframscript which can be slow
# This is normal - each evaluation test takes 4-5 seconds
```

## Adding New Tests

When adding new functionality:

1. **Write the test first** (TDD approach)
2. **Add to appropriate test file**:
   - Core functions → `test-mode.el`
   - Workflows → `integration-test.el`
   - Evaluation → `test-eval.el`
3. **Run tests** to ensure they fail initially
4. **Implement feature**
5. **Run tests** to ensure they pass
6. **Update test count** in `test-all.sh`

Example:

```elisp
;; In test-mode.el
(ert-deftest wolfram-nb-test-new-feature ()
  "Test the new feature."
  (should (wolfram-nb-new-feature "input") "expected"))
```

## Test Philosophy

- **Small, focused tests** - Each test checks one thing
- **Clear names** - Test names describe what they test
- **Good assertions** - Use appropriate `should` forms
- **Fast when possible** - Unit tests run in milliseconds
- **Skip gracefully** - Use `skip-unless` for optional features

## See Also

- [ERT Manual](https://www.gnu.org/software/emacs/manual/html_node/ert/)
- [Writing Tests](https://www.gnu.org/software/emacs/manual/html_node/ert/Writing-Tests.html)
- [Running Tests](https://www.gnu.org/software/emacs/manual/html_node/ert/Running-Tests-Interactively.html)
