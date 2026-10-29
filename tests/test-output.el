;;; test-output.el --- Tests for evaluation output and graphics cells -*- lexical-binding: t; -*-

;;; Commentary:
;; Everything here runs without a Wolfram kernel: results are handed to the
;; output writer as plists, and evaluation is stubbed where a command would
;; otherwise call out.

;;; Code:

(require 'ert)
(require 'cl-lib)
(add-to-list 'load-path
             (file-name-directory
              (directory-file-name
               (file-name-directory (or load-file-name buffer-file-name default-directory)))))
(require 'wolfram-nb-mode)

(defconst wolfram-nb-test--png
  (base64-decode-string
   "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")
  "A 1x1 PNG.")

(defconst wolfram-nb-test--boxes "GraphicsBox[{Circle[{0, 0}]}]"
  "Boxes of a small graphic.")

(defmacro wolfram-nb-test--in-buffer (text &rest body)
  "Run BODY in a `wolfram-nb-mode' buffer holding TEXT, kernel disabled."
  (declare (indent 1))
  `(with-temp-buffer
     (let ((wolfram-nb-use-kernel nil)
           (wolfram-nb-rasterize-graphics nil))
       (wolfram-nb-mode)
       (insert ,text)
       (goto-char (point-min))
       ,@body)))

(defun wolfram-nb-test--count (regexp)
  "Count the matches of REGEXP in the buffer."
  (save-excursion
    (goto-char (point-min))
    (let ((n 0))
      (while (re-search-forward regexp nil t) (setq n (1+ n)))
      n)))

;;; Results

(ert-deftest wolfram-nb-output-test-png-p ()
  (should (wolfram-nb--png-p wolfram-nb-test--png))
  (should-not (wolfram-nb--png-p "plain"))
  (should-not (wolfram-nb--png-p nil)))

(ert-deftest wolfram-nb-output-test-normalize-result ()
  (should (equal (wolfram-nb--normalize-result "4") '(:status "ok" :result "4")))
  (should (equal (plist-get (wolfram-nb--normalize-result wolfram-nb-test--png) :png)
                 wolfram-nb-test--png)))

(ert-deftest wolfram-nb-output-test-result-text ()
  (should (equal (wolfram-nb--result-text
                  '(:stdout "out\n" :messages "\nf::bad: oops" :result "2"))
                 "out\nf::bad: oops\n2"))
  (should (equal (wolfram-nb--result-text '(:result "")) ""))
  (should (equal (wolfram-nb--result-text '(:stdout nil :result "x")) "x")))

(ert-deftest wolfram-nb-output-test-kernel-code-and-flags ()
  (should (equal (wolfram-nb--kernel-code "a; b" nil) "a; b"))
  (should (equal (wolfram-nb--kernel-code "a; b" "JSON")
                 "ExportString[(a; b), \"JSON\"]"))
  (should (equal (wolfram-nb--kernel-code "x" "png") "x"))
  (should (equal (wolfram-nb--kernel-flags "PNG") "pb"))
  (should (equal (wolfram-nb--kernel-flags nil) "gb")))

(ert-deftest wolfram-nb-output-test-timeout-is-an-eval-error ()
  (should-error (wolfram-nb--check-status '(:status "timeout" :seconds 30))
                :type 'wolfram-nb-eval-error)
  (should (wolfram-nb--check-status '(:status "ok"))))

;;; Text output

(ert-deftest wolfram-nb-output-test-text-output-inserted ()
  (wolfram-nb-test--in-buffer "#+begin_src wolfram\n2+2\n#+end_src\n\nNext paragraph.\n"
    (wolfram-nb--apply-eval-result (save-excursion (re-search-forward "#\\+end_src\n\n") (point))
                                   '(:status "ok" :result "4") "2+2")
    (should (string-match-p "#\\+end_src\n\n#\\+begin_example\n4\n#\\+end_example\n\nNext paragraph"
                            (buffer-string)))))

(ert-deftest wolfram-nb-output-test-reevaluation-replaces-output ()
  (wolfram-nb-test--in-buffer "#+begin_src wolfram\n2+2\n#+end_src\n\n"
    (let ((end (point-max)))
      (wolfram-nb--apply-eval-result end '(:status "ok" :result "4") "2+2")
      (wolfram-nb--apply-eval-result end '(:status "ok" :result "five") "2+2")
      (should (= (wolfram-nb-test--count "begin_example") 1))
      (should (string-match-p "five" (buffer-string)))
      (should-not (string-match-p "^4$" (buffer-string))))))

(ert-deftest wolfram-nb-output-test-empty-result-leaves-no-block ()
  "Assignments like x=5; print nothing, so no empty block is added."
  (wolfram-nb-test--in-buffer "#+begin_src wolfram\nx=5;\n#+end_src\n\n"
    (let ((end (point-max)))
      (wolfram-nb--apply-eval-result end '(:status "ok" :result "") "x=5;")
      (should (= (wolfram-nb-test--count "begin_example") 0))
      ;; And a stale output is removed when the new result is empty.
      (wolfram-nb--apply-eval-result end '(:status "ok" :result "old") "x=5;")
      (should (= (wolfram-nb-test--count "begin_example") 1))
      (wolfram-nb--apply-eval-result end '(:status "ok" :result "") "x=5;")
      (should (= (wolfram-nb-test--count "begin_example") 0)))))

(ert-deftest wolfram-nb-output-test-print-and-messages-shown ()
  (wolfram-nb-test--in-buffer "#+begin_src wolfram\nPrint[1]; 2\n#+end_src\n\n"
    (wolfram-nb--apply-eval-result
     (point-max) '(:status "ok" :stdout "1" :messages "\nf::bad: oops" :result "2")
     "Print[1]; 2")
    (should (string-match-p "begin_example\n1\nf::bad: oops\n2\n#\\+end_example"
                            (buffer-string)))))

(ert-deftest wolfram-nb-output-test-block-without-trailing-newline ()
  (wolfram-nb-test--in-buffer "#+begin_src wolfram\n2+2\n#+end_src"
    (wolfram-nb--apply-eval-result (point-max) '(:status "ok" :result "4") "2+2")
    (should (string-match-p "#\\+end_src\n\n#\\+begin_example\n4\n#\\+end_example\n"
                            (buffer-string)))))

(ert-deftest wolfram-nb-output-test-forced-png-without-image-support ()
  "A PNG result keeps an overlay and never fails, whatever Emacs can display."
  (wolfram-nb-test--in-buffer "#+begin_src wolfram :format PNG\n2+2\n#+end_src\n\n"
    (wolfram-nb--apply-eval-result
     (point-max) (list :status "ok" :result "4" :png wolfram-nb-test--png) "2+2")
    (should (> (length wolfram-nb--overlays) 0))
    (should (string-match-p "begin_example\n<" (buffer-string)))))

;;; Graphics output

(defun wolfram-nb-test--graphics-result ()
  "Return a result plist for a graphical evaluation."
  (list :status "ok" :result "-Graphics-" :png wolfram-nb-test--png
        :boxes wolfram-nb-test--boxes))

(ert-deftest wolfram-nb-output-test-graphics-output-is-kept-verbatim ()
  (wolfram-nb-test--in-buffer "#+begin_src wolfram\nGraphics[Circle[]]\n#+end_src\n\n"
    (wolfram-nb--apply-eval-result
     (point-max) (wolfram-nb-test--graphics-result) "Graphics[Circle[]]")
    (should (string-match-p
             "#\\+ATTR_WOLFRAM: :style \"Output\" :id \"large-cell-1\"\n#\\+begin_src wolfram-raw\n<Graphics output"
             (buffer-string)))
    (should-not (string-match-p "GraphicsBox" (buffer-string)))
    (should (equal (gethash "large-cell-1" wolfram-nb--large-cells-cache)
                   (format "BoxData[%s]" wolfram-nb-test--boxes)))
    (should (equal (gethash "large-cell-1" wolfram-nb--png-cache)
                   wolfram-nb-test--png))
    ;; Saving writes the boxes back as a real Output cell.
    (let ((cells (wolfram-nb--org-to-cells (buffer-string))))
      (should (equal (car (last cells))
                     (format "Cell[BoxData[%s], \"Output\"]" wolfram-nb-test--boxes))))))

(ert-deftest wolfram-nb-output-test-graphics-reevaluation-replaces ()
  (wolfram-nb-test--in-buffer "#+begin_src wolfram\nGraphics[Circle[]]\n#+end_src\n\n"
    (let ((end (point-max)))
      (wolfram-nb--apply-eval-result end (wolfram-nb-test--graphics-result) "g")
      (wolfram-nb--apply-eval-result end (wolfram-nb-test--graphics-result) "g")
      (should (= (wolfram-nb-test--count "begin_src wolfram-raw") 1))
      ;; A text result then takes the graphic's place.
      (wolfram-nb--apply-eval-result end '(:status "ok" :result "plain") "g")
      (should (= (wolfram-nb-test--count "begin_src wolfram-raw") 0))
      (should (string-match-p "plain" (buffer-string))))))

(ert-deftest wolfram-nb-output-test-graphics-with-print-keeps-both ()
  (wolfram-nb-test--in-buffer "#+begin_src wolfram\nPrint[1]; g\n#+end_src\n\n"
    (wolfram-nb--apply-eval-result
     (point-max)
     (plist-put (wolfram-nb-test--graphics-result) :stdout "1") "g")
    (should (= (wolfram-nb-test--count "begin_example") 1))
    (should (= (wolfram-nb-test--count "begin_src wolfram-raw") 1))))

(ert-deftest wolfram-nb-output-test-clear-outputs-removes-graphics ()
  (wolfram-nb-test--in-buffer "#+begin_src wolfram\ng\n#+end_src\n\n"
    (wolfram-nb--apply-eval-result
     (point-max)
     (plist-put (wolfram-nb-test--graphics-result) :stdout "1") "g")
    (insert "Closing text.\n")
    (wolfram-nb-clear-outputs)
    (should-not (string-match-p "begin_example\\|wolfram-raw" (buffer-string)))
    (should (string-match-p "Closing text" (buffer-string)))
    (should (string-match-p "begin_src wolfram\ng\n#\\+end_src" (buffer-string)))))

(ert-deftest wolfram-nb-output-test-overlay-apply-uses-cached-png ()
  "Reapplying overlays finds the PNG kept for a generated graphics cell."
  (wolfram-nb-test--in-buffer "#+begin_src wolfram\ng\n#+end_src\n\n"
    (wolfram-nb--apply-eval-result
     (point-max) (wolfram-nb-test--graphics-result) "g")
    (wolfram-nb-apply-buffer-overlays)
    (let ((ov (car (cl-remove-if-not (lambda (o) (overlay-get o 'wolfram-nb-id))
                                     wolfram-nb--overlays))))
      (should ov)
      (should (equal (overlay-get ov 'wolfram-nb-id) "large-cell-1"))
      (should (overlay-get ov 'folded))
      (when (image-type-available-p 'png)
        (should (eq (car-safe (overlay-get ov 'display)) 'image))))))

;;; Evaluating a whole buffer

(ert-deftest wolfram-nb-output-test-eval-buffer-in-order ()
  "Outputs land under their own block even though earlier ones shifted text."
  (wolfram-nb-test--in-buffer
      (concat "#+begin_src wolfram\na=1;\n#+end_src\n\n"
              "Some text.\n\n"
              "#+begin_src wolfram\na+1\n#+end_src\n\n"
              "#+begin_src python\nprint(1)\n#+end_src\n\n"
              "#+begin_src wolfram\na+2\n#+end_src\n")
    (let ((seen nil))
      (cl-letf (((symbol-function 'wolfram-nb--eval-detailed)
                 (lambda (code &optional _format)
                   (push code seen)
                   (list :status "ok"
                         :result (if (equal code "a=1;\n") "" (format "R(%s)" (string-trim code)))))))
        (wolfram-nb-eval-buffer))
      (should (equal (nreverse seen) '("a=1;\n" "a+1\n" "a+2\n")))
      (let ((text (buffer-string)))
        (should (string-match-p "a\\+1\n#\\+end_src\n\n#\\+begin_example\nR(a\\+1)\n#\\+end_example" text))
        (should (string-match-p "a\\+2\n#\\+end_src\n\n#\\+begin_example\nR(a\\+2)\n#\\+end_example" text))
        (should-not (string-match-p "print(1)\n#\\+end_src\n\n#\\+begin_example" text))
        (should (= (wolfram-nb-test--count "begin_example") 2))))))

(ert-deftest wolfram-nb-output-test-eval-buffer-twice-is-stable ()
  (wolfram-nb-test--in-buffer "#+begin_src wolfram\n1+1\n#+end_src\n\n#+begin_src wolfram\n2+2\n#+end_src\n"
    (cl-letf (((symbol-function 'wolfram-nb--eval-detailed)
               (lambda (code &optional _format)
                 (list :status "ok" :result (format "<%s>" (string-trim code))))))
      (wolfram-nb-eval-buffer)
      (let ((first (buffer-string)))
        (wolfram-nb-eval-buffer)
        (should (equal first (buffer-string)))))))

(ert-deftest wolfram-nb-output-test-eval-block-reports-error ()
  (wolfram-nb-test--in-buffer "#+begin_src wolfram\n1+1\n#+end_src\n"
    (cl-letf (((symbol-function 'wolfram-nb--eval-detailed)
               (lambda (&rest _) (signal 'wolfram-nb-eval-error '("boom")))))
      (should-not (wolfram-nb-eval-block))
      (should-not (string-match-p "begin_example" (buffer-string))))))

;;; Graphics cells survive a round trip

(defconst wolfram-nb-test--graphics-notebook
  (concat "Notebook[{\n"
          "Cell[\"Plots\", \"Section\"],\n"
          "Cell[BoxData[RowBox[{\"Plot\", \"[\", RowBox[{\"Sin\", \"[\", \"x\", \"]\"}], \"]\"}]], \"Input\"],\n"
          "Cell[BoxData[GraphicsBox[{Circle[{0, 0}], Line[{{0, 0}, {1, 1}}]}, ImageSize -> 360]], \"Output\", ExpressionUUID -> \"aaaa-bbbb\"],\n"
          "Cell[BoxData[Graphics3DBox[SphereBox[{0, 0, 0}]]], \"Output\"],\n"
          "Cell[BoxData[GraphicsBox[{}, Method -> {\"AxisPadding\" -> Scaled[0.02], \"DefaultMeshStyle\" -> 1}]], \"Output\", CellLabel -> \"Out[3]=\"],\n"
          "Cell[BoxData[FormBox[RowBox[{\"x\", \"+\", \"1\"}], TraditionalForm]], \"Output\"],\n"
          "Cell[\"The end.\", \"Text\"]\n}]\n")
  "A notebook with code and several graphics output cells.")

(defun wolfram-nb-test--cells-of (nb-text)
  "Parse NB-TEXT, convert to Org and back, return (ORG . CELL-STRINGS)."
  (let ((file (make-temp-file "wolfram-nb-test" nil ".nb")))
    (unwind-protect
        (with-temp-buffer
          (wolfram-nb-mode)
          (with-temp-file file (insert nb-text))
          (let* ((cells (wolfram-nb--parse-notebook file))
                 (org (wolfram-nb--cells-to-org cells)))
            (cons org (wolfram-nb--org-to-cells org))))
      (delete-file file))))

(ert-deftest wolfram-nb-output-test-graphics-cells-roundtrip ()
  (let* ((result (wolfram-nb-test--cells-of wolfram-nb-test--graphics-notebook))
         (org (car result))
         (cells (cdr result)))
    (should (= (length cells) 7))
    ;; Graphics are verbatim BoxData cells again, not quoted strings.
    (should (member "Cell[BoxData[GraphicsBox[{Circle[{0, 0}], Line[{{0, 0}, {1, 1}}]}, ImageSize -> 360]], \"Output\", ExpressionUUID -> \"aaaa-bbbb\"]" cells))
    (should (member "Cell[BoxData[Graphics3DBox[SphereBox[{0, 0, 0}]]], \"Output\"]" cells))
    (should (member "Cell[BoxData[FormBox[RowBox[{\"x\", \"+\", \"1\"}], TraditionalForm]], \"Output\"]" cells))
    (should-not (cl-some (lambda (c) (string-match-p "\\`Cell\\[\"\\(BoxData\\|GraphicsBox\\)" c)) cells))
    ;; The Org text holds placeholders, never the boxes themselves.
    (should-not (string-match-p "GraphicsBox\\|Circle" org))
    (should (= (let ((n 0) (start 0))
                 (while (string-match "begin_src wolfram-raw" org start)
                   (setq n (1+ n) start (match-end 0)))
                 n)
               4))
    ;; Strings inside the boxes must not be taken for the cell style.
    (should (member "Cell[BoxData[GraphicsBox[{}, Method -> {\"AxisPadding\" -> Scaled[0.02], \"DefaultMeshStyle\" -> 1}]], \"Output\", CellLabel -> \"Out[3]=\"]" cells))))

