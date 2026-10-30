;;; test-verbatim.el --- Cells that cannot be shown as Org are kept whole -*- lexical-binding: t; -*-

;;; Commentary:
;; A cell with no style, one whose content is an expression, and dynamic
;; content cannot be written back from what Org shows.  They were dropped or
;; rewritten (`Cell[Sin[x], "Input"]' became the string "Sin[x]").  They are now
;; kept as the whole cell they were, shown in a raw block, and the notebook
;; says which cells they are.  The same file checks that errors say where.

;;; Code:

(require 'ert)
(require 'cl-lib)
(add-to-list 'load-path
             (file-name-directory
              (directory-file-name
               (file-name-directory (or load-file-name buffer-file-name default-directory)))))
(require 'wolfram-nb-mode)

(defconst wolfram-nb-verbatim--cells
  '("Cell[\"control\", \"Text\"]"
    "Cell[BoxData[RowBox[{\"1\", \"+\", \"1\"}]]]"
    "Cell[\"no style\"]"
    "Cell[TextData[{\"a \", StyleBox[\"b\", FontWeight -> Bold]}]]"
    "Cell[BoxData[RowBox[{\"a\"}]], CellTags -> \"t\"]"
    "Cell[DynamicModuleBox[{x = 1}, \"x\"], \"Output\"]"
    "Cell[Sin[x], \"Input\"]"
    "Cell[OutputFormData[\"a\", \"a\"], \"Output\"]"
    "Cell[BoxData[RowBox[{\"2\"}]], \"Input\", CellLabel -> \"In[1]:=\"]")
  "Cells as a notebook may hold them; numbers 2 to 7 cannot be shown as Org.")

(defun wolfram-nb-verbatim--write (cells)
  "Return the file name of a notebook with CELLS."
  (let ((file (make-temp-file "wolfram-nb-verbatim" nil ".nb")))
    (with-temp-file file
      (insert "Notebook[{\n" (string-join cells ",\n") "\n}]\n"))
    file))

(defmacro wolfram-nb-verbatim--with-parsed (cell-strings vars &rest body)
  "Parse a notebook of CELL-STRINGS in a notebook buffer and run BODY.
VARS is (CELLS ORG): the symbols bound to the parsed cells and their Org text."
  (declare (indent 2))
  `(let ((file (wolfram-nb-verbatim--write ,cell-strings)))
     (unwind-protect
         (with-temp-buffer
           (wolfram-nb-mode)
           (let* ((,(car vars) (wolfram-nb--parse-notebook file))
                  (,(cadr vars) (wolfram-nb--cells-to-org ,(car vars))))
             ,@body))
       (delete-file file))))

(ert-deftest wolfram-nb-verbatim-test-no-cell-is-dropped-or-rewritten ()
  (wolfram-nb-verbatim--with-parsed wolfram-nb-verbatim--cells (cells org)
    (should (= (length cells) (length wolfram-nb-verbatim--cells)))
    (should (equal (mapcar #'substring-no-properties (wolfram-nb--org-to-cells org))
                   wolfram-nb-verbatim--cells))))

(ert-deftest wolfram-nb-verbatim-test-cells-are-named-with-the-reason ()
  (wolfram-nb-verbatim--with-parsed wolfram-nb-verbatim--cells (cells org)
    (ignore cells org)
    (should (equal wolfram-nb--verbatim-cells
                   '((2 . "it has no style") (3 . "it has no style")
                     (4 . "it has no style") (5 . "it has no style")
                     (6 . "it is dynamic content") (7 . "its content is an expression"))))))

