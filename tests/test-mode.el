;;; test-mode.el --- Comprehensive tests for wolfram-nb-mode -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests covering string ops, parsing, conversion, roundtrips,
;; cell struct, hierarchy, BoxData, TextData, imenu, mode-line, and
;; property-based randomized roundtrip testing.

;;; Code:

(require 'ert)
(require 'cl-lib)

(defvar wolfram-nb-test--dir
  (file-name-directory (or load-file-name buffer-file-name default-directory))
  "Directory containing the test files.")

(defvar wolfram-nb-test--root
  (file-name-directory (directory-file-name wolfram-nb-test--dir))
  "Root directory of the wolfram-nb-mode project.")

(add-to-list 'load-path wolfram-nb-test--root)
(require 'wolfram-nb-mode)

;;; =========================================================
;;; String escaping
;;; =========================================================

(ert-deftest wolfram-nb-test-escape-simple ()
  "Plain ASCII passes through unchanged."
  (should (string= (wolfram-nb--escape-string "hello world") "hello world")))

(ert-deftest wolfram-nb-test-escape-quote ()
  (should (string= (wolfram-nb--escape-string "say \"hi\"") "say \\\"hi\\\"")))

(ert-deftest wolfram-nb-test-escape-backslash ()
  (should (string= (wolfram-nb--escape-string "a\\b") "a\\\\b")))

(ert-deftest wolfram-nb-test-escape-newline ()
  (should (string= (wolfram-nb--escape-string "a\nb") "a\\nb")))

(ert-deftest wolfram-nb-test-escape-tab ()
  (should (string= (wolfram-nb--escape-string "a\tb") "a\\tb")))

(ert-deftest wolfram-nb-test-escape-empty ()
  (should (string= (wolfram-nb--escape-string "") ""))
  (should (string= (wolfram-nb--unescape-string "") "")))

(ert-deftest wolfram-nb-test-unescape-simple ()
  (should (string= (wolfram-nb--unescape-string "hello") "hello")))

(ert-deftest wolfram-nb-test-unescape-quote ()
  (should (string= (wolfram-nb--unescape-string "a\\\"b") "a\"b")))

(ert-deftest wolfram-nb-test-unescape-backslash ()
  (should (string= (wolfram-nb--unescape-string "a\\\\b") "a\\b")))

(ert-deftest wolfram-nb-test-unescape-newline ()
  (should (string= (wolfram-nb--unescape-string "a\\nb") "a\nb")))

(ert-deftest wolfram-nb-test-unescape-tab ()
  (should (string= (wolfram-nb--unescape-string "a\\tb") "a\tb")))

(ert-deftest wolfram-nb-test-escape-roundtrip ()
  "escape then unescape returns original."
  (let ((original "Test \"quoted\" with\\backslash and\nnewline and\ttab"))
    (should (string= (wolfram-nb--unescape-string
                       (wolfram-nb--escape-string original))
                      original))))

(ert-deftest wolfram-nb-test-escape-multiple-special ()
  "String with every special character."
  (let* ((original "\"hello\"\nworld\\end\t!")
         (escaped (wolfram-nb--escape-string original))
         (unescaped (wolfram-nb--unescape-string escaped)))
    (should (string= unescaped original))))

(ert-deftest wolfram-nb-test-escape-backslash-n-literal ()
  "Literal backslash followed by n should roundtrip correctly.
The Mathematica string \\\\\\\\n means backslash-backslash-n, not backslash-newline."
  (let* ((original "path\\name")
         (escaped (wolfram-nb--escape-string original))
         (unescaped (wolfram-nb--unescape-string escaped)))
    (should (string= unescaped original))))

(ert-deftest wolfram-nb-test-escape-consecutive-backslashes ()
  "Multiple consecutive backslashes roundtrip correctly."
  (dolist (s '("\\" "\\\\" "\\\\\\"))
    (should (string= (wolfram-nb--unescape-string
                       (wolfram-nb--escape-string s)) s))))

;; Property-based: random roundtrips
(ert-deftest wolfram-nb-test-escape-random-roundtrip ()
  "Randomized roundtrip test with 100 random strings."
  (dotimes (_ 100)
    (let* ((len (random 50))
           (chars (mapcar (lambda (_)
                            (let ((r (random 6)))
                              (pcase r
                                (0 ?\\)
                                (1 ?\")
                                (2 ?\n)
                                (3 ?\t)
                                (4 (+ ?a (random 26)))
                                (_ (+ ?A (random 26))))))
                          (number-sequence 1 (max 1 len))))
           (original (apply #'string chars)))
      (should (string= (wolfram-nb--unescape-string
                         (wolfram-nb--escape-string original))
                        original)))))

;;; =========================================================
;;; Cell struct
;;; =========================================================

(ert-deftest wolfram-nb-test-cell-struct-create ()
  "Test cl-defstruct cell creation and access."
  (let ((c (wolfram-nb-cell-create :content "Hello" :style "Text")))
    (should (wolfram-nb-cell-p c))
    (should (string= (wolfram-nb-cell-content c) "Hello"))
    (should (string= (wolfram-nb-cell-style c) "Text"))
    (should (null (wolfram-nb-cell-options c)))))

(ert-deftest wolfram-nb-test-cell-struct-with-options ()
  "Test cell with options."
  (let ((c (wolfram-nb-cell-create :content "x" :style "Input"
                                   :options '((cell-label . "In[1]:="))
                                   :raw-options "CellLabel->\"In[1]:=\"")))
    (should (equal (cdr (assq 'cell-label (wolfram-nb-cell-options c)))
                   "In[1]:="))
    (should (string= (wolfram-nb-cell-raw-options c) "CellLabel->\"In[1]:=\""))))

;;; =========================================================
;;; Parsing: parse-cell
;;; =========================================================

(ert-deftest wolfram-nb-test-parse-cell-simple ()
  "Simple text cell."
  (let ((c (wolfram-nb--parse-cell "Cell[\"Hello\", \"Text\"]")))
    (should (wolfram-nb-cell-p c))
    (should (string= (wolfram-nb-cell-content c) "Hello"))
    (should (string= (wolfram-nb-cell-style c) "Text"))))

(ert-deftest wolfram-nb-test-parse-cell-escaped-content ()
  "Cell with escape sequences."
  (let ((c (wolfram-nb--parse-cell "Cell[\"Hello\\nWorld\", \"Text\"]")))
    (should c)
    (should (string= (wolfram-nb-cell-content c) "Hello\nWorld"))))

(ert-deftest wolfram-nb-test-parse-cell-section ()
  (let ((c (wolfram-nb--parse-cell "Cell[\"My Section\", \"Section\"]")))
    (should (string= (wolfram-nb-cell-style c) "Section"))
    (should (string= (wolfram-nb-cell-content c) "My Section"))))

(ert-deftest wolfram-nb-test-parse-cell-with-label ()
  "Cell with CellLabel option."
  (let ((c (wolfram-nb--parse-cell "Cell[\"2+2\", \"Input\", CellLabel->\"In[1]:=\"]")))
    (should c)
    (should (string= (wolfram-nb-cell-style c) "Input"))
    (should (equal (cdr (assq 'cell-label (wolfram-nb-cell-options c)))
                   "In[1]:="))
    (should (string-match-p "CellLabel->\"In\\[1\\]:=\"" (wolfram-nb-cell-raw-options c)))))

(ert-deftest wolfram-nb-test-parse-cell-generic-options ()
  "Cell with arbitrary options."
  (let ((c (wolfram-nb--parse-cell "Cell[\"T\", \"Text\", CellID->123, Background->RGBColor[1,0,0]]")))
    (should c)
    (should (string= (wolfram-nb-cell-content c) "T"))
    (should (string-match-p "CellID->123" (wolfram-nb-cell-raw-options c)))
    (should (string-match-p "Background->RGBColor" (wolfram-nb-cell-raw-options c)))))

(ert-deftest wolfram-nb-test-parse-cell-boxdata ()
  "BoxData cell extracts code."
  (let ((c (wolfram-nb--parse-cell
            "Cell[BoxData[RowBox[{\"x\", \"=\", \"5\"}]], \"Input\"]")))
    (should c)
    (should (string= (wolfram-nb-cell-style c) "Input"))
    ;; Should extract the meaningful strings
    (should (stringp (wolfram-nb-cell-content c)))))

(ert-deftest wolfram-nb-test-parse-cell-textdata ()
  "TextData cell extracts text."
  (let ((c (wolfram-nb--parse-cell
            "Cell[TextData[{\"Hello \", StyleBox[\"world\", FontWeight->\"Bold\"]}], \"Text\"]")))
    (should c)
    (should (string= (wolfram-nb-cell-style c) "Text"))
    (should (string-match-p "Hello" (wolfram-nb-cell-content c)))
    (should (string-match-p "world" (wolfram-nb-cell-content c)))))

(ert-deftest wolfram-nb-test-parse-cell-cellgroupdata-returns-nil ()
  "CellGroupData wrappers return nil from parse-cell."
  (should-not (wolfram-nb--parse-cell "Cell[CellGroupData[{...}]]")))

(defun wolfram-nb-cell-p (obj)
  "Return non-nil if OBJ is a `wolfram-nb-cell` struct."
  (cl-typep obj 'wolfram-nb-cell))

(ert-deftest wolfram-nb-test-parse-cell-invalid ()
  "Invalid strings return nil."
  (should-not (wolfram-nb--parse-cell "not a cell"))
  (should-not (wolfram-nb--parse-cell "")))

(ert-deftest wolfram-nb-test-parse-cell-fallback ()
  "Test fallback/robust parsing of unrecognized cell formats."
  (let ((c (wolfram-nb--parse-cell "Cell[123, \"Text\"]")))
    (should c)
    (should (string= (wolfram-nb-cell-content c) "123"))
    (should (string= (wolfram-nb-cell-style c) "Text")))
  (let ((c (wolfram-nb--parse-cell "Cell[SomeHead[foo, bar], \"MyCustomStyle\"]")))
    (should c)
    (should (string= (wolfram-nb-cell-content c) "SomeHead[foo, bar]"))
    (should (string= (wolfram-nb-cell-style c) "MyCustomStyle"))))

(ert-deftest wolfram-nb-test-parse-cell-dynamic ()
  "DynamicModuleBox returns Output placeholder."
  (let ((c (wolfram-nb--parse-cell "Cell[DynamicModuleBox[stuff], \"Output\"]")))
    (should c)
    (should (string= (wolfram-nb-cell-style c) "Output"))))

(ert-deftest wolfram-nb-test-parse-cell-boxdata-no-celllabel-leak ()
  "BoxData extraction should not include CellLabel from options.
This tests the fix for CellLabel leaking into extracted content.
The cell has CellLabel->\"In[1]:=\" in the options, which should
NOT appear in the extracted code content."
  (let ((c (wolfram-nb--parse-cell
            "Cell[BoxData[RowBox[{\"1\", \"+\", \"1\"}]], \"Input\", CellLabel->\"In[1]:=\"]")))
    (should c)
    (should (string= (wolfram-nb-cell-style c) "Input"))
    ;; The content should be just "1+1", not "1+1In[1]:="
    (should (string= (wolfram-nb-cell-content c) "1+1"))
    (should-not (string-match-p "In\\[1\\]" (wolfram-nb-cell-content c)))))

(ert-deftest wolfram-nb-test-parse-cell-textdata-no-option-leak ()
  "TextData extraction should not include options.
Ensures that even with complex options, TextData content is extracted cleanly."
  (let ((c (wolfram-nb--parse-cell
            "Cell[TextData[{\"Hello \", \"world\"}], \"Text\", CellLabel->\"In[2]:=\", CellID->123]")))
    (should c)
    (should (string= (wolfram-nb-cell-style c) "Text"))
    ;; Should contain the text content only
    (should (string-match-p "Hello" (wolfram-nb-cell-content c)))
    (should (string-match-p "world" (wolfram-nb-cell-content c)))
    ;; Should NOT contain CellLabel option text
    (should-not (string-match-p "In\\[2\\]" (wolfram-nb-cell-content c)))
    (should-not (string-match-p "123" (wolfram-nb-cell-content c)))))

(ert-deftest wolfram-nb-test-parse-cell-long-string-continuation ()
  "Test parsing simple text cells formatted as long strings with line continuation."
  (let ((c (wolfram-nb--parse-cell
            "Cell[\"\\<\\\nline 1 \\\nline 2\\\n\\>\", \"Text\"]")))
    (should c)
    (should (string= (wolfram-nb-cell-style c) "Text"))
    (should (string= (wolfram-nb-cell-content c) "line 1 line 2")))
  (let ((c (wolfram-nb--parse-cell
            "Cell[\"\\<\\\nThe idea will be to migrate all Wyatt[\\\"ERP Reports\\\"] into this framework. \\\nIf we can cover some of the use cases there we can consider the testing to be \\\nsuccessful.\\\n\\>\", \"Text\"]")))
    (should c)
    (should (string= (wolfram-nb-cell-style c) "Text"))
    (should (string= (wolfram-nb-cell-content c) "The idea will be to migrate all Wyatt[\"ERP Reports\"] into this framework. If we can cover some of the use cases there we can consider the testing to be successful."))))

;;; =========================================================
;;; Parsing: find-cell-end
;;; =========================================================

(ert-deftest wolfram-nb-test-find-cell-end-simple ()
  (with-temp-buffer
    (insert "Cell[\"Hi\", \"Text\"] extra")
    (let ((end (wolfram-nb--find-cell-end 1)))
      (should end)
      (should (= (char-before end) ?\])))))

(ert-deftest wolfram-nb-test-find-cell-end-nested-brackets ()
  (with-temp-buffer
    (insert "Cell[BoxData[RowBox[{\"x\"}]], \"Input\"] tail")
    (let ((end (wolfram-nb--find-cell-end 1)))
      (should end)
      (should (= (char-before end) ?\])))))

(ert-deftest wolfram-nb-test-find-cell-end-string-with-brackets ()
  "Brackets inside strings should not affect depth tracking."
  (with-temp-buffer
    (insert "Cell[\"a[b]c\", \"Text\"] end")
    (let ((end (wolfram-nb--find-cell-end 1)))
      (should end)
      (should (string= (buffer-substring end (point-max)) " end")))))

(ert-deftest wolfram-nb-test-find-cell-end-not-a-cell ()
  "Returns nil when not positioned at Cell[."
  (with-temp-buffer
    (insert "NotACell[stuff]")
    (should-not (wolfram-nb--find-cell-end 1))))

;;; =========================================================
;;; CellGroupData
;;; =========================================================

(ert-deftest wolfram-nb-test-is-cellgroupdata ()
  (should (wolfram-nb--is-cellgroupdata "Cell[CellGroupData[{...}]]"))
  (should-not (wolfram-nb--is-cellgroupdata "Cell[\"text\", \"Section\"]")))

(ert-deftest wolfram-nb-test-cgd-simple ()
  (let ((cells (wolfram-nb--extract-cells-from-group
                "Cell[CellGroupData[{Cell[\"A\", \"Section\"],Cell[\"B\", \"Text\"]}]]")))
    (should (= (length cells) 2))
    (should (string= (wolfram-nb-cell-style (nth 0 cells)) "Section"))
    (should (string= (wolfram-nb-cell-content (nth 0 cells)) "A"))
    (should (string= (wolfram-nb-cell-content (nth 1 cells)) "B"))))

(ert-deftest wolfram-nb-test-cgd-nested ()
  (let ((cells (wolfram-nb--extract-cells-from-group
                (concat "Cell[CellGroupData[{"
                        "Cell[\"Outer\", \"Section\"],"
                        "Cell[CellGroupData[{"
                        "Cell[\"Inner\", \"Subsection\"],"
                        "Cell[\"Deep\", \"Text\"]"
                        "}]]"
                        "}]]"))))
    (should (= (length cells) 3))
    (should (string= (wolfram-nb-cell-content (nth 0 cells)) "Outer"))
    (should (string= (wolfram-nb-cell-content (nth 1 cells)) "Inner"))
    (should (string= (wolfram-nb-cell-content (nth 2 cells)) "Deep"))))

(ert-deftest wolfram-nb-test-cgd-empty ()
  (let ((cells (wolfram-nb--extract-cells-from-group "Cell[CellGroupData[{}]]")))
    (should (= (length cells) 0))))

(ert-deftest wolfram-nb-test-cgd-with-escaped-strings ()
  (let ((cells (wolfram-nb--extract-cells-from-group
                (concat "Cell[CellGroupData[{"
                        "Cell[\"Hello\\nWorld\", \"Text\"],"
                        "Cell[\"Quote: \\\"test\\\"\", \"Text\"]"
                        "}]]"))))
    (should (= (length cells) 2))
    (should (string= (wolfram-nb-cell-content (nth 0 cells)) "Hello\nWorld"))
    (should (string= (wolfram-nb-cell-content (nth 1 cells)) "Quote: \"test\""))))

(ert-deftest wolfram-nb-test-cgd-with-code ()
  (let ((cells (wolfram-nb--extract-cells-from-group
                (concat "Cell[CellGroupData[{"
                        "Cell[\"Demo\", \"Section\"],"
                        "Cell[\"x = 5\", \"Input\"],"
                        "Cell[\"5\", \"Output\"]"
                        "}]]"))))
    (should (= (length cells) 3))
    (should (string= (wolfram-nb-cell-style (nth 1 cells)) "Input"))
    (should (string= (wolfram-nb-cell-style (nth 2 cells)) "Output"))))

;;; =========================================================
;;; Parse notebook
;;; =========================================================

(ert-deftest wolfram-nb-test-parse-notebook ()
  "Parse example notebook file."
  (let ((cells (wolfram-nb--parse-notebook
                (expand-file-name "examples/simple.nb" wolfram-nb-test--root))))
    (should (> (length cells) 0))
    (dolist (c cells)
      (should (wolfram-nb-cell-p c))
      (should (wolfram-nb-cell-style c))
      (should (wolfram-nb-cell-content c)))))

(ert-deftest wolfram-nb-test-parse-notebook-cell-count ()
  "simple.nb should have the expected number of cells."
  (let ((cells (wolfram-nb--parse-notebook
                (expand-file-name "examples/simple.nb" wolfram-nb-test--root))))
    (should (= (length cells) 19))))

(ert-deftest wolfram-nb-test-parse-notebook-invalid-signals-error ()
  (let ((f (make-temp-file "wolfram-nb-test" nil ".nb" "not a notebook")))
    (unwind-protect
        (should-error (wolfram-nb--parse-notebook f) :type 'wolfram-nb-parse-error)
      (delete-file f))))

(ert-deftest wolfram-nb-test-parse-notebook-with-cgd ()
  "Notebook with CellGroupData is properly unwrapped."
  (let ((f (make-temp-file "wolfram-nb-test" nil ".nb")))
    (with-temp-file f
      (insert "Notebook[{\n"
              "Cell[CellGroupData[{"
              "Cell[\"Title\", \"Title\"],"
              "Cell[\"Body\", \"Text\"]"
              "}]]\n}]\n"))
    (unwind-protect
        (let ((cells (wolfram-nb--parse-notebook f)))
          (should (= (length cells) 2))
          (should (string= (wolfram-nb-cell-style (nth 0 cells)) "Title"))
          (should (string= (wolfram-nb-cell-style (nth 1 cells)) "Text")))
      (delete-file f))))

(ert-deftest wolfram-nb-test-parse-notebook-empty ()
  "Empty notebook returns empty list."
  (let ((f (make-temp-file "wolfram-nb-test" nil ".nb" "Notebook[{\n}]\n")))
    (unwind-protect
        (should (= (length (wolfram-nb--parse-notebook f)) 0))
      (delete-file f))))

;;; =========================================================
;;; Cell -> Org conversion
;;; =========================================================

(ert-deftest wolfram-nb-test-cell-to-org-title ()
  (should (string= (wolfram-nb--cell-to-org
                     (wolfram-nb-cell-create :content "T" :style "Title"))
                    "#+TITLE: T\n\n")))

(ert-deftest wolfram-nb-test-cell-to-org-subtitle ()
  (should (string= (wolfram-nb--cell-to-org
                     (wolfram-nb-cell-create :content "S" :style "Subtitle"))
                    "#+SUBTITLE: S\n\n")))

(ert-deftest wolfram-nb-test-cell-to-org-chapter ()
  (should (string= (wolfram-nb--cell-to-org
                     (wolfram-nb-cell-create :content "C" :style "Chapter"))
                    "* C\n")))

(ert-deftest wolfram-nb-test-cell-to-org-section ()
  (should (string= (wolfram-nb--cell-to-org
                     (wolfram-nb-cell-create :content "S" :style "Section"))
                    "** S\n")))

(ert-deftest wolfram-nb-test-cell-to-org-subsection ()
  (should (string= (wolfram-nb--cell-to-org
                     (wolfram-nb-cell-create :content "SS" :style "Subsection"))
                    "*** SS\n")))

(ert-deftest wolfram-nb-test-cell-to-org-subsubsection ()
  (should (string= (wolfram-nb--cell-to-org
                     (wolfram-nb-cell-create :content "SSS" :style "Subsubsection"))
                    "**** SSS\n")))

(ert-deftest wolfram-nb-test-cell-to-org-text ()
  (should (string= (wolfram-nb--cell-to-org
                     (wolfram-nb-cell-create :content "Hello" :style "Text"))
                    "Hello\n\n")))

(ert-deftest wolfram-nb-test-cell-to-org-item ()
  (should (string= (wolfram-nb--cell-to-org
                     (wolfram-nb-cell-create :content "• Thing" :style "Item"))
                    "- Thing\n")))

(ert-deftest wolfram-nb-test-cell-to-org-subitem ()
  (should (string= (wolfram-nb--cell-to-org
                     (wolfram-nb-cell-create :content "Sub" :style "Subitem"))
                    "  - Sub\n")))

(ert-deftest wolfram-nb-test-cell-to-org-subsubitem ()
  (should (string= (wolfram-nb--cell-to-org
                     (wolfram-nb-cell-create :content "Deep" :style "Subsubitem"))
                    "    - Deep\n")))

(ert-deftest wolfram-nb-test-cell-to-org-code ()
  (let ((org (wolfram-nb--cell-to-org
              (wolfram-nb-cell-create :content "x=5" :style "Code"))))
    (should (string-match-p "begin_src wolfram" org))
    (should (string-match-p "x=5" org))
    (should (string-match-p "end_src" org))))

(ert-deftest wolfram-nb-test-cell-to-org-input ()
  (let ((org (wolfram-nb--cell-to-org
              (wolfram-nb-cell-create :content "2+2" :style "Input"))))
    (should (string-match-p "begin_src wolfram" org))))

(ert-deftest wolfram-nb-test-cell-to-org-output ()
  (let ((org (wolfram-nb--cell-to-org
              (wolfram-nb-cell-create :content "4" :style "Output"))))
    (should (string-match-p "begin_example" org))
    (should (string-match-p "4" org))))

(ert-deftest wolfram-nb-test-cell-to-org-unknown ()
  "Unknown styles produce a wolfram-raw source block fallback."
  (let ((org (wolfram-nb--cell-to-org
              (wolfram-nb-cell-create :content "mystery" :style "WeirdStyle"))))
    (should (string-match-p "#\\+ATTR_WOLFRAM: :style \"WeirdStyle\"" org))
    (should (string-match-p "begin_src wolfram-raw" org))
    (should (string-match-p "mystery" org))))

(ert-deftest wolfram-nb-test-cells-to-org-multiple ()
  (let* ((cells (list (wolfram-nb-cell-create :content "Sec" :style "Section")
                      (wolfram-nb-cell-create :content "Hello" :style "Text")
                      (wolfram-nb-cell-create :content "x=1" :style "Input")))
         (org (wolfram-nb--cells-to-org cells)))
    (should (string-match-p "\\*\\* Sec" org))
    (should (string-match-p "Hello" org))
    (should (string-match-p "begin_src wolfram" org))))

;;; =========================================================
;;; Hierarchy mapping (full chain)
;;; =========================================================

(ert-deftest wolfram-nb-test-hierarchy-cell-to-org ()
  "Verify the complete hierarchy mapping."
  (let ((cases '(("Title" "^#\\+TITLE:")
                 ("Subtitle" "^#\\+SUBTITLE:")
                 ("Chapter" "^\\* ")
                 ("Section" "^\\*\\* ")
                 ("Subsection" "^\\*\\*\\* ")
                 ("Subsubsection" "^\\*\\*\\*\\* "))))
    (dolist (case cases)
      (let ((org (wolfram-nb--cell-to-org
                  (wolfram-nb-cell-create :content "X" :style (car case)))))
        (should (string-match-p (cadr case) org))))))

;;; =========================================================
;;; Org -> Cells conversion
;;; =========================================================

(ert-deftest wolfram-nb-test-org-to-cells-basic ()
  (let ((cells (wolfram-nb--org-to-cells "** Section\n\nHello\n")))
    (should (>= (length cells) 2))
    (should (cl-some (lambda (c) (string-match-p "\"Section\"" c)) cells))
    (should (cl-some (lambda (c) (string-match-p "\"Text\"" c)) cells))))

(ert-deftest wolfram-nb-test-org-to-cells-title ()
  (let ((cells (wolfram-nb--org-to-cells "#+TITLE: My Notebook\n")))
    (should (cl-some (lambda (c) (string-match-p "\"Title\"" c)) cells))))

(ert-deftest wolfram-nb-test-org-to-cells-subtitle ()
  (let ((cells (wolfram-nb--org-to-cells "#+SUBTITLE: Sub\n")))
    (should (cl-some (lambda (c) (string-match-p "\"Subtitle\"" c)) cells))))

(ert-deftest wolfram-nb-test-org-to-cells-hierarchy ()
  (let ((cells (wolfram-nb--org-to-cells
                "* Chapter\n** Section\n*** Subsection\n**** Subsubsection\n")))
    (should (cl-some (lambda (c) (string-match-p "\"Chapter\"" c)) cells))
    (should (cl-some (lambda (c) (string-match-p "\"Section\"" c)) cells))
    (should (cl-some (lambda (c) (string-match-p "\"Subsection\"" c)) cells))
    (should (cl-some (lambda (c) (string-match-p "\"Subsubsection\"" c)) cells))))

(ert-deftest wolfram-nb-test-org-to-cells-src-to-input ()
  "Wolfram src blocks become Input cells."
  (let ((cells (wolfram-nb--org-to-cells "#+begin_src wolfram\n2+2\n#+end_src\n")))
    (should (= (length cells) 1))
    (should (string-match-p "\"Input\"" (car cells)))))

(ert-deftest wolfram-nb-test-org-to-cells-example-to-output ()
  (let ((cells (wolfram-nb--org-to-cells "#+begin_example\n4\n#+end_example\n")))
    (should (= (length cells) 1))
    (should (string-match-p "\"Output\"" (car cells)))))

(ert-deftest wolfram-nb-test-org-to-cells-raw-fallback ()
  "Test parsing wolfram-raw src blocks back to cells with custom styles and options."
  (let ((cells (wolfram-nb--org-to-cells
                "#+ATTR_WOLFRAM: :style \"CustomStyle\" :options \"CellLabel->\\\"1\\\"\"\n#+begin_src wolfram-raw\nBoxData[GraphicsBox[Circle[]]]\n#+end_src\n")))
    (should (= (length cells) 1))
    (should (string-match-p "Cell\\[BoxData\\[GraphicsBox\\[Circle\\[\\]\\]\\], \"CustomStyle\", CellLabel->\"1\"\\]" (car cells)))))

(ert-deftest wolfram-nb-test-org-to-cells-items ()
  (let ((cells (wolfram-nb--org-to-cells "- A\n- B\n- C\n")))
    (should (= (length cells) 3))
    (dolist (c cells)
      (should (string-match-p "\"Item\"" c)))))

;;; =========================================================
;;; Notebook serialization
;;; =========================================================

(ert-deftest wolfram-nb-test-cells-to-notebook-format ()
  (let ((nb (wolfram-nb--cells-to-notebook
             (list "Cell[\"A\", \"Section\"]" "Cell[\"B\", \"Text\"]"))))
    (should (string-match-p "\\`Notebook\\[{" nb))
    (should (string-match-p "}\\]" nb))
    (should (string-match-p "Cell\\[\"A\", \"Section\"\\]" nb))))

(ert-deftest wolfram-nb-test-cells-to-notebook-with-options ()
  (let ((nb (wolfram-nb--cells-to-notebook
             (list "Cell[\"A\", \"Text\"]")
             "FrontEndVersion->\"14.0\"")))
    (should (string-match-p "FrontEndVersion" nb))))

(ert-deftest wolfram-nb-test-cells-to-notebook-empty ()
  (let ((nb (wolfram-nb--cells-to-notebook '())))
    (should (string-match-p "Notebook\\[{" nb))))

;;; =========================================================
;;; Make-cell
;;; =========================================================

(ert-deftest wolfram-nb-test-make-cell-string ()
  (should (string= (wolfram-nb--make-cell-string "Hello" "Text")
                    "Cell[\"Hello\", \"Text\"]")))

(ert-deftest wolfram-nb-test-make-cell-string-escapes ()
  (let ((c (wolfram-nb--make-cell-string "line1\nline2" "Text")))
    (should (string-match-p "\\\\n" c))
    (should (string-match-p "\"Text\"" c))))

(ert-deftest wolfram-nb-test-make-cell-string-trims ()
  (should (string= (wolfram-nb--make-cell-string "  spaced  " "Text")
                    "Cell[\"spaced\", \"Text\"]")))

;;; =========================================================
;;; Roundtrip tests
;;; =========================================================

(ert-deftest wolfram-nb-test-roundtrip-simple-nb ()
  "Parse simple.nb -> org -> cells -> notebook, verify structure."
  (let* ((cells1 (wolfram-nb--parse-notebook
                  (expand-file-name "examples/simple.nb" wolfram-nb-test--root)))
         (org-text (wolfram-nb--cells-to-org cells1))
         (cells2 (wolfram-nb--org-to-cells org-text))
         (nb (wolfram-nb--cells-to-notebook cells2)))
    (should (> (length cells1) 0))
    (should (> (length cells2) 0))
    (should (string-match-p "Notebook\\[{" nb))))

(ert-deftest wolfram-nb-test-roundtrip-title-preservation ()
  (let* ((cells (list (wolfram-nb-cell-create :content "My Title" :style "Title")
                      (wolfram-nb-cell-create :content "Intro" :style "Section")))
         (org (wolfram-nb--cells-to-org cells))
         (new-cells (wolfram-nb--org-to-cells org)))
    (should (string-match-p "#\\+TITLE: My Title" org))
    (should (cl-some (lambda (c) (string-match-p "\"Title\"" c)) new-cells))))

(ert-deftest wolfram-nb-test-roundtrip-all-styles ()
  "All cell styles survive org roundtrip via file."
  (let* ((org-text (concat
                    "#+TITLE: Test\n\n"
                    "* Chapter\n\n"
                    "** Section\n\n"
                    "Text here.\n\n"
                    "*** Subsection\n\n"
                    "**** Subsubsection\n\n"
                    "- Item\n\n"
                    "#+begin_src wolfram\nPlot[x,{x,0,1}]\n#+end_src\n\n"
                    "#+begin_example\nresult\n#+end_example\n"))
         (cells (wolfram-nb--org-to-cells org-text))
         (f (make-temp-file "wolfram-nb-rt" nil ".nb")))
    (with-temp-file f (insert (wolfram-nb--cells-to-notebook cells)))
    (unwind-protect
        (let* ((cells2 (wolfram-nb--parse-notebook f))
               (styles (mapcar #'wolfram-nb-cell-style cells2)))
          (should (member "Title" styles))
          (should (member "Chapter" styles))
          (should (member "Section" styles))
          (should (member "Subsection" styles))
          (should (member "Subsubsection" styles))
          (should (member "Text" styles))
          (should (member "Item" styles))
          (should (member "Input" styles))
          (should (member "Output" styles)))
      (delete-file f))))

;;; =========================================================
;;; Phase 2: Core Org-Mode Markup Support
;;; =========================================================

(ert-deftest wolfram-nb-test-phase2-numbered-lists ()
  "Test numbered lists bidirectional mapping."
  ;; Cell -> Org
  (let ((c1 (wolfram-nb--parse-cell "Cell[\"Step 1\", \"ItemNumbered\"]"))
        (c2 (wolfram-nb--parse-cell "Cell[\"Step 2\", \"SubitemNumbered\"]")))
    (should (string= (wolfram-nb--cell-to-org c1) "1. Step 1\n"))
    (should (string= (wolfram-nb--cell-to-org c2) "  1. Step 2\n")))
  ;; Org -> Cell
  (let ((cells (wolfram-nb--org-to-cells "1. Bullet One\n  1. Nested One\n")))
    (should (= (length cells) 2))
    (should (string-match-p "\"ItemNumbered\"" (car cells)))
    (should (string-match-p "\"SubitemNumbered\"" (cadr cells)))))

(ert-deftest wolfram-nb-test-phase2-rich-text ()
  "Test bold, italic, underline, verbatim inline markup."
  ;; Org -> Cell
  (let ((cells (wolfram-nb--org-to-cells "Plain *bold* and /italic/ and _under_ and =code=.")))
    (should (= (length cells) 1))
    ;; Should generate a TextData wrapper
    (should (string-match-p "TextData" (car cells)))
    (should (string-match-p "StyleBox.*Bold" (car cells)))
    (should (string-match-p "StyleBox.*Italic" (car cells)))
    (should (string-match-p "StyleBox.*Underlined" (car cells)))
    (should (string-match-p "StyleBox.*Courier" (car cells))))
  ;; Cell -> Org
  (let* ((cell (wolfram-nb--parse-cell "Cell[TextData[{\"Plain \", StyleBox[\"bold\", \"Bold\"], \" and \", StyleBox[\"italic\", \"Italic\"], \" and \", StyleBox[\"under\", \"Underlined\"], \" and \", StyleBox[\"code\", \"Courier\"], \".\"}], \"Text\"]"))
         (org (wolfram-nb--cell-to-org cell)))
    (should (string-match-p "\\*bold\\*" org))
    (should (string-match-p "/italic/" org))
    (should (string-match-p "_under_" org))
    (should (string-match-p "=code=" org))))

(ert-deftest wolfram-nb-test-phase2-links ()
  "Test plain and descriptive links bidirectional preservation."
  ;; Org -> Cell
  (let ((cells (wolfram-nb--org-to-cells "Check [[file:img.png]] or [[https://wolfram.com][Wolfram]].")))
    (should (= (length cells) 1))
    (should (string-match-p "\\[\\[file:img.png\\]\\]" (car cells)))
    (should (string-match-p "\\[\\[https:.*Wolfram\\]\\]" (car cells))))
  ;; Cell -> Org
  (let* ((cell (wolfram-nb-cell-create
                :style "Text"
                :content "Check [[file:img.png]] or [[https://wolfram.com][Wolfram]]."))
         (org (wolfram-nb--cell-to-org cell)))
    (should (string-match-p "\\[\\[file:img.png\\]\\]" org))
    (should (string-match-p "\\[\\[https://wolfram.com\\]\\[Wolfram\\]\\]" org))))

(ert-deftest wolfram-nb-test-phase2-document-blocks ()
  "Test quotes, tables, and horizontal rules bidirectional support."
  ;; Org -> Cell
  (let ((cells (wolfram-nb--org-to-cells "#+begin_quote\nThis is a quote.\n#+end_quote\n\n| Col A | Col B |\n|---|---|\n| 1 | 2 |\n\n-----\n")))
    (should (= (length cells) 3))
    (should (string-match-p "\"Quote\"" (car cells)))
    (should (string-match-p "\"Text\"" (cadr cells)))
    (should (string-match-p "\"Text\"" (caddr cells)))
    (should (string-match-p "This is a quote" (car cells)))
    (should (string-match-p "Col A" (cadr cells)))
    (should (string-match-p "----" (caddr cells))))
  ;; Cell -> Org (Quote)
  (let ((org (wolfram-nb--cell-to-org (wolfram-nb-cell-create :content "Quote text" :style "Quote"))))
    (should (string-match-p "begin_quote" org))
    (should (string-match-p "Quote text" org))))

;;; =========================================================
;;; Format output
;;; =========================================================

(ert-deftest wolfram-nb-test-format-output-plain ()
  (should (string= (wolfram-nb--format-output "42") "42")))

(ert-deftest wolfram-nb-test-format-output-graphics ()
  (should (string-match-p "Mathematica" (wolfram-nb--format-output "Graphics[...]")))
  (should (string-match-p "Mathematica" (wolfram-nb--format-output "Graphics3D[...]")))
  (should (string-match-p "Mathematica" (wolfram-nb--format-output "Image[...]"))))

;;; =========================================================
;;; Imenu
;;; =========================================================

(ert-deftest wolfram-nb-test-imenu-index ()
  "Imenu creates index from headings and src blocks."
  (with-temp-buffer
    (wolfram-nb-mode)
    (insert "* Chapter\n** Section\n#+begin_src wolfram\nx\n#+end_src\n")
    (let ((index (wolfram-nb--imenu-create-index)))
      (should (>= (length index) 3)))))

(ert-deftest wolfram-nb-test-phase3-imenu-style-extraction ()
  "Test that Imenu extracts styles from wolfram-raw blocks."
  (with-temp-buffer
    (wolfram-nb-mode)
    (insert "#+ATTR_WOLFRAM: :style \"MyCustomStyle\"\n#+begin_src wolfram-raw\nBoxData[...]\n#+end_src\n")
    (let ((index (wolfram-nb--imenu-create-index)))
      (should (= (length index) 1))
      (should (string-match-p "MyCustomStyle" (car (car index)))))))

;;; =========================================================
;;; Visual Overlays & Inline Previews
;;; =========================================================

(ert-deftest wolfram-nb-test-overlays-folding-and-toggling ()
  "Test raw block folding overlay creation and toggling."
  (with-temp-buffer
    (wolfram-nb-mode)
    (insert "#+begin_src wolfram-raw\nBoxData[SomeGraphicsBox[]]\n#+end_src\n")
    ;; Apply overlays
    (wolfram-nb-apply-buffer-overlays)
    (should (= (length wolfram-nb--overlays) 2)) ;; 1 fold overlay + 1 preview overlay
    
    ;; Verify fold overlay is folded by default
    (let ((fold-ov (car (cl-member-if (lambda (ov) (overlay-get ov 'wolfram-nb-fold)) wolfram-nb--overlays)))
          (preview-ov (car (cl-member-if (lambda (ov) (overlay-get ov 'wolfram-nb-preview)) wolfram-nb--overlays))))
      (should fold-ov)
      (should (overlay-get fold-ov 'folded))
      (should (overlay-get fold-ov 'display))
      (should (overlay-get preview-ov 'invisible))
      
      ;; Toggle fold
      (goto-char (overlay-start fold-ov))
      (wolfram-nb-toggle-block-at-point)
      
      ;; Verify expanded
      (should-not (overlay-get fold-ov 'folded))
      (should-not (overlay-get fold-ov 'display))
      (should-not (overlay-get preview-ov 'invisible)))
    
    ;; Clear overlays
    (wolfram-nb-clear-overlays)
    (should-not wolfram-nb--overlays)))

(ert-deftest wolfram-nb-test-overlays-evaluation-rendering ()
  "Test that evaluation outputs of graphics trigger overlay rendering."
  (with-temp-buffer
    (wolfram-nb-mode)
    (insert "#+begin_example\nPlot[x, {x, 0, 1}]\n#+end_example\n")
    (let ((wolfram-nb-rasterize-graphics t))
      (wolfram-nb--render-evaluation-output (point-min) (point-max) "Plot[x, {x, 0, 1}]")
      (should (= (length wolfram-nb--overlays) 1))
      (should (overlay-get (car wolfram-nb--overlays) 'wolfram-nb-result))
      (wolfram-nb-clear-overlays))))

(ert-deftest wolfram-nb-test-overlays-toggle-command ()
  "Test the interactive toggle-overlays command."
  (with-temp-buffer
    (wolfram-nb-mode)
    (insert "#+begin_src wolfram-raw\nBoxData[SomeGraphicsBox[]]\n#+end_src\n")
    (should-not wolfram-nb--overlays)
    (wolfram-nb-toggle-overlays)
    (should (= (length wolfram-nb--overlays) 2))
    (wolfram-nb-toggle-overlays)
    (should-not wolfram-nb--overlays)))

;;; =========================================================
;;; =========================================================
;;; Stress / performance
;;; =========================================================

(ert-deftest wolfram-nb-test-stress-1000-cells ()
  "Generate and parse a notebook with 1000 cells."
  (let ((f (make-temp-file "wolfram-nb-stress" nil ".nb")))
    (with-temp-file f
      (insert "Notebook[{\n")
      (dotimes (i 1000)
        (insert (format "Cell[\"Cell %d content\", \"Text\"]" i))
        (when (< i 999) (insert ",\n")))
      (insert "\n}]\n"))
    (unwind-protect
        (let ((cells (wolfram-nb--parse-notebook f)))
          (should (= (length cells) 1000)))
      (delete-file f))))

;;; =========================================================
;;; Error types
;;; =========================================================

(ert-deftest wolfram-nb-test-error-hierarchy ()
  "Custom errors inherit correctly."
  (should (get 'wolfram-nb-error 'error-conditions))
  (should (memq 'wolfram-nb-error
                 (get 'wolfram-nb-parse-error 'error-conditions)))
  (should (memq 'wolfram-nb-error
                 (get 'wolfram-nb-eval-error 'error-conditions))))

;;; =========================================================
;;; Byte-compilation
;;; =========================================================

(ert-deftest wolfram-nb-test-byte-compile-clean ()
  "The main file byte-compiles without warnings."
  (let* ((el-file (expand-file-name "wolfram-nb-mode.el" wolfram-nb-test--root))
         (byte-compile-error-on-warn t)
         (result (byte-compile-file el-file)))
    (should result)
    ;; Clean up .elc
    (let ((elc (concat el-file "c")))
      (when (file-exists-p elc)
        (delete-file elc)))))

(provide 'test-mode)
;;; test-mode.el ends here