(ert-deftest wolfram-nb-output-test-style-ignores-strings-inside-boxes ()
  (let* ((cell "Cell[BoxData[GraphicsBox[{}, Method -> {\"A\" -> Scaled[0.02], \"DefaultMeshStyle\" -> 1}]], \"Output\", X -> 1]")
         (info (wolfram-nb--cell-style-info cell)))
    (should (equal (car info) "Output"))
    (should (equal (substring cell (cdr info)) ", X -> 1]")))
  (should (equal (car (wolfram-nb--cell-style-info
                       "Cell[TextData[{\"a \", Cell[\"inner\", \"Text\"]}], \"Section\", Y -> 2]"))
                 "Section"))
  (should (equal (car (wolfram-nb--cell-style-info
                       "Cell[BoxData[RowBox[{\"f\", \"[\", \"x\", \"]\"}]], \"Input\"]"))
                 "Input"))
  (should-not (wolfram-nb--cell-style-info "Cell[BoxData[x]]")))

(ert-deftest wolfram-nb-output-test-options-kept-on-input-box-cells ()
  "Options such as ExpressionUUID survive on BoxData Input cells."
  (let ((cells (cdr (wolfram-nb-test--cells-of
                     (concat "Notebook[{\n"
                             "Cell[BoxData[RowBox[{\"1\", \"+\", \"1\"}]], \"Input\", CellChangeTimes -> {1, 2}, ExpressionUUID -> \"u1\"]\n}]\n")))))
    (should (equal cells '("Cell[\"1+1\", \"Input\", CellChangeTimes -> {1, 2}, ExpressionUUID -> \"u1\"]")))))

(ert-deftest wolfram-nb-output-test-graphics-roundtrip-is-idempotent ()
  "Saving twice gives the same cells."
  (let* ((once (cdr (wolfram-nb-test--cells-of wolfram-nb-test--graphics-notebook)))
         (nb (wolfram-nb--cells-to-notebook once))
         (twice (cdr (wolfram-nb-test--cells-of nb))))
    (should (equal once twice))))

(ert-deftest wolfram-nb-output-test-plain-input-boxes-still-become-code ()
  "Ordinary Input boxes are still turned into editable code."
  (let ((cells (cdr (wolfram-nb-test--cells-of wolfram-nb-test--graphics-notebook))))
    (should (cl-some (lambda (c) (string-match-p "\\`Cell\\[\"Plot\\[Sin\\[x\\]\\]\", \"Input\"" c))
                     cells))))

(provide 'test-output)
;;; test-output.el ends here