(ert-deftest wolfram-nb-verbatim-test-summary-is-short ()
  (should (equal (wolfram-nb--verbatim-summary '((2 . "it has no style")))
                 "1 cell kept as it is: cell 2 (it has no style)"))
  (should (string-match-p
           "\\`4 cells kept as they are: cell 2 (a), cell 3 (b), cell 4 (c), \\.\\.\\.\\'"
           (wolfram-nb--verbatim-summary '((2 . "a") (3 . "b") (4 . "c") (5 . "d"))))))

(ert-deftest wolfram-nb-verbatim-test-a-short-cell-is-shown-and-can-be-edited ()
  (wolfram-nb-verbatim--with-parsed wolfram-nb-verbatim--cells (cells org)
    (ignore cells)
    (should (string-match-p
             (regexp-quote "#+ATTR_WOLFRAM: :style \"<verbatim>\"")
             org))
    (should (string-match-p (regexp-quote "Cell[Sin[x], \"Input\"]") org))
    ;; the block is the cell, so editing the block edits the cell
    (let ((edited (replace-regexp-in-string (regexp-quote "Cell[Sin[x], \"Input\"]")
                                            "Cell[Cos[x], \"Input\"]" org t t)))
      (should (member "Cell[Cos[x], \"Input\"]"
                      (mapcar #'substring-no-properties (wolfram-nb--org-to-cells edited)))))))

(ert-deftest wolfram-nb-verbatim-test-a-large-cell-is-described-and-kept ()
  (let* ((big (format "Cell[DynamicModuleBox[{x = 1}, \"%s\"], \"Output\"]"
                      (make-string 5000 ?a)))
         (cells (list "Cell[\"before\", \"Text\"]" big "Cell[\"after\", \"Text\"]")))
    (wolfram-nb-verbatim--with-parsed cells (parsed org)
      (ignore parsed)
      (should (string-match-p "<Cell kept as it is (" org))
      (should-not (string-match-p (make-string 100 ?a) org))
      (should (equal (mapcar #'substring-no-properties (wolfram-nb--org-to-cells org))
                     cells)))))

(ert-deftest wolfram-nb-verbatim-test-cells-in-a-group-keep-their-group ()
  (let* ((text (concat "Notebook[{\nCell[CellGroupData[{\n"
                       "Cell[\"Intro\", \"Section\"],\n"
                       "Cell[BoxData[\"z\"]],\n"
                       "Cell[\"after\", \"Text\"]\n}, Closed]]\n}]\n"))
         (file (make-temp-file "wolfram-nb-verbatim" nil ".nb")))
    (unwind-protect
        (progn
          (with-temp-file file (insert text))
          (with-current-buffer (find-file-noselect file)
            (set-buffer-modified-p t)
            (save-buffer)
            (let ((saved (with-temp-buffer (insert-file-contents file) (buffer-string))))
              (should (string-match-p "Cell\\[BoxData\\[\"z\"\\]\\]" saved))
              (should (string-match-p "}, Closed\\]\\]" saved)))
            (set-buffer-modified-p nil)
            (kill-buffer)))
      (delete-file file))))

(ert-deftest wolfram-nb-verbatim-test-opening-says-which-cells-are-kept ()
  (let ((file (wolfram-nb-verbatim--write wolfram-nb-verbatim--cells))
        (messages '()))
    (unwind-protect
        (cl-letf (((symbol-function 'message)
                   (lambda (format-string &rest args)
                     (push (apply #'format format-string args) messages))))
          (with-current-buffer (find-file-noselect file)
            (set-buffer-modified-p nil)
            (kill-buffer)))
      (delete-file file))
    (should (cl-some (lambda (m) (string-match-p "6 cells kept as they are: cell 2 (it has no style)" m))
                     messages))))

;;; Errors say where

(ert-deftest wolfram-nb-verbatim-test-unclosed-cell-list-says-the-line ()
  (let ((file (make-temp-file "wolfram-nb-verbatim" nil ".nb")))
    (unwind-protect
        (progn
          (with-temp-file file (insert "\n\nNotebook[{\nCell[\"a\", \"Text\"]\n"))
          (with-temp-buffer
            (let ((err (should-error (wolfram-nb--parse-notebook file)
                                     :type 'wolfram-nb-parse-error)))
              (should (string-match-p "starts at line 3" (cadr err))))))
      (delete-file file))))

(ert-deftest wolfram-nb-verbatim-test-eval-error-names-the-block ()
  "An error names the block by its line, and so does the summary of a buffer."
  (with-temp-buffer
    (let ((wolfram-nb-use-kernel nil)
          (messages '()))
      (wolfram-nb-mode)
      (insert "intro\n\n#+begin_src wolfram\n2+2\n#+end_src\n\n"
              "text\n\n#+begin_src wolfram\n1+1\n#+end_src\n")
      (cl-letf (((symbol-function 'wolfram-nb--eval-detailed)
                 (lambda (code &optional _format)
                   (if (string-match-p "2\\+2" code)
                       (signal 'wolfram-nb-eval-error '("boom"))
                     (list :status "ok" :result "2"))))
                ((symbol-function 'message)
                 (lambda (format-string &rest args)
                   (push (apply #'format format-string args) messages))))
        (wolfram-nb-eval-buffer))
      (should (member "Eval error in the block at line 3: boom" messages))
      (should (equal (car messages) "Evaluated 1 blocks (1 errors, at line 3)")))))

(provide 'test-verbatim)
;;; test-verbatim.el ends here
