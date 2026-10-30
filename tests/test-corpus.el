;;; test-corpus.el --- Round trips over a corpus of notebooks -*- lexical-binding: t; -*-

;;; Commentary:
;; tests/corpus holds notebooks made by tests/corpus/generate.wls with the
;; layout of Front End files, trailing cache comment included.  manifest.txt
;; lists, for each, the true number of cells and of notebook options.
;;
;; Without a kernel the tests check that opening and saving keeps the cell
;; count, styles, content and options, and that saving twice gives the same
;; file.  With a kernel the original and the saved file are loaded as Wolfram
;; expressions and compared (tests/corpus/compare.wl).  Two ways of saving are
;; compared: unedited cells, which must come back exactly, and every cell
;; pushed through the converters, as if it had been edited.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'subr-x)
(let ((tests-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory))))
  (add-to-list 'load-path (file-name-directory (directory-file-name tests-dir)))
  (defconst wolfram-nb-corpus--dir (expand-file-name "corpus/" tests-dir)
    "Directory of the notebook corpus."))
(require 'wolfram-nb-mode)

;;; Corpus access

(defun wolfram-nb-corpus--manifest ()
  "Return the manifest as a list of (NAME CELLS OPTIONS)."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "manifest.txt" wolfram-nb-corpus--dir))
    (delq nil
          (mapcar (lambda (line)
                    (let ((f (split-string line " " t)))
                      (and (= (length f) 3)
                           (list (nth 0 f) (string-to-number (nth 1 f))
                                 (string-to-number (nth 2 f))))))
                  (split-string (buffer-string) "\n" t)))))

(defun wolfram-nb-corpus--file (name)
  "Return the absolute file name of the corpus notebook NAME."
  (expand-file-name name wolfram-nb-corpus--dir))

