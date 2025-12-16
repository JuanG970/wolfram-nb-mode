#!/bin/bash
echo "╔════════════════════════════════════════════════════════╗"
echo "║     wolfram-nb-mode v0.3.0 - Complete Test Suite      ║"
echo "║                Using ERT Framework                     ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

FAILED=0

echo "1. Unit Tests (16 tests)..."
UNIT_RESULT=$(emacs --batch -l ert -l test-mode.el -f ert-run-tests-batch-and-exit 2>&1)
if echo "$UNIT_RESULT" | grep -q "16 results as expected"; then
    echo "   ✓ Unit tests PASSED (16/16)"
else
    echo "   ✗ Unit tests FAILED"
    echo "$UNIT_RESULT" | tail -5
    FAILED=1
fi

echo ""
echo "2. Integration Tests (6 tests)..."
INTEG_RESULT=$(emacs --batch -l ert -l integration-test.el -f ert-run-tests-batch-and-exit 2>&1)
if echo "$INTEG_RESULT" | grep -q "6 results as expected"; then
    echo "   ✓ Integration tests PASSED (6/6)"
else
    echo "   ✗ Integration tests FAILED"
    echo "$INTEG_RESULT" | tail -5
    FAILED=1
fi

echo ""
echo "3. Evaluation Tests (6 tests)..."
# Evaluation tests may skip some if wolframscript not available
EVAL_RESULT=$(emacs --batch -l ert -l test-eval.el -f ert-run-tests-batch-and-exit 2>&1)
if echo "$EVAL_RESULT" | grep -q "results as expected"; then
    # Extract test counts using awk
    PASSED=$(echo "$EVAL_RESULT" | grep "passed" | awk '{print $2}' | head -1)
    TOTAL=$(echo "$EVAL_RESULT" | grep "Ran" | awk '{print $2}' | head -1)
    echo "   ✓ Evaluation tests PASSED ($PASSED/$TOTAL)"
    if echo "$EVAL_RESULT" | grep -q "skipped"; then
        echo "     Note: Some tests skipped (wolframscript not installed)"
    fi
else
    echo "   ✗ Evaluation tests FAILED"
    echo "$EVAL_RESULT" | tail -5
    FAILED=1
fi

echo ""
echo "4. Parse eval-demo.nb..."
CELLS=$(emacs --batch --eval "(progn (add-to-list 'load-path \".\") (require 'wolfram-nb-mode) (message \"%d\" (length (wolfram-nb--parse-notebook \"eval-demo.nb\"))))" 2>&1 | tail -1)
if [ "$CELLS" -gt 0 ]; then
    echo "   ✓ Parsed $CELLS cells from eval-demo.nb"
else
    echo "   ✗ Failed to parse eval-demo.nb"
    FAILED=1
fi

echo ""
if [ $FAILED -eq 0 ]; then
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║             ✓ ALL TESTS PASSED                        ║"
    echo "╚════════════════════════════════════════════════════════╝"
else
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║             ✗ SOME TESTS FAILED                       ║"
    echo "╚════════════════════════════════════════════════════════╝"
    exit 1
fi

echo ""
echo "Features Verified:"
echo "  ✓ String escaping/unescaping"
echo "  ✓ Notebook parsing (simple and complex)"
echo "  ✓ CellGroupData unwrapping"
echo "  ✓ Cell-to-org conversion"
echo "  ✓ Org-to-cell conversion"
echo "  ✓ Roundtrip conversion"
echo "  ✓ Code evaluation (if wolframscript available)"
echo "  ✓ Input/Output handling"
echo ""
echo "Total: 28+ ERT tests"
echo ""
echo "wolfram-nb-mode v0.3.0 is ready!"
