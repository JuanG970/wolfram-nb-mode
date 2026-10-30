;;; test-edge.el --- Regression tests for edge cases found by fuzzing -*- lexical-binding: t; -*-

;;; Commentary:
;; Each case here once lost or changed data.  The table-driven part reuses the
;; fuzzer's harness (test-fuzz.el): a cell of the given style holds the given
;; text, written as it appears in a Wolfram string, and must survive being
;; converted to Org and back.

;;; Code:

(require 'ert)
(require 'cl-lib)
(let ((dir (file-name-directory (or load-file-name buffer-file-name default-directory))))
  (add-to-list 'load-path dir))
(require 'test-fuzz)

(defconst wolfram-nb-edge--cases
  '(;; commas that Org's block escaping must not eat
    ("Input" ",*") ("Output" ",*") ("Input" ",#+x") ("Text" ",*~- \\n")
    ("Input" "#+end_src") ("Output" "#+end_example") ("Code" ":PROPERTIES:\\n:END:")
    ;; text that Org reads as something other than a paragraph
    ("Text" "*") ("Text" "** (parenthesis)") ("Text" "* x") ("Text" "- a") ("Text" "1. a")
    ("Text" "#+NAME: n\\nx1") ("Text" "#+TITLE: t") ("Text" "it's*) \\n :END:")
    ("Text" ": fixed") ("Text" "| a | b |") ("Text" "-----") ("Text" "[fn:1]naïve")
    ("Text" "a\\n\\nb") ("Text" "$x$<") ("Text" "src_python{1}") ("Text" "a_b") ("Text" "x^2")
    ("Text" "\\\\") ("Text" "word \\\\\\\\") ("Text" "[[a][b]]") ("Text" "<<t>>") ("Text" "+s+")
    ("Text" "{{{m(a)}}}") ("Text" "<2026-10-29 Thu>") ("Text" "[1/3] done") ("Text" "[50%]")
    ;; a backslash before > is not the end of a long string
    ("Text" "\\\\>") ("Text" "a\\\\>") ("Input" "x\\\\>")
    ;; named characters keep a single backslash
    ("Text" "\\[Alpha] and \\[Dash]") ("Input" "\\[Alpha] = 1") ("Text" "\\:03b1")
    ;; headlines: words Org would take for keywords, priorities and tags
    ("Section" "TODO list") ("Section" "DONE") ("Section" "Notes :work:") ("Section" ":a:b:")
    ("Section" "[#A] first") ("Section" "COMMENT out") ("Subsection" "* star")
    ("Section" "a\\nb") ("Chapter" "x [[a][b]] y") ("Section" "*)<<t>>\\tword(*")
    ("Section" "/[#A] foo[[a][b]]/") ("Subsubsection" "\\\\alpha_b") ("Section" "$x$")
    ;; titles, kept where they stand
    ("Title" "TODO") ("Title" "a :tag:") ("Subtitle" "x\\ny")
    ;; list items that do not survive as a list item
    ("Item" "") ("Item" "a\\nb") ("Item" "foo :: bar") ("Item" "[ ] todo") ("Item" "[@3] x")
    ("Item" "-----]") ("Item" "- x1") ("Item" ":tag:") ("Item" "*b* and /i/")
    ("ItemNumbered" "1. text") ("ItemNumbered" "") ("Subitem" "alone") ("Subsubitem" "alone")
    ("SubitemNumbered" "alone")
    ;; a literal backslash before characters that would form a character escape
    ("Text" "\\\\(z\\\\)") ("Input" "a\\\\(b") ("Text" "\\\\[Alpha]") ("Text" "x\\\\*y")
    ("Output" "\\\\\\\\(") ("Text" "end \\\\"))
  "Pairs of a style and a string body that once failed.")

(ert-deftest wolfram-nb-edge-test-cases-that-once-failed ()
  (let (failures)
    (dolist (case wolfram-nb-edge--cases)
      (let ((result (wolfram-nb-fuzz--case (car case) (list (cadr case)))))
        (when result (push result failures))))
    (when failures
      (message "%s" (wolfram-nb-fuzz--report (nreverse failures))))
    (should-not failures)))

;;; Cells in context

(ert-deftest wolfram-nb-edge-test-block-opened-in-one-cell-closed-by-another ()
  "An indented #+begin_src in a paragraph must not swallow the cells that follow."
  (let* ((cells '("Cell[\"a #+begin_src\\n #+begin_src x\", \"Text\"]"
                  "Cell[\"1+1\", \"Input\"]"
                  "Cell[\"after\", \"Text\"]"))
         (back (cdr (wolfram-nb-fuzz--round-trip cells))))
    (should (equal (mapcar (lambda (s) (wolfram-nb-cell-style (wolfram-nb--parse-cell s))) back)
                   '("Text" "Input" "Text")))
    (should (equal (wolfram-nb-cell-content (wolfram-nb--parse-cell (nth 2 back))) "after"))))

(ert-deftest wolfram-nb-edge-test-drawer-and-environment-openers-are-contained ()
  (let* ((cells '("Cell[\"x\\n :PROPERTIES:\\ny\", \"Text\"]"
                  "Cell[\"\\\\begin{x}\\nmore\", \"Text\"]"
                  "Cell[\"Heading\", \"Section\", ExpressionUUID -> \"h\"]"
                  "Cell[\"end\", \"Text\"]"))
         (back (cdr (wolfram-nb-fuzz--round-trip cells))))
    (should (= (length back) 4))
    (should (equal (mapcar (lambda (s) (wolfram-nb-cell-style (wolfram-nb--parse-cell s))) back)
                   '("Text" "Text" "Section" "Text")))))

(ert-deftest wolfram-nb-edge-test-inline-box-next-to-a-url-or-latex ()
  "An inline box right after a URL or \\begin{x} is not swallowed by it."
  (dolist (tail '("\"https://x.y/z\", Cell[BoxData[FractionBox[\"a\", \"3\"]], \"InlineFormula\"]"
                  "\"\\\\begin{x}\", Cell[BoxData[FractionBox[\"a\", \"3\"]], \"InlineFormula\"]"
                  "StyleBox[\"=v=\", \"Courier\"], Cell[BoxData[FractionBox[\"a\", \"3\"]], \"InlineFormula\"]"))
    (let* ((cell (format "Cell[TextData[{%s}], \"Text\", ExpressionUUID -> \"t\"]" tail))
           (back (cadr (cdr (wolfram-nb-fuzz--round-trip (list "Cell[\"b\", \"Text\"]" cell))))))
      (should (string-match-p "InlineFormula" back))
      (should-not (string-match-p "\\[wnb:" back)))))

(ert-deftest wolfram-nb-edge-test-touching-styled-spans-stay-styled ()
  (let* ((cell "Cell[TextData[{StyleBox[\"bold\", \"Bold\"], StyleBox[\"italic\", \"Italic\"], \"x\", StyleBox[\"code\", \"Courier\"]}], \"Text\"]")
         (back (cadr (cdr (wolfram-nb-fuzz--round-trip (list "Cell[\"b\", \"Text\"]" cell))))))
    ;; the style names read here are written as the forms that work
    (should (string-match-p "StyleBox\\[\"bold\", FontWeight->Bold\\]" back))
    (should (string-match-p "StyleBox\\[\"italic\", FontSlant->Italic\\]" back))
    (should (string-match-p "StyleBox\\[\"code\", FontFamily->\"Courier\"\\]" back))
    ;; no marker characters and no invisible separators leak into the file
    (should-not (string-match-p "[\u200b]" back))))

(ert-deftest wolfram-nb-edge-test-invisible-marks-never-reach-the-file ()
  (dolist (body '("a\\\\(b" "\\\\[Alpha]" "x\\\\" "p\\\\\\\\(q"))
    (let ((back (cadr (cdr (wolfram-nb-fuzz--round-trip
                       (list "Cell[\"b\", \"Text\"]"
                             (format "Cell[\"%s\", \"Input\"]" body)))))))
      (should-not (string-match-p "[\u200b\u200c]" back)))))

(ert-deftest wolfram-nb-edge-test-escaped-backslash-reads-back-the-same ()
  "A literal backslash before (, [Alpha] or * is not turned into a character escape."
  (dolist (body '("\\\\(z\\\\)" "a\\\\[Alpha]b" "\\\\*" "\\\\\\[Alpha]"))
    (should (equal (wolfram-nb--escape-string (wolfram-nb--unescape-string body)) body))))

;;; Evaluation never sees the marks

(ert-deftest wolfram-nb-edge-test-code-for-evaluation-has-no-marks ()
  (should (equal (wolfram-nb--code-for-evaluation "a\\\u200c(b \u200c c") "a\\(b \u200c c")))


(defun wolfram-nb-edge--roundtrip-styles (cells)
  "Return the styles after converting the cell strings CELLS to Org and back."
  (mapcar (lambda (s) (wolfram-nb-cell-style (wolfram-nb--parse-cell s)))
          (cdr (wolfram-nb-fuzz--round-trip cells))))

(ert-deftest wolfram-nb-edge-test-title-keeps-its-place ()
  "A Title in the middle of a notebook is not moved to the top."
  (should (equal (wolfram-nb-edge--roundtrip-styles
                  '("Cell[\"a\", \"Text\"]" "Cell[\"T\", \"Title\"]" "Cell[\"b\", \"Text\"]"))
                 '("Text" "Title" "Text"))))

(ert-deftest wolfram-nb-edge-test-list-depths-follow-the-items-before ()
  (should (equal (wolfram-nb-edge--roundtrip-styles
                  '("Cell[\"a\", \"Item\"]" "Cell[\"b\", \"Subitem\"]"
                    "Cell[\"c\", \"Subsubitem\"]" "Cell[\"d\", \"Subitem\"]"
                    "Cell[\"e\", \"Item\"]" "Cell[\"f\", \"Subsubitem\"]"
                    "Cell[\"g\", \"ItemNumbered\"]" "Cell[\"h\", \"SubitemNumbered\"]"))
                 '("Item" "Subitem" "Subsubitem" "Subitem" "Item" "Subsubitem"
                   "ItemNumbered" "SubitemNumbered"))))

(ert-deftest wolfram-nb-edge-test-nested-items-do-not-repeat-their-children ()
  (let ((back (cdr (wolfram-nb-fuzz--round-trip
                    '("Cell[\"top\", \"Item\"]" "Cell[\"mid\", \"Subitem\"]"
                      "Cell[\"low\", \"Subsubitem\"]")))))
    (should (equal (mapcar (lambda (s) (wolfram-nb-cell-content (wolfram-nb--parse-cell s)))
                           back)
                   '("top" "mid" "low")))))

(ert-deftest wolfram-nb-edge-test-styled-span-with-several-pieces ()
  "Bold text holding a link or a target keeps all of its text."
  (with-temp-buffer
    (wolfram-nb-mode)
    (let ((cells (wolfram-nb--org-to-cells "x *one [[http://a.b][c]] two* y\n")))
      (should (= (length cells) 1))
      (should (string-match-p "StyleBox\\[\"one \\[\\[http://a.b\\]\\[c\\]\\] two\", FontWeight->Bold\\]"
                              (car cells))))))

(ert-deftest wolfram-nb-edge-test-link-written-as-it-was ()
  (dolist (link '("[[a][b]]" "[[https://x.y/z][label]]" "[[file:x.org][f]]" "[[x]]"))
    (with-temp-buffer
      (wolfram-nb-mode)
      (let* ((cells (wolfram-nb--org-to-cells (format "see %s here *now*\n" link)))
             (back (wolfram-nb-cell-content (wolfram-nb--parse-cell (car cells)))))
        (should (string-match-p (regexp-quote link) back))))))

;;; Files

(defun wolfram-nb-edge--notebook-file (text &optional coding)
  "Write TEXT to a temporary notebook with CODING and return its name."
  (let ((file (make-temp-file "wolfram-nb-edge" nil ".nb"))
        (coding-system-for-write (or coding 'utf-8-unix)))
    (with-temp-file file (insert text))
    file))

(defconst wolfram-nb-edge--small-notebook
  "Notebook[{\nCell[\"Title\", \"Title\"],\nCell[\"Some text\", \"Text\"],\nCell[BoxData[RowBox[{\"f\", \"[\", RowBox[{\"x\", \",\", \"y\"}], \"]\"}]], \"Input\"]\n}, WindowSize -> {400, 300}]\n"
  "A small notebook.")

(ert-deftest wolfram-nb-edge-test-windows-line-endings ()
  (let ((file (wolfram-nb-edge--notebook-file
               (replace-regexp-in-string "\n" "\r\n" wolfram-nb-edge--small-notebook)
               'no-conversion)))
    (unwind-protect
        (with-temp-buffer
          (wolfram-nb-mode)
          (let ((cells (wolfram-nb--parse-notebook file)))
            (should (= (length cells) 3))
            (should (equal (wolfram-nb-cell-content (nth 1 cells)) "Some text"))
            (should (equal (wolfram-nb-cell-content (nth 2 cells)) "f[x, y]"))
            (should (string-match-p "WindowSize" (or wolfram-nb--notebook-options "")))))
      (delete-file file))))

(ert-deftest wolfram-nb-edge-test-byte-order-mark-and-utf8 ()
  (let ((file (wolfram-nb-edge--notebook-file
               (concat "\ufeff"
                       (replace-regexp-in-string "Some text" "Caf\u00e9 \u65e5\u672c"
                                                 wolfram-nb-edge--small-notebook))
               'utf-8-unix)))
    (unwind-protect
        (with-temp-buffer
          (wolfram-nb-mode)
          (let ((cells (wolfram-nb--parse-notebook file)))
            (should (= (length cells) 3))
            (should (equal (wolfram-nb-cell-content (nth 1 cells)) "Café 日本"))))
      (delete-file file))))

(ert-deftest wolfram-nb-edge-test-save-leaves-no-temporary-file-behind ()
  (let* ((dir (make-temp-file "wolfram-nb-dir" t))
         (file (expand-file-name "n.nb" dir)))
    (unwind-protect
        (progn
          (with-temp-file file (insert "old"))
          (wolfram-nb--write-file-atomically file "new text é")
          (should (equal (with-temp-buffer
                           (let ((coding-system-for-read 'utf-8))
                             (insert-file-contents file))
                           (buffer-string))
                         "new text é"))
          (should (equal (directory-files dir nil "\\`[^.]\\|\\`\\.[^.]") '("n.nb"))))
      (delete-directory dir t))))

(ert-deftest wolfram-nb-edge-test-failed-save-keeps-the-old-notebook ()
  (let* ((dir (make-temp-file "wolfram-nb-dir" t))
         (file (expand-file-name "n.nb" dir)))
    (unwind-protect
        (progn
          (with-temp-file file (insert "precious"))
          (cl-letf (((symbol-function 'rename-file)
                     (lambda (&rest _) (error "Disk full"))))
            (should-error (wolfram-nb--write-file-atomically file "new")))
          (should (equal (with-temp-buffer (insert-file-contents file) (buffer-string))
                         "precious"))
          (should (equal (directory-files dir nil "\\`[^.]") '("n.nb")))
          (should (equal (directory-files dir nil "wolfram-nb-save") nil)))
      (delete-directory dir t))))

;;; Editing in Org

(ert-deftest wolfram-nb-edge-test-copied-cell-gets-no-duplicate-identifier ()
  (let* ((org (concat "#+ATTR_WOLFRAM: ExpressionUUID -> \"same-id\"\n#+begin_src wolfram\n1+1\n#+end_src\n\n"
                      "#+ATTR_WOLFRAM: ExpressionUUID -> \"same-id\"\n#+begin_src wolfram\n1+1\n#+end_src\n"))
         (text (with-temp-buffer
                 (wolfram-nb-mode)
                 (wolfram-nb--cells-to-notebook (wolfram-nb--org-to-cells org)))))
    (should (= (length (split-string text "same-id")) 2))
    (should (= (length (split-string text "Cell\\[")) 3))))

(ert-deftest wolfram-nb-edge-test-a-repeated-identifier-leaves-the-other-options ()
  "Dropping a repeated ExpressionUUID keeps the commas between the options."
  (let ((seen (make-hash-table :test 'equal))
        (cell "Cell[\"a\", \"Text\", ExpressionUUID->\"u2\", CellTags->\"t\"]"))
    (should (equal (wolfram-nb--drop-repeated-uuid cell seen) cell))
    (should (equal (wolfram-nb--drop-repeated-uuid cell seen)
                   "Cell[\"a\", \"Text\", CellTags->\"t\"]"))))

(ert-deftest wolfram-nb-edge-test-a-symbol-in-another-context-is-not-the-identifier ()
  "`$CellContext`ExpressionUUID' is another symbol; only ExpressionUUID is the identifier."
  (let ((seen (make-hash-table :test 'equal))
        (cell (concat "Cell[\"a\", \"InlineFormula\", $CellContext`ExpressionUUID -> \"u1\", "
                      "ExpressionUUID -> \"u2\"]")))
    (should (equal (wolfram-nb--cell-uuid
                    (wolfram-nb--extract-cell-options
                     cell (cdr (wolfram-nb--cell-style-info cell))))
                   "u2"))
    (should (equal (wolfram-nb--drop-repeated-uuid cell seen) cell))
    (should (equal (wolfram-nb--drop-repeated-uuid cell seen)
                   "Cell[\"a\", \"InlineFormula\", $CellContext`ExpressionUUID -> \"u1\"]"))))

(ert-deftest wolfram-nb-edge-test-deleting-and-moving-cells-in-org ()
  (with-temp-buffer
    (wolfram-nb-mode)
    (let* ((cells (let ((file (make-temp-file "wolfram-nb-edge" nil ".nb")))
                    (unwind-protect
                        (progn (with-temp-file file
                                 (insert "Notebook[{Cell[\"One\", \"Section\"], Cell[\"two\", \"Text\"], Cell[\"3+3\", \"Input\"], Cell[\"Four\", \"Section\"]}]"))
                               (wolfram-nb--parse-notebook file))
                      (delete-file file))))
           (org (wolfram-nb--cells-to-org cells)))
      ;; delete the paragraph
      (let ((without (replace-regexp-in-string "two\n\n" "" org)))
        (should (equal (mapcar (lambda (s) (wolfram-nb-cell-style (wolfram-nb--parse-cell s)))
                               (wolfram-nb--org-to-cells without))
                       '("Section" "Input" "Section"))))
      ;; move the code block above the paragraph
      (let* ((moved (replace-regexp-in-string
                     "two\n\n\\(#\\+begin_src wolfram\n3\\+3\n#\\+end_src\n\n\\)" "\\1two\n\n" org)))
        (should (equal (mapcar (lambda (s) (wolfram-nb-cell-style (wolfram-nb--parse-cell s)))
                               (wolfram-nb--org-to-cells moved))
                       '("Section" "Input" "Text" "Section")))))))

(ert-deftest wolfram-nb-edge-test-one-enormous-line-is-kept-aside ()
  (let* ((text (make-string 30000 ?a))
         (cell (format "Cell[\"%s\", \"Text\", ExpressionUUID -> \"long\"]" text))
         (result (wolfram-nb-fuzz--round-trip (list cell))))
    (should (< (apply #'max (mapcar #'length (split-string (car result) "\n"))) 2000))
    (should (string-match-p "Large Cell Block" (car result)))
    (should (equal (cdr result) (list cell)))))

(ert-deftest wolfram-nb-edge-test-long-output-lines-are-cut ()
  (let ((wolfram-nb-max-output-line-length 50)
        (wolfram-nb-max-output-length 100000))
    (let ((cut (wolfram-nb--limit-output (concat "ok\n" (make-string 500 ?y) "\nend"))))
      (should (string-match-p "\\`ok\n" cut))
      (should (string-match-p "<\\.\\.\\. 450 more characters>\nend\\'" cut))
      (should (< (apply #'max (mapcar #'length (split-string cut "\n"))) 80)))))

(ert-deftest wolfram-nb-edge-test-output-is-cut-to-a-limit ()
  (let ((wolfram-nb-max-output-length 100)
        (wolfram-nb-max-output-line-length 100000))
    (should (equal (wolfram-nb--limit-output "short") "short"))
    (let ((cut (wolfram-nb--limit-output (make-string 500 ?x))))
      (should (string-prefix-p (make-string 100 ?x) cut))
      (should (string-match-p "output cut: 100 of 500" cut))
      (should (< (length cut) 200)))))

(ert-deftest wolfram-nb-edge-test-uuid-wrapped-by-the-front-end ()
  "The Front End wraps long strings with a backslash and a newline.  A cell
whose ExpressionUUID is wrapped is still written back as the boxes it had."
  (let ((file (make-temp-file "wolfram-nb-edge" nil ".nb")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "Notebook[{\n"
                    "Cell[BoxData[RowBox[{\"f\", \"[\", \"x\", \"]\"}]], \"Input\",\n"
                    " ExpressionUUID->\"76d23fec-ea85-4295-a92e-\\\n0123456789ab\"]\n"
                    "}]\n"))
          (with-temp-buffer
            (wolfram-nb-mode)
            (let* ((cells (wolfram-nb--parse-notebook file))
                   (back (wolfram-nb--org-to-cells (wolfram-nb--cells-to-org cells))))
              (should (= (length back) 1))
              (should (string-prefix-p "Cell[BoxData[RowBox[" (car back)))
              (should (equal (wolfram-nb--cell-uuid (wolfram-nb-cell-raw-options (car cells)))
                             "76d23fec-ea85-4295-a92e-0123456789ab")))))
      (delete-file file))))

(ert-deftest wolfram-nb-edge-test-plain-text-with-markdown-markers-stays-plain ()
  "A plain string with `* item' and `*word*' lines is not formatting.
Org reads the lines as headlines, where it finds no markup, so the cell once
went through the rich-text path and came back with bold and underlined words."
  (let ((file (make-temp-file "wolfram-nb-edge" nil ".nb"))
        (text "Goals:\\n\\n* Cover *all* reports.\\n\\n* Document any _quirks_ found."))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert (format "Notebook[{\nCell[\"%s\", \"Text\"]\n}]\n" text)))
          (with-temp-buffer
            (wolfram-nb-mode)
            (let ((cells (wolfram-nb--parse-notebook file)))
              (let ((org (wolfram-nb--cells-to-org cells)))
                ;; as an edited cell: the originals are forgotten
                (setq wolfram-nb--box-sources nil)
                (should (equal (wolfram-nb--org-to-cells org)
                               (list (format "Cell[\"%s\", \"Text\"]" text))))))))
      (delete-file file))))

;;; The scanner that finds where an expression ends

(defun wolfram-nb-edge--sexp-end (text)
  "Return how many characters of TEXT the expression at its start covers."
  (with-temp-buffer
    (insert text)
    (goto-char (point-min))
    (wolfram-nb--forward-sexp)
    (1- (point))))

(ert-deftest wolfram-nb-edge-test-scanner-reads-named-characters-outside-strings ()
  "The Front End writes \\[Name] unquoted in code; its ] is not a closing bracket."
  (should (= (wolfram-nb-edge--sexp-end "[a, \\[Alpha], b] tail") 16))
  (should (= (wolfram-nb-edge--sexp-end "[$CellContext`\\[CapitalDelta]x = 1] tail") 35))
  (should (= (wolfram-nb-edge--sexp-end "{\\[Rule], {\\[Times]}} tail") 21)))

(ert-deftest wolfram-nb-edge-test-scanner-skips-strings-and-comments ()
  (should (= (wolfram-nb-edge--sexp-end "{\"a]\", \"\\\"]\"} tail") 13))
  ;; a quote inside a comment is not a string, as the kernel reads comments
  (should (= (wolfram-nb-edge--sexp-end "[(* ] \" *) 1] tail") 13))
  (should (= (wolfram-nb-edge--sexp-end "[(* (* ] *) ] *) 1] tail") 19))
  (should (= (wolfram-nb-edge--sexp-end "\"a\\\"b\" tail") 6)))

(ert-deftest wolfram-nb-edge-test-scanner-signals-when-not-closed ()
  (should-error (wolfram-nb-edge--sexp-end "[a, [b]") :type 'scan-error)
  (should-error (wolfram-nb-edge--sexp-end "[\"open]") :type 'scan-error)
  (should-error (wolfram-nb-edge--sexp-end "x[1]") :type 'scan-error))

(ert-deftest wolfram-nb-edge-test-a-closer-with-no-opener-does-not-loop ()
  "An unbalanced cell once made the argument scanner loop for ever on a `}'."
  (should (stringp (wolfram-nb--extract-head-argument "Cell[a}b, c]" "Cell")))
  (should (listp (wolfram-nb--split-args "a}b, c"))))

(ert-deftest wolfram-nb-edge-test-cell-with-named-characters-in-code-keeps-its-extent ()
  "Such a cell ended early, and the rest of it spilled into the cells after."
  (let* ((dynamic "Cell[BoxData[DynamicModuleBox[{$CellContext`\\[CapitalDelta]x = 1, y = {2}}, \"x\"]], \"Output\"]")
         (cells (list "Cell[\"before\", \"Text\"]" dynamic "Cell[\"after\", \"Text\"]"))
         (file (make-temp-file "wolfram-nb-edge" nil ".nb")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "Notebook[{\n" (string-join cells ",\n") "\n}]\n"))
          (with-temp-buffer
            (wolfram-nb-mode)
            (let ((parsed (wolfram-nb--parse-notebook file)))
              (should (= (length parsed) 3))
              (should (equal (wolfram-nb-cell-content (nth 2 parsed)) "after"))
              (should (equal (mapcar #'substring-no-properties
                                     (wolfram-nb--org-to-cells (wolfram-nb--cells-to-org parsed)))
                             cells)))))
      (delete-file file))))

;;; Found by round-tripping the notebooks the Engine ships

(defun wolfram-nb-edge--parse-text (text)
  "Parse the notebook TEXT; return its cells and the Org view, in a notebook buffer."
  (let ((file (make-temp-file "wolfram-nb-edge" nil ".nb")))
    (unwind-protect
        (progn
          (with-temp-file file (insert text))
          (with-temp-buffer
            (wolfram-nb-mode)
            (let ((cells (wolfram-nb--parse-notebook file)))
              (list cells (wolfram-nb--cells-to-org cells)
                    (mapcar #'substring-no-properties
                            (wolfram-nb--org-to-cells (wolfram-nb--cells-to-org cells)))))))
      (delete-file file))))

(ert-deftest wolfram-nb-edge-test-readable-notebook-is-read ()
  "SaveReadableNotebook puts a newline and indentation after Notebook[ and Cell[."
  (pcase-let ((`(,cells ,org ,back)
               (wolfram-nb-edge--parse-text
                (concat "Notebook[\n {\n  Cell[CellGroupData[{\n"
                        "   Cell[\n    \"Title\", \"Section\"],\n"
                        "   Cell[\n    BoxData[RowBox[{\"1\", \"+\", \"2\"}]], \"Input\"],\n"
                        "   Cell[\n    TextData[{\"a \", StyleBox[\"b\", FontWeight -> Bold]}], \"Text\"]},\n"
                        "   Open]]},\n WindowSize -> {500, 400}]\n"))))
    (should (= (length cells) 3))
    (should (equal (mapcar #'wolfram-nb-cell-style cells) '("Section" "Input" "Text")))
    (should (string-match-p "^1 ?\\+ ?2$" org))
    (should (string-match-p "a \\*b\\*" org))
    (should (= (length back) 3))
    (should (string-match-p "FontWeight ?-> ?Bold" (nth 2 back)))
    ;; and the group is still there when it is saved
    (should (equal (wolfram-nb-cell-group (car cells)) (wolfram-nb-cell-group (nth 2 cells))))))

(ert-deftest wolfram-nb-edge-test-a-style-from-the-stylesheet-keeps-its-boxes ()
  "A style the mode does not know holds BoxData; unedited, it comes back as BoxData."
  (let ((cell "Cell[BoxData[RowBox[{\"f\", \"[\", \"x\", \"]\"}]], \"DeployedWLInput\", CellLabel -> \"In[1]:=\"]"))
    (pcase-let ((`(,_ ,_ ,back) (wolfram-nb-edge--parse-text (format "Notebook[{\n%s\n}]\n" cell))))
      (should (= (length back) 1))
      (should (string-match-p "\\`Cell\\[BoxData\\[RowBox\\[" (car back)))
      (should (string-match-p "\"DeployedWLInput\"" (car back))))))

(ert-deftest wolfram-nb-edge-test-a-cell-without-a-style-is-not-given-one-from-its-boxes ()
  "The text `], \"Name\"' inside the boxes of a style-less cell is not its style."
  (let ((cell (concat "Cell[BoxData[RowBox[{\"f\", \"[\", ButtonBox[\"x\", ButtonFunction :> "
                      "FrontEndExecute[{FrontEnd`NotebookApply[x], \"OpenCloseGroup\"}]], \"]\"}]],\n"
                      " CellMargins -> {{0, 0}, {-1, 2}}]")))
    (should-not (wolfram-nb--cell-style-info cell))
    (pcase-let ((`(,cells ,_ ,back) (wolfram-nb-edge--parse-text (format "Notebook[{\n%s\n}]\n" cell))))
      (should (equal (wolfram-nb-cell-style (car cells)) wolfram-nb--verbatim-style))
      (should (equal back (list cell))))))

(ert-deftest wolfram-nb-edge-test-a-long-string-full-of-escapes-does-not-overflow-the-regexp ()
  "A plain-string cell once went through a regexp that overflowed on such a string."
  (let* ((text (apply #'concat (make-list 40000 "a\\\"b\\n")))
         (cell (format "Cell[\"%s\", \"Text\"]" text)))
    (should (wolfram-nb-cell-p (wolfram-nb--parse-cell cell)))
    ;; a string this long took half a minute while each backslash searched to
    ;; the end of it
    (let ((start (float-time)))
      (pcase-let ((`(,_ ,_ ,back) (wolfram-nb-edge--parse-text (format "Notebook[{\n%s\n}]\n" cell))))
        (should (equal back (list cell))))
      (should (< (- (float-time) start) 10)))))

(ert-deftest wolfram-nb-edge-test-a-line-continuation-between-arguments-is-dropped ()
  "The Front End wraps long cells with a backslash and a newline between arguments."
  (should (equal (wolfram-nb--flatten-options "\"MSG\", \\\n\"x\",\n CellLabel->\"y\"")
                 "\"MSG\", \"x\", CellLabel->\"y\""))
  (should (string-match-p "\\`a, +b\\'" (wolfram-nb--flatten-options "a, \\  \n  b")))
  ;; a backslash that is not a continuation is left alone
  (should (equal (wolfram-nb--flatten-options "\\[Alpha], b") "\\[Alpha], b"))
  ;; and a cell written that way comes back as a notebook the kernel can read
  (let ((cell (concat "Cell[\"text\", \"Message\", \\\n\"MSG\",\n CellLabel->\"During evaluation of In[6]:=\"]")))
    (pcase-let ((`(,_ ,_ ,back) (wolfram-nb-edge--parse-text (format "Notebook[{\n%s\n}]\n" cell))))
      (should (string-match-p "\"Message\", \"MSG\"" (car back)))
      (should-not (string-match-p "\\\\ " (car back))))))

(ert-deftest wolfram-nb-edge-test-list-elements-are-read-whole ()
  (with-temp-buffer
    (insert "{Cell[\"a, b\", \"Text\"], (* a, comment *) TemplateSlot[\"x\", {1, 2}],\n"
            "  Cell[CellGroupData[{Cell[\"c\", \"Text\"]}, Open]], \\[Alpha]}")
    (should (equal (wolfram-nb--list-elements 2 (1- (point-max)))
                   '("Cell[\"a, b\", \"Text\"]" "TemplateSlot[\"x\", {1, 2}]"
                     "Cell[CellGroupData[{Cell[\"c\", \"Text\"]}, Open]]" "\\[Alpha]")))))

(ert-deftest wolfram-nb-edge-test-elements-that-are-not-cells-are-kept ()
  "A template notebook has TemplateSlot among its cells, and a Cell inside one."
  (let* ((slot "TemplateSlot[Cell[\"inside\", \"Text\"]]")
         (expression "TemplateExpression[Cell[\"also inside\", \"Section\"]]")
         (cells (list "Cell[\"before\", \"Text\"]" slot expression "Cell[\"after\", \"Text\"]")))
    (pcase-let ((`(,parsed ,_ ,back)
                 (wolfram-nb-edge--parse-text
                  (format "Notebook[{\n%s\n}]\n" (string-join cells ",\n")))))
      ;; four things, not six: what is inside a template is not a cell of the notebook
      (should (= (length parsed) 4))
      (should (equal back cells))
      (should (equal (cl-remove-if-not #'identity
                                       (mapcar (lambda (c) (and (equal (wolfram-nb-cell-style c)
                                                                       wolfram-nb--verbatim-style)
                                                                (wolfram-nb-cell-content c)))
                                               parsed))
                     (list slot expression))))))

(ert-deftest wolfram-nb-edge-test-a-large-box-cell-comes-back-as-its-boxes ()
  "A BoxData cell whose code is one very long line is kept aside, as its boxes."
  (let* ((items (string-join (make-list 5000 "\"12345\", \",\"") ", "))
         (cell (format "Cell[BoxData[RowBox[{\"{\", %s, \"}\"}]], \"Output\", CellLabel -> \"Out[1]=\"]"
                       items)))
    (pcase-let ((`(,_ ,org ,back) (wolfram-nb-edge--parse-text (format "Notebook[{\n%s\n}]\n" cell))))
      (should (string-match-p "<Large Cell Block" org))
      (should (equal back (list cell))))))

(provide 'test-edge)
;;; test-edge.el ends here