(defun wolfram-nb-corpus--names (&optional pattern)
  "Return corpus notebook names that exist, matching PATTERN when given."
  (cl-remove-if-not
   (lambda (name)
     (and (file-exists-p (wolfram-nb-corpus--file name))
          (or (null pattern) (string-match-p pattern name))))
   (mapcar #'car (wolfram-nb-corpus--manifest))))

(defun wolfram-nb-corpus--option-count (options)
  "Return how many top-level options the string OPTIONS holds."
  (if (or (null options) (string-empty-p options))
      0
    (length (wolfram-nb--split-args options))))

;;; Running a notebook through the pipeline

(cl-defstruct (wolfram-nb-corpus-run (:constructor wolfram-nb-corpus--make-run))
  cells org back nb options)

(defun wolfram-nb-corpus--run (file &optional forced)
  "Parse FILE, show it as Org, and convert it back.
With FORCED the originals of the cells are forgotten first, so that every
cell goes through the converters as if it had been edited."
  (with-temp-buffer
    (wolfram-nb-mode)
    (let* ((cells (wolfram-nb--parse-notebook file))
           (org (wolfram-nb--cells-to-org cells)))
      (when forced
        (setq wolfram-nb--box-sources nil))
      (let ((back (wolfram-nb--org-to-cells org)))
        (wolfram-nb-corpus--make-run
         :cells cells :org org :back back
         :nb (wolfram-nb--cells-to-notebook back)
         :options wolfram-nb--notebook-options)))))

(defun wolfram-nb-corpus--write-temp (text)
  "Write TEXT to a temporary notebook file and return its name."
  (let ((file (make-temp-file "wolfram-nb-corpus" nil ".nb")))
    (with-temp-file file (insert text))
    file))

(defun wolfram-nb-corpus--max-line (text)
  "Return the length of the longest line of TEXT."
  (let ((longest 0))
    (dolist (line (split-string text "\n"))
      (setq longest (max longest (length line))))
    longest))

(defun wolfram-nb-corpus--cell-signature (cell)
  "Return what must survive for CELL: style and content."
  (list (wolfram-nb-cell-style cell) (wolfram-nb-cell-content cell)))

;;; Without a kernel

(ert-deftest wolfram-nb-corpus-test-manifest-is-complete ()
  (should (>= (length (wolfram-nb-corpus--names)) 10))
  (dolist (name '("structure.nb" "richtext.nb" "code.nb" "graphics.nb"
                  "options.nb" "unicode.nb" "edge.nb" "empty.nb"))
    (should (member name (wolfram-nb-corpus--names)))))

(ert-deftest wolfram-nb-corpus-test-cell-and-option-counts ()
  "Every notebook has the number of cells and options the generator wrote.
The trailing cache comment of each file lists cells too; none of them may
be imported."
  (dolist (entry (wolfram-nb-corpus--manifest))
    (let ((name (nth 0 entry)))
      (when (file-exists-p (wolfram-nb-corpus--file name))
        (let ((run (wolfram-nb-corpus--run (wolfram-nb-corpus--file name))))
          (should (equal (list name (length (wolfram-nb-corpus-run-cells run)))
                         (list name (nth 1 entry))))
          (should (equal (list name (wolfram-nb-corpus--option-count
                                     (wolfram-nb-corpus-run-options run)))
                         (list name (nth 2 entry)))))))))

(ert-deftest wolfram-nb-corpus-test-unedited-notebooks-come-back-unchanged ()
  "Reading a notebook and saving it again changes no cell and no option."
  (dolist (name (wolfram-nb-corpus--names))
    (let* ((file (wolfram-nb-corpus--file name))
           (run (wolfram-nb-corpus--run file))
           (saved (wolfram-nb-corpus--write-temp (wolfram-nb-corpus-run-nb run))))
      (unwind-protect
          (let ((again (wolfram-nb-corpus--run saved)))
            (should (equal (list name (length (wolfram-nb-corpus-run-back run)))
                           (list name (length (wolfram-nb-corpus-run-cells run)))))
            (should (equal (list name (mapcar #'wolfram-nb-corpus--cell-signature
                                              (wolfram-nb-corpus-run-cells again)))
                           (list name (mapcar #'wolfram-nb-corpus--cell-signature
                                              (wolfram-nb-corpus-run-cells run)))))
            (should (equal (list name (wolfram-nb-corpus-run-options again))
                           (list name (wolfram-nb-corpus-run-options run))))
            ;; Saving the saved file gives the same file.
            (should (equal (list name (wolfram-nb-corpus-run-nb again))
                           (list name (wolfram-nb-corpus-run-nb run)))))
        (delete-file saved)))))

(ert-deftest wolfram-nb-corpus-test-edited-notebooks-reach-a-fixed-point ()
  "After one pass through the converters, another changes nothing."
  (dolist (name (wolfram-nb-corpus--names))
    (let* ((first (wolfram-nb-corpus--run (wolfram-nb-corpus--file name) t))
           (file (wolfram-nb-corpus--write-temp (wolfram-nb-corpus-run-nb first))))
      (unwind-protect
          (let ((second (wolfram-nb-corpus--run file t)))
            (should (equal (list name (length (wolfram-nb-corpus-run-back second)))
                           (list name (length (wolfram-nb-corpus-run-back first)))))
            (should (equal (list name (wolfram-nb-corpus-run-nb second))
                           (list name (wolfram-nb-corpus-run-nb first)))))
        (delete-file file)))))

(ert-deftest wolfram-nb-corpus-test-org-text-is-editable ()
  "No line of the Org text is long enough to hurt Emacs, and none is a stray."
  (dolist (name (wolfram-nb-corpus--names))
    (let ((org (wolfram-nb-corpus-run-org
                (wolfram-nb-corpus--run (wolfram-nb-corpus--file name)))))
      (should (< (wolfram-nb-corpus--max-line org) 6000))
      ;; Graphics are placeholders, never the boxes themselves.
      (should-not (string-match-p "GraphicsBox\\|RasterBox" org)))))

(ert-deftest wolfram-nb-corpus-test-styles-survive-in-both-paths ()
  (dolist (name (wolfram-nb-corpus--names))
    (let ((expected (mapcar #'wolfram-nb-cell-style
                            (wolfram-nb-corpus-run-cells
                             (wolfram-nb-corpus--run (wolfram-nb-corpus--file name))))))
      (dolist (forced '(nil t))
        (let ((run (wolfram-nb-corpus--run (wolfram-nb-corpus--file name) forced)))
          (should (equal (list name forced
                               (mapcar (lambda (s) (wolfram-nb-cell-style (wolfram-nb--parse-cell s)))
                                       (wolfram-nb-corpus-run-back run)))
                         (list name forced expected))))))))

(ert-deftest wolfram-nb-corpus-test-literal-text-stays-literal ()
  "Asterisks, slashes and lines that look like Org stay what they were."
  (let* ((file (wolfram-nb-corpus--file "richtext.nb"))
         (forced (wolfram-nb-corpus-run-back (wolfram-nb-corpus--run file t)))
         (all (mapconcat #'identity forced "\n")))
    ;; The literal-marker text is not turned into formatting ...
    (should (string-match-p "Literal markers in plain text: 5 \\* 3 \\* 2, a \\*star\\* here" all))
    ;; ... and the Org-looking lines are kept in one cell.
    (should (string-match-p "not a headline\\\\n- not a list\\\\n1. not numbered" all))
    ;; The plain URL is not rewritten as an Org link.
    (should (string-match-p "https://www.wolfram.com/mathematica and \\[\\[not a link\\]\\]" all))
    (should-not (string-match-p "\\[\\[https" all))
    ;; Named characters keep their single backslash.
    (should (string-match-p "named character \\\\\\[Alpha\\]" all))
    (should-not (string-match-p "\\\\\\\\\\[Alpha\\]" all))))

(ert-deftest wolfram-nb-corpus-test-inline-boxes-survive-editing ()
  "Hyperlinks and inline cells inside text come back as they were."
  (let* ((forced (wolfram-nb-corpus-run-back
                  (wolfram-nb-corpus--run (wolfram-nb-corpus--file "richtext.nb") t)))
         (all (mapconcat #'identity forced "\n")))
    (should (string-match-p "ButtonBox\\[\"Wolfram\"" all))
    (should (string-match-p "InlineFormula" all))
    (should-not (string-match-p "\\[wnb:" all))))

(ert-deftest wolfram-nb-corpus-test-editing-a-cell-changes-only-that-cell ()
  "Editing the text of one code cell leaves all the others as they were."
  (with-temp-buffer
    (wolfram-nb-mode)
    (let* ((file (wolfram-nb-corpus--file "code.nb"))
           (cells (wolfram-nb--parse-notebook file))
           (org (wolfram-nb--cells-to-org cells))
           (edited (replace-regexp-in-string "Sin\\[x\\]\\^2 ?\\+ ?Cos\\[x\\]\\^2"
                                             "Tan[x] + 1" org t t))
           (before (wolfram-nb--org-to-cells org))
           (after (wolfram-nb--org-to-cells edited))
           (changed (cl-loop for a in before for b in after
                             unless (equal a b) collect b)))
      (should (= (length before) (length after)))
      (should (>= (length changed) 1))
      (should (cl-every (lambda (c) (string-match-p "Tan\\[x\\] \\+ 1" c)) changed)))))

(ert-deftest wolfram-nb-corpus-test-trailing-cache-comment-adds-no-cells ()
  "The Front End's cache comment, with its look-alike cells, is not content."
  (dolist (name '("structure.nb" "richtext.nb" "empty.nb"))
    (let* ((file (wolfram-nb-corpus--file name))
           (text (with-temp-buffer (insert-file-contents file) (buffer-string))))
      (should (string-match-p "NotebookFileOutline" text))
      (should (= (length (wolfram-nb-corpus-run-cells (wolfram-nb-corpus--run file)))
                 (nth 1 (assoc name (wolfram-nb-corpus--manifest))))))))

(ert-deftest wolfram-nb-corpus-test-large-notebook-stays-fast ()
  "A notebook of thousands of cells and a multi-megabyte graphic is no problem."
  (let* ((file (make-temp-file "wolfram-nb-large" nil ".nb"))
         (raster (apply #'concat (make-list 40000 "0.123456, 0.654321, ")))
         (count 3000))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "Notebook[{\n")
            (dotimes (i count)
              (insert (format "Cell[CellGroupData[{Cell[\"Section %d\", \"Section\", ExpressionUUID -> \"s%d\"],\n" i i)
                              (format "Cell[\"Some text %d with *markers*\", \"Text\", ExpressionUUID -> \"t%d\"],\n" i i)
                              (format "Cell[BoxData[RowBox[{\"f\", \"[\", RowBox[{\"x\", \",\", \"%d\"}], \"]\"}]], \"Input\", ExpressionUUID -> \"i%d\"]}, Open]],\n" i i)))
            (insert "Cell[BoxData[GraphicsBox[RasterBox[{{" raster "0.5}}]]], \"Output\"]\n}, WindowSize -> {500, 400}]\n"))
          (let* ((start (float-time))
                 (run (wolfram-nb-corpus--run file))
                 (parse-and-convert (- (float-time) start)))
            (should (= (length (wolfram-nb-corpus-run-cells run)) (1+ (* 3 count))))
            (should (= (length (wolfram-nb-corpus-run-back run)) (1+ (* 3 count))))
            (should (< (wolfram-nb-corpus--max-line (wolfram-nb-corpus-run-org run)) 6000))
            (should (< parse-and-convert 60))
            (message "large notebook (%d cells, %d bytes): %.1fs"
                     (length (wolfram-nb-corpus-run-cells run))
                     (nth 7 (file-attributes file)) parse-and-convert)))
      (delete-file file))))

;;; With a kernel

(defvar wolfram-nb-corpus--kernel nil
  "The kernel shared by the corpus tests.")

(defun wolfram-nb-corpus--kernel ()
  "Return a started kernel with the comparison loaded, or skip the test."
  (unless (wolfram-nb-kernel-available-p)
    (ert-skip "No Wolfram kernel found"))
  (unless (wolfram-nb-kernel-live-p wolfram-nb-corpus--kernel)
    (let ((kernel (wolfram-nb-kernel-start)))
      (condition-case err
          (wolfram-nb-kernel-eval-sync
           kernel (format "Get[%S]" (wolfram-nb-corpus--file "compare.wl")) :wait 120)
        (wolfram-nb-kernel-error
         (ert-skip (format "The Wolfram kernel could not be started: %s" (cadr err)))))
      (setq wolfram-nb-corpus--kernel kernel)))
  wolfram-nb-corpus--kernel)

(defun wolfram-nb-corpus--compare (original saved)
  "Return the kernel's comparison of ORIGINAL and SAVED as an alist."
  (let* ((result (wolfram-nb-kernel-eval-sync
                  (wolfram-nb-corpus--kernel)
                  (format "WolframNBCompare`compare[%S, %S]" original saved)
                  :timeout 120 :wait 180))
         (text (plist-get result :result)))
    (mapcar (lambda (pair) (let ((kv (split-string pair "="))) (cons (car kv) (cadr kv))))
            (split-string text ";" t))))

(defun wolfram-nb-corpus--all-full (value)
  "Return non-nil if VALUE like \"3/3\" has equal sides."
  (and (stringp value)
       (string-match "\\`\\([0-9]+\\)/\\([0-9]+\\)\\'" value)
       (equal (match-string 1 value) (match-string 2 value))))

(ert-deftest wolfram-nb-corpus-test-kernel-unedited-notebooks-are-identical ()
  "The kernel reads the saved file as exactly the same cells and options."
  (dolist (name (wolfram-nb-corpus--names))
    (let* ((file (wolfram-nb-corpus--file name))
           (run (wolfram-nb-corpus--run file))
           (saved (wolfram-nb-corpus--write-temp (wolfram-nb-corpus-run-nb run))))
      (unwind-protect
          (let ((cmp (wolfram-nb-corpus--compare file saved)))
            (should (equal (list name (cdr (assoc "exact" cmp))) (list name "True")))
            (should (equal (list name (cdr (assoc "nbopts" cmp))) (list name "True")))
            (should (wolfram-nb-corpus--all-full (cdr (assoc "cells" cmp)))))
        (delete-file saved)))))

(ert-deftest wolfram-nb-corpus-test-kernel-edited-notebooks-keep-their-meaning ()
  "With every cell converted, the saved file still means the same thing."
  (dolist (name (wolfram-nb-corpus--names))
    (let* ((file (wolfram-nb-corpus--file name))
           (run (wolfram-nb-corpus--run file t))
           (saved (wolfram-nb-corpus--write-temp (wolfram-nb-corpus-run-nb run))))
      (unwind-protect
          (let ((cmp (wolfram-nb-corpus--compare file saved)))
            (should (equal (list name (cdr (assoc "styles" cmp))) (list name "True")))
            (should (equal (list name (cdr (assoc "nbopts" cmp))) (list name "True")))
            (should (wolfram-nb-corpus--all-full (cdr (assoc "cells" cmp))))
            (should (wolfram-nb-corpus--all-full (cdr (assoc "gfx" cmp))))
            (should (wolfram-nb-corpus--all-full (cdr (assoc "text" cmp))))
            (should (wolfram-nb-corpus--all-full (cdr (assoc "code" cmp))))
            (should (wolfram-nb-corpus--all-full (cdr (assoc "opts" cmp)))))
        (delete-file saved)))))

;;; Evaluating notebooks

(defun wolfram-nb-corpus--outputs ()
  "Return the output texts of the current notebook buffer, one per source block.
The text is nil for a block without output, and `graphics' for a graphic."
  (let (result)
    (goto-char (point-min))
    (while (re-search-forward "^#\\+begin_src wolfram\n" nil t)
      (re-search-forward "^#\\+end_src[ \t]*\n")
      (skip-chars-forward " \t\n")
      (push (cond
             ((looking-at "#\\+begin_example\n")
              (let ((start (match-end 0)))
                (re-search-forward "^#\\+end_example")
                (string-trim-right
                 (buffer-substring-no-properties start (match-beginning 0)) "\n")))
             ((looking-at "#\\+ATTR_WOLFRAM: :style \"Output\" :id ")
              'graphics))
            result))
    (nreverse result)))

(defmacro wolfram-nb-corpus--with-evaluated (name &rest body)
  "Open the corpus notebook NAME, evaluate it all, and run BODY in its buffer."
  (declare (indent 1))
  `(let ((file (make-temp-file "wolfram-nb-eval" nil ".nb")))
     (copy-file (wolfram-nb-corpus--file ,name) file t)
     (unwind-protect
         (progn
           (wolfram-nb-open file)
           (let ((buf (current-buffer)))
             (unwind-protect
                 (with-current-buffer buf
                   (let ((wolfram-nb-eval-timeout 120))
                     (setq wolfram-nb--kernel (wolfram-nb-corpus--kernel))
                     (wolfram-nb-kernel-eval-sync wolfram-nb--kernel
                                                  "Quiet[Clear[\"Global`*\"]]" :wait 30)
                     (wolfram-nb-eval-buffer)
                     ,@body))
               ;; The kernel is shared; the buffer must not stop it.
               (with-current-buffer buf
                 (setq wolfram-nb--kernel nil)
                 (set-buffer-modified-p nil))
               (kill-buffer buf))))
       (delete-file file))))

(ert-deftest wolfram-nb-corpus-test-evaluate-state ()
  (wolfram-nb-corpus--with-evaluated "eval-state.nb"
    (should (equal (wolfram-nb-corpus--outputs)
                   (list nil "6" nil "14" "14" "{1, 2, 3, 4, 5}" "15"
                         "printed\n42" "wörld")))))

(ert-deftest wolfram-nb-corpus-test-evaluate-errors-leave-the-kernel-usable ()
  (wolfram-nb-corpus--with-evaluated "eval-errors.nb"
    (let ((out (wolfram-nb-corpus--outputs)))
      (should (equal (nth 0 out) "1"))
      (should (string-match-p "Sin::argx" (nth 1 out)))
      (should (string-match-p "Sin\\[1, 2\\]" (nth 1 out)))
      (should (string-match-p "sntx" (nth 2 out)))
      (should (string-match-p "Power::infy" (nth 3 out)))
      (should (string-match-p "ComplexInfinity" (nth 3 out)))
      (should (equal (nth 4 out) "2")))))

(ert-deftest wolfram-nb-corpus-test-evaluate-graphics-and-save ()
  (wolfram-nb-corpus--with-evaluated "eval-graphics.nb"
    (should (equal (wolfram-nb-corpus--outputs)
                   '(graphics "3" graphics graphics graphics "{1, 4, 9, 16}")))
    (let ((saved (make-temp-file "wolfram-nb-saved" nil ".nb")))
      (unwind-protect
          (progn
            (delete-file saved)
            (write-file saved)
            (let ((kernel (wolfram-nb-corpus--kernel)))
              ;; Four graphics were drawn; each is a real graphic in the file.
              (should (equal (plist-get
                              (wolfram-nb-kernel-eval-sync
                               kernel
                               (format "Count[Cases[Get[%S], Cell[BoxData[b_], \"Output\", ___] :> b, Infinity], _GraphicsBox | _Graphics3DBox, Infinity]"
                                       saved)
                               :timeout 60)
                              :result)
                             "4"))
              (should (equal (plist-get
                              (wolfram-nb-kernel-eval-sync
                               kernel (format "Head[Get[%S]]" saved) :timeout 60)
                              :result)
                             "Notebook"))))
        (delete-file saved)))))

(provide 'test-corpus)
;;; test-corpus.el ends here
