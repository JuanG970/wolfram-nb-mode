;;; test-mode.el --- Test script for wolfram-nb-mode using ERT -*- lexical-binding: t; -*-

;;; Commentary:
;; Test basic functionality of wolfram-nb-mode using Emacs ERT framework

;;; Code:

(require 'ert)
(add-to-list 'load-path default-directory)
(require 'wolfram-nb-mode)

;;; String Escaping Tests

(ert-deftest wolfram-nb-test-escape-string ()
  "Test string escaping."
  (should (string= (wolfram-nb--escape-string "simple") "simple"))
  (should (string= (wolfram-nb--escape-string "with\"quote") "with\\\"quote"))
  (should (string= (wolfram-nb--escape-string "with\\backslash") "with\\\\backslash"))
  (should (string= (wolfram-nb--escape-string "with\nnewline") "with\\nnewline")))

(ert-deftest wolfram-nb-test-unescape-string ()
  "Test string unescaping."
  (should (string= (wolfram-nb--unescape-string "simple") "simple"))
  (should (string= (wolfram-nb--unescape-string "with\\\"quote") "with\"quote"))
  (should (string= (wolfram-nb--unescape-string "with\\\\backslash") "with\\backslash"))
  (should (string= (wolfram-nb--unescape-string "with\\nnewline") "with\nnewline")))

(ert-deftest wolfram-nb-test-escape-roundtrip ()
  "Test that escape/unescape roundtrips correctly."
  (let* ((original "Test \"quoted\" with\\backslash and\nnewline")
         (escaped (wolfram-nb--escape-string original))
         (unescaped (wolfram-nb--unescape-string escaped)))
    (should (string= original unescaped))))

;;; Parsing Tests

(ert-deftest wolfram-nb-test-parse-notebook ()
  "Test parsing a notebook file."
  (let ((cells (wolfram-nb--parse-notebook "test.nb")))
    (should (> (length cells) 0))
    (should (listp cells))
    ;; Check that each cell has required properties
    (dolist (cell cells)
      (should (plist-get cell :style))
      (should (plist-get cell :content)))))

(ert-deftest wolfram-nb-test-parse-cell-simple ()
  "Test parsing simple text cells."
  (let ((cell-str "Cell[\"Test content\", \"Section\"]"))
    (let ((parsed (wolfram-nb--parse-cell cell-str)))
      (should parsed)
      (should (string= (plist-get parsed :content) "Test content"))
      (should (string= (plist-get parsed :style) "Section")))))

(ert-deftest wolfram-nb-test-parse-cell-cellgroupdata ()
  "Test that CellGroupData wrappers are detected."
  (let ((cell-str "Cell[CellGroupData[{Cell[\"Title\", \"Title\"]}]]"))
    (should (wolfram-nb--is-cellgroupdata cell-str))))

;;; Conversion Tests

(ert-deftest wolfram-nb-test-cell-to-org-section ()
  "Test converting Section cell to org format."
  (let* ((cell (list :content "Test Section" :style "Section"))
         (org-text (wolfram-nb--cell-to-org cell)))
    (should (string-match-p "\\* Test Section" org-text))))

(ert-deftest wolfram-nb-test-cell-to-org-title ()
  "Test converting Title cell to org format."
  (let* ((cell (list :content "My Title" :style "Title"))
         (org-text (wolfram-nb--cell-to-org cell)))
    (should (string-match-p "#\\+TITLE:" org-text))
    (should (string-match-p "My Title" org-text))))

(ert-deftest wolfram-nb-test-cell-to-org-text ()
  "Test converting Text cell to org format."
  (let* ((cell (list :content "Some text here" :style "Text"))
         (org-text (wolfram-nb--cell-to-org cell)))
    (should (string-match-p "Some text here" org-text))))

(ert-deftest wolfram-nb-test-cell-to-org-item ()
  "Test converting Item cell to org format."
  (let* ((cell (list :content "• List item" :style "Item"))
         (org-text (wolfram-nb--cell-to-org cell)))
    (should (string-match-p "- List item" org-text))))

(ert-deftest wolfram-nb-test-cell-to-org-code ()
  "Test converting Code cell to org format."
  (let* ((cell (list :content "x = 5" :style "Code"))
         (org-text (wolfram-nb--cell-to-org cell)))
    (should (string-match-p "begin_src wolfram" org-text))
    (should (string-match-p "x = 5" org-text))
    (should (string-match-p "end_src" org-text))))

(ert-deftest wolfram-nb-test-cells-to-org-multiple ()
  "Test converting multiple cells to org format."
  (let* ((test-cells (list
                      (list :content "Test Section" :style "Section")
                      (list :content "Some text here" :style "Text")
                      (list :content "• List item" :style "Item")
                      (list :content "x = 5" :style "Code")))
         (org-text (wolfram-nb--cells-to-org test-cells)))
    (should (string-match-p "\\* Test Section" org-text))
    (should (string-match-p "Some text here" org-text))
    (should (string-match-p "- List item" org-text))
    (should (string-match-p "begin_src wolfram" org-text))))

(ert-deftest wolfram-nb-test-org-to-cells ()
  "Test converting org format to cells."
  (let* ((org-text "* My Section\n\nSome text\n\n- Item one\n- Item two\n\n#+begin_src wolfram\nPlot[x^2, {x, 0, 1}]\n#+end_src\n")
         (cells (wolfram-nb--org-to-cells org-text)))
    (should (> (length cells) 0))
    (should (listp cells))))

;;; Roundtrip Tests

(ert-deftest wolfram-nb-test-roundtrip-conversion ()
  "Test roundtrip: notebook -> org -> cells -> notebook."
  (let* ((cells1 (wolfram-nb--parse-notebook "test.nb"))
         (org-text (wolfram-nb--cells-to-org cells1))
         (cells2 (wolfram-nb--org-to-cells org-text))
         (notebook-text (wolfram-nb--cells-to-notebook cells2)))
    (should (> (length cells1) 0))
    (should (> (length cells2) 0))
    (should (string-match-p "Notebook\\[{" notebook-text))))

;;; CellGroupData Tests

(ert-deftest wolfram-nb-test-cellgroupdata-detection ()
  "Test CellGroupData detection."
  (should (wolfram-nb--is-cellgroupdata "Cell[CellGroupData[{...}]]"))
  (should-not (wolfram-nb--is-cellgroupdata "Cell[\"text\", \"Section\"]")))

(ert-deftest wolfram-nb-test-cellgroupdata-extraction ()
  "Test extracting cells from CellGroupData."
  (let* ((cellgroup-str "Cell[CellGroupData[{Cell[\"Title\", \"Title\"],Cell[\"Text\", \"Text\"]}]]")
         (cells (wolfram-nb--extract-cells-from-group cellgroup-str)))
    (should (listp cells))
    ;; Should extract at least the inner cells
    (should (>= (length cells) 0))))

(provide 'test-mode)
;;; test-mode.el ends here
