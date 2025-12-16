#!/bin/bash
echo "==================================="
echo "wolfram-nb-mode - Final Test Suite"
echo "==================================="
echo ""

echo "1. Running unit tests..."
if emacs --batch -l test-mode.el 2>&1 | grep -q "ALL TESTS PASSED"; then
    echo "   ✓ Unit tests PASSED"
else
    echo "   ✗ Unit tests FAILED"
    exit 1
fi
echo ""

echo "2. Running integration tests..."
if emacs --batch -l integration-test.el 2>&1 | grep -q "ALL INTEGRATION TESTS PASSED"; then
    echo "   ✓ Integration tests PASSED"
else
    echo "   ✗ Integration tests FAILED"
    exit 1
fi
echo ""

echo "3. Testing example.nb..."
CELLS=$(emacs --batch --eval "(progn (add-to-list 'load-path \".\") (require 'wolfram-nb-mode) (message \"%d\" (length (wolfram-nb--parse-notebook \"example.nb\"))))" 2>&1 | tail -1)
if [ "$CELLS" -gt 0 ]; then
    echo "   ✓ Parsed $CELLS cells from example.nb"
else
    echo "   ✗ Failed to parse example.nb"
    exit 1
fi
echo ""

echo "4. Testing test.nb..."
CELLS=$(emacs --batch --eval "(progn (add-to-list 'load-path \".\") (require 'wolfram-nb-mode) (message \"%d\" (length (wolfram-nb--parse-notebook \"test.nb\"))))" 2>&1 | tail -1)
if [ "$CELLS" -gt 0 ]; then
    echo "   ✓ Parsed $CELLS cells from test.nb"
else
    echo "   ✗ Failed to parse test.nb"
    exit 1
fi
echo ""

echo "5. Testing roundtrip..."
emacs --batch --eval "(progn (add-to-list 'load-path \".\") (require 'wolfram-nb-mode) (let* ((cells1 (wolfram-nb--parse-notebook \"test.nb\")) (org (wolfram-nb--cells-to-org cells1)) (cells2 (wolfram-nb--org-to-cells org)) (nb (wolfram-nb--cells-to-notebook cells2))) (with-temp-file \"/tmp/roundtrip-test.nb\" (insert nb))))" 2>&1
if [ -f /tmp/roundtrip-test.nb ] && grep -q "^Notebook\[{" /tmp/roundtrip-test.nb; then
    echo "   ✓ Roundtrip conversion successful"
else
    echo "   ✗ Roundtrip conversion failed"
    exit 1
fi
echo ""

echo "==================================="
echo "✓ ALL FINAL TESTS PASSED"
echo "==================================="
echo ""
echo "Summary:"
echo "  - Unit tests: PASS"
echo "  - Integration tests: PASS"
echo "  - Example parsing: PASS"
echo "  - Test parsing: PASS"
echo "  - Roundtrip: PASS"
echo ""
echo "wolfram-nb-mode is ready to use!"
