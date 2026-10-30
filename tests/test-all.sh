#!/bin/bash
set -euo pipefail

echo "╔════════════════════════════════════════════════════════╗"
echo "║     wolfram-nb-mode v0.5.0 — Full Test Suite          ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

FAILED=0
TOTAL_TESTS=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

run_test_file() {
    local name="$1"
    local file="$2"
    local result exit_code
    set +e
    result=$(emacs --batch -Q \
        -L "$ROOT_DIR" -L "$SCRIPT_DIR" \
        -l ert -l "$SCRIPT_DIR/$file" \
        -f ert-run-tests-batch-and-exit 2>&1)
    exit_code=$?
    set -e

    local ran passed skipped
    ran=$(echo "$result" | grep -oE "Ran [0-9]+ tests" | grep -oE "[0-9]+" || echo 0)
    passed=$(echo "$result" | grep -oE "[0-9]+ tests? passed" | grep -oE "^[0-9]+" || echo "$ran")
    skipped=$(echo "$result" | grep -oE "[0-9]+ skipped" | grep -oE "^[0-9]+" || echo 0)

    if [ "$exit_code" -eq 0 ]; then
        echo "   ✓ $name PASSED (${passed}/${ran})"
        [ "$skipped" -gt 0 ] 2>/dev/null && echo "     ($skipped skipped)"
    else
        echo "   ✗ $name FAILED"
        echo "$result" | grep -E "(FAILED|unexpected|Error)" | head -10
        FAILED=1
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + ran))
}

echo "1. Unit Tests"
run_test_file "Unit tests" "test-mode.el"

echo ""
echo "2. Integration Tests"
run_test_file "Integration tests" "integration-test.el"

echo ""
echo "3. CellGroupData Tests"
run_test_file "CellGroupData tests" "test-cellgroupdata.el"

echo ""
echo "4. Evaluation Tests"
run_test_file "Evaluation tests" "test-eval.el"

echo ""
echo "5. Parse example notebooks"
for nb in "$ROOT_DIR"/examples/*.nb; do
    nb_name=$(basename "$nb")
    set +e
    CELLS=$(emacs --batch -Q -L "$ROOT_DIR" \
        --eval "(progn (require 'wolfram-nb-mode) (message \"%d\" (length (wolfram-nb--parse-notebook \"$nb\"))))" \
        2>&1 | tail -1)
    set -e
    if [ "$CELLS" -gt 0 ] 2>/dev/null; then
        echo "   ✓ $nb_name: $CELLS cells"
    else
        echo "   ✗ $nb_name: failed to parse"
        FAILED=1
    fi
done

echo ""
echo "6. Session Tests"
run_test_file "Session tests" "test-session.el"

echo ""
echo "7. Kernel Tests"
run_test_file "Kernel tests" "test-kernel.el"

echo ""
echo "8. Output & Graphics Tests"
run_test_file "Output tests" "test-output.el"

echo ""
echo "9. End-to-End Notebook Tests"
run_test_file "End-to-end tests" "test-e2e.el"

echo ""
echo "10. Notebook Corpus Tests"
run_test_file "Corpus tests" "test-corpus.el"

echo ""
echo "11. Edge Cases and Fuzzing"
run_test_file "Edge-case tests" "test-edge.el"
run_test_file "Highlighting tests" "test-faces.el"
run_test_file "Workflow tests" "test-workflow.el"
run_test_file "Cell group tests" "test-groups.el"
run_test_file "Verbatim cell tests" "test-verbatim.el"

echo ""
echo "12. Byte-compilation"
set +e
BC_RESULT=$(emacs --batch -Q -L "$ROOT_DIR" \
    --eval "(setq byte-compile-error-on-warn t)" \
    -f batch-byte-compile "$ROOT_DIR/wolfram-nb-kernel.el" "$ROOT_DIR/wolfram-nb-mode.el" 2>&1)
BC_EXIT=$?
set -e
rm -f "$ROOT_DIR/wolfram-nb-mode.elc" "$ROOT_DIR/wolfram-nb-kernel.elc"
if [ "$BC_EXIT" -eq 0 ]; then
    echo "   ✓ Byte-compiles cleanly (no warnings)"
else
    echo "   ✗ Byte-compilation issues"
    echo "$BC_RESULT"
    FAILED=1
fi

echo ""
echo "════════════════════════════════════════════════════════"
if [ $FAILED -eq 0 ]; then
    echo "  ✓ ALL TESTS PASSED — $TOTAL_TESTS ERT tests"
else
    echo "  ✗ SOME TESTS FAILED"
    exit 1
fi
echo "════════════════════════════════════════════════════════"
