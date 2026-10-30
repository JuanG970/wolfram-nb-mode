;;; test-groups.el --- Cell groups survive a visit in Emacs -*- lexical-binding: t; -*-

;;; Commentary:
;; A notebook's CellGroupData structure, with each group's Open or Closed, is
;; kept when the notebook is opened and saved, also when cells in it are edited.
;; Cells that are new get the groups the Front End would give them.  The tests
;; read the saved file back with the notebook parser and compare the nesting.
;; No kernel is needed.

;;; Code:

(require 'ert)
(require 'cl-lib)
(add-to-list 'load-path
             (file-name-directory
              (directory-file-name
               (file-name-directory (or load-file-name buffer-file-name default-directory)))))
(require 'wolfram-nb-mode)

(defconst wolfram-nb-groups--notebook
  (concat "Notebook[{\n"
          "Cell[CellGroupData[{\n"
          "Cell[\"Intro\", \"Section\"],\n"
          "Cell[\"intro text\", \"Text\"],\n"
          "Cell[CellGroupData[{\n"
          "Cell[\"1+1\", \"Input\"],\n"
          "Cell[\"2\", \"Output\"]}, Closed]],\n"
          "Cell[CellGroupData[{\n"
          "Cell[\"Sub\", \"Subsection\"],\n"
          "Cell[\"sub text\", \"Text\"]}, Open]]}, Open]],\n"
          "Cell[CellGroupData[{\n"
          "Cell[\"Next\", \"Section\"],\n"
          "Cell[\"next text\", \"Text\"]}, Open]]\n"
          "}]\n")
  "A notebook with nested groups, one of them closed.")

(defconst wolfram-nb-groups--flat-notebook
  (concat "Notebook[{\n"
          "Cell[\"Intro\", \"Section\"],\n"
          "Cell[\"1+1\", \"Input\"]\n"
          "}]\n")
  "A notebook without any cell groups.")

(defconst wolfram-nb-groups--original-shape
  '((("Section" 1) ("Text" 1) ("Input" 1 2) ("Output" 1 2)
     ("Subsection" 1 3) ("Text" 1 3) ("Section" 4) ("Text" 4))
    . ((1 . "Open") (2 . "Closed") (3 . "Open") (4 . "Open")))
  "The nesting of `wolfram-nb-groups--notebook'.")

(defun wolfram-nb-groups--shape (text)
  "Return (CELLS . STATES) for the notebook TEXT.
CELLS lists each cell's style and the numbers of the groups around it, STATES
the Open or Closed of each group.  Groups are numbered as they are met."
  (let ((file (make-temp-file "wolfram-nb-groups" nil ".nb")))
    (unwind-protect
        (with-temp-buffer
          (with-temp-file file (insert text))
          (let* ((cells (wolfram-nb--parse-notebook file))
                 (numbers (make-hash-table))
                 (count 0)
                 (shape (mapcar
                         (lambda (cell)
                           (cons (wolfram-nb-cell-style cell)
                                 (mapcar (lambda (id)
                                           (or (gethash id numbers)
                                               (puthash id (cl-incf count) numbers)))
                                         (wolfram-nb-cell-group cell))))
                         cells))
                 (states '()))
            (when wolfram-nb--group-info
              (maphash (lambda (id number)
                         (push (cons number (plist-get (gethash id wolfram-nb--group-info)
                                                       :state))
                               states))
                       numbers))
            (cons shape (sort states (lambda (a b) (< (car a) (car b)))))))
      (delete-file file))))

(defun wolfram-nb-groups--read (file)
  "Return the contents of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defmacro wolfram-nb-groups--with-notebook (text file &rest body)
  "Run BODY in a buffer visiting a notebook file FILE that holds TEXT."
  (declare (indent 2))
  `(let* ((dir (make-temp-file "wolfram-nb-groups" t))
          (,file (expand-file-name "n.nb" dir)))
     (with-temp-file ,file (insert ,text))
     (unwind-protect
         (with-current-buffer (find-file-noselect ,file)
           ,@body)
       (dolist (buf (buffer-list))
         (when (and (buffer-file-name buf) (string-prefix-p dir (buffer-file-name buf)))
           (with-current-buffer buf (set-buffer-modified-p nil))
           (kill-buffer buf)))
       (delete-directory dir t))))

(defun wolfram-nb-groups--save-after (edit file)
  "Run EDIT in the current notebook buffer, save, and return the saved shape."
  (funcall edit)
  (set-buffer-modified-p t)
  (save-buffer)
  (wolfram-nb-groups--shape (wolfram-nb-groups--read file)))

(defun wolfram-nb-groups--replace (from to)
  "Replace the text FROM by TO in the current buffer."
  (goto-char (point-min))
  (unless (search-forward from nil t)
    (error "No %S in the buffer" from))
  (replace-match to t t))

;;; Parsing

(ert-deftest wolfram-nb-groups-test-parse-reads-the-nesting ()
  (should (equal (wolfram-nb-groups--shape wolfram-nb-groups--notebook)
                 wolfram-nb-groups--original-shape)))

(ert-deftest wolfram-nb-groups-test-flat-notebook-has-no-groups ()
  (let ((shape (wolfram-nb-groups--shape wolfram-nb-groups--flat-notebook)))
    (should (equal (car shape) '(("Section") ("Input"))))
    (should-not (cdr shape))))

;;; Round trip

(ert-deftest wolfram-nb-groups-test-unedited-notebook-keeps-its-groups ()
  (wolfram-nb-groups--with-notebook wolfram-nb-groups--notebook file
    (should (equal (wolfram-nb-groups--save-after #'ignore file)
                   wolfram-nb-groups--original-shape))
    ;; and once more, from the file that was written
    (kill-buffer)
    (with-current-buffer (find-file-noselect file)
      (should (equal (wolfram-nb-groups--save-after #'ignore file)
                     wolfram-nb-groups--original-shape))
      (set-buffer-modified-p nil))))

(ert-deftest wolfram-nb-groups-test-saving-twice-gives-the-same-file ()
  (wolfram-nb-groups--with-notebook wolfram-nb-groups--notebook file
    (wolfram-nb-groups--save-after #'ignore file)
    (let ((first (wolfram-nb-groups--read file)))
      (revert-buffer t t)
      (wolfram-nb-groups--save-after #'ignore file)
      (should (equal first (wolfram-nb-groups--read file))))))

(ert-deftest wolfram-nb-groups-test-editing-cells-keeps-their-groups ()
  "A cell whose text changed stays in the group it was in."
  (wolfram-nb-groups--with-notebook wolfram-nb-groups--notebook file
    (should (equal (wolfram-nb-groups--save-after
                    (lambda ()
                      (wolfram-nb-groups--replace "Intro" "Introduction")
                      (wolfram-nb-groups--replace "intro text" "different text")
                      (wolfram-nb-groups--replace "1+1" "1+2")
                      (wolfram-nb-groups--replace "Sub\n" "Sub heading\n")
                      (wolfram-nb-groups--replace "Next" "Following"))
                    file)
                   wolfram-nb-groups--original-shape))))

(ert-deftest wolfram-nb-groups-test-editing-keeps-a-cell-in-its-group-by-uuid ()
  "With an ExpressionUUID a cell is found again however it was edited."
  (let ((text (concat "Notebook[{\n"
                      "Cell[CellGroupData[{\n"
                      "Cell[\"Alpha\", \"Section\", ExpressionUUID -> \"a-1\"],\n"
                      "Cell[\"one\", \"Text\", ExpressionUUID -> \"a-2\"],\n"
                      "Cell[\"two\", \"Text\", ExpressionUUID -> \"a-3\"]}, Closed]],\n"
                      "Cell[CellGroupData[{\n"
                      "Cell[\"Beta\", \"Section\", ExpressionUUID -> \"b-1\"],\n"
                      "Cell[\"three\", \"Text\", ExpressionUUID -> \"b-2\"]}, Open]]\n"
                      "}]\n")))
    (wolfram-nb-groups--with-notebook text file
      (should (equal (wolfram-nb-groups--save-after
                      (lambda ()
                        (wolfram-nb-groups--replace "Beta" "Gamma")
                        (wolfram-nb-groups--replace "two" "completely other words")
                        (wolfram-nb-groups--replace "three" "more words"))
                      file)
                     '((("Section" 1) ("Text" 1) ("Text" 1) ("Section" 2) ("Text" 2))
                       . ((1 . "Closed") (2 . "Open"))))))))

;;; New cells

(ert-deftest wolfram-nb-groups-test-new-input-with-result-becomes-a-group ()
  (wolfram-nb-groups--with-notebook wolfram-nb-groups--notebook file
    (should (equal (wolfram-nb-groups--save-after
                    (lambda ()
                      (goto-char (point-max))
                      (insert "\n#+begin_src wolfram\n3+3\n#+end_src\n\n"
                              "#+RESULTS:\n#+begin_example\n6\n#+end_example\n"))
                    file)
                   '((("Section" 1) ("Text" 1) ("Input" 1 2) ("Output" 1 2)
                      ("Subsection" 1 3) ("Text" 1 3) ("Section" 4) ("Text" 4)
                      ("Input" 4 5) ("Output" 4 5))
                     . ((1 . "Open") (2 . "Closed") (3 . "Open") (4 . "Open") (5 . "Open")))))))

(ert-deftest wolfram-nb-groups-test-new-result-joins-the-group-of-its-input ()
  "Evaluating again replaces the output; the group and its state stay."
  (wolfram-nb-groups--with-notebook wolfram-nb-groups--notebook file
    (should (equal (wolfram-nb-groups--save-after
                    (lambda ()
                      (wolfram-nb--apply-eval-result
                       (save-excursion (goto-char (point-min))
                                       (re-search-forward "^#\\+end_src\n\n")
                                       (point))
                       '(:status "ok" :result "TWO") "1+1"))
                    file)
                   wolfram-nb-groups--original-shape))
    (should (string-match-p "\"TWO\", \"Output\"" (wolfram-nb-groups--read file)))))

(ert-deftest wolfram-nb-groups-test-text-after-an-input-group-is-outside-it ()
  (wolfram-nb-groups--with-notebook wolfram-nb-groups--notebook file
    (let ((shape (wolfram-nb-groups--save-after
                  (lambda ()
                    (wolfram-nb-groups--replace
                     "#+end_example\n" "#+end_example\n\nAdded text.\n"))
                  file)))
      (should (equal (nth 4 (car shape)) '("Text" 1))))))

(ert-deftest wolfram-nb-groups-test-new-headings-open-groups ()
  (wolfram-nb-groups--with-notebook wolfram-nb-groups--notebook file
    (let ((shape (wolfram-nb-groups--save-after
                  (lambda ()
                    (goto-char (point-max))
                    (insert "\n** Third\n\nthird text\n\n*** Under third\n\ndeep text\n"))
                  file)))
      (should (equal (last (car shape) 5)
                     '(("Text" 4) ("Section" 5) ("Text" 5) ("Subsection" 5 6) ("Text" 5 6))))
      (should (equal (cdr (assq 5 (cdr shape))) "Open")))))

(ert-deftest wolfram-nb-groups-test-flat-notebook-stays-flat ()
  (wolfram-nb-groups--with-notebook wolfram-nb-groups--flat-notebook file
    (let ((shape (wolfram-nb-groups--save-after
                  (lambda ()
                    (goto-char (point-max))
                    (insert "\n#+begin_src wolfram\n2\n#+end_src\n\n"
                            "#+RESULTS:\n#+begin_example\n2\n#+end_example\n"))
                  file)))
      (should (equal (car shape) '(("Section") ("Input") ("Input") ("Output"))))
      (should-not (cdr shape))
      (should-not (string-match-p "CellGroupData" (wolfram-nb-groups--read file))))))

;;; New notebooks

(defconst wolfram-nb-groups--new-org
  (concat "#+TITLE: A new notebook\n\n"
          "* Part\n\n** Section\n\nSome text.\n\n"
          "#+begin_src wolfram\n1+1\n#+end_src\n\n"
          "#+RESULTS:\n#+begin_example\n2\n#+end_example\n\n"
          "** Next\n\nMore text.\n")
  "Org text for a notebook written from scratch.")

(defconst wolfram-nb-groups--new-shape
  '((("Title" 1) ("Chapter" 1 2) ("Section" 1 2 3) ("Text" 1 2 3)
     ("Input" 1 2 3 4) ("Output" 1 2 3 4) ("Section" 1 2 5) ("Text" 1 2 5))
    . ((1 . "Open") (2 . "Open") (3 . "Open") (4 . "Open") (5 . "Open")))
  "The groups of `wolfram-nb-groups--new-org', as the Front End makes them.")

(defmacro wolfram-nb-groups--in-new-directory (&rest body)
  "Run BODY with `dir' bound to a new directory, and remove it and its buffers."
  (declare (indent 0))
  `(let ((dir (make-temp-file "wolfram-nb-groups" t)))
     (unwind-protect
         (progn ,@body)
       (dolist (buf (buffer-list))
         (when (and (buffer-file-name buf) (string-prefix-p dir (buffer-file-name buf)))
           (with-current-buffer buf (set-buffer-modified-p nil))
           (kill-buffer buf)))
       (delete-directory dir t))))

(ert-deftest wolfram-nb-groups-test-notebook-visited-before-it-exists-is-grouped ()
  (wolfram-nb-groups--in-new-directory
    (let ((file (expand-file-name "fresh.nb" dir)))
      (with-current-buffer (find-file-noselect file)
        (insert wolfram-nb-groups--new-org)
        (save-buffer)
        (should (equal (wolfram-nb-groups--shape (wolfram-nb-groups--read file))
                       wolfram-nb-groups--new-shape))))))

(ert-deftest wolfram-nb-groups-test-empty-notebook-file-is-grouped ()
  (wolfram-nb-groups--in-new-directory
    (let ((file (expand-file-name "empty.nb" dir)))
      (with-temp-file file)
      (with-current-buffer (find-file-noselect file)
        (insert wolfram-nb-groups--new-org)
        (save-buffer)
        (should (equal (wolfram-nb-groups--shape (wolfram-nb-groups--read file))
                       wolfram-nb-groups--new-shape))))))

(ert-deftest wolfram-nb-groups-test-notebook-made-with-the-command-is-grouped ()
  (wolfram-nb-groups--in-new-directory
    (let ((file (expand-file-name "made.nb" dir)))
      (wolfram-nb-create-new file)
      (save-buffer)
      (should (equal (wolfram-nb-groups--shape (wolfram-nb-groups--read file))
                     '((("Title" 1) ("Chapter" 1 2) ("Input" 1 2))
                       . ((1 . "Open") (2 . "Open"))))))))

(ert-deftest wolfram-nb-groups-test-new-notebook-is-stable-when-opened-and-saved-again ()
  (wolfram-nb-groups--in-new-directory
    (let ((file (expand-file-name "stable.nb" dir)))
      (with-current-buffer (find-file-noselect file)
        (insert wolfram-nb-groups--new-org)
        (save-buffer)
        (set-buffer-modified-p nil)
        (kill-buffer))
      (let ((first (wolfram-nb-groups--read file)))
        (with-current-buffer (find-file-noselect file)
          (set-buffer-modified-p t)
          (save-buffer)
          (should (equal first (wolfram-nb-groups--read file)))
          (should (equal (wolfram-nb-groups--shape (wolfram-nb-groups--read file))
                         wolfram-nb-groups--new-shape)))))))

;;; Against the Front End

(defconst wolfram-nb-groups--fe-file
  (expand-file-name "corpus/fe-groups.txt"
                    (file-name-directory (or load-file-name buffer-file-name default-directory)))
  "Recorded answers of the Front End: how it groups lists of cells.
One line per list: the styles, a tab, the nesting.  Made with CreateDocument and
NotebookGet on Wolfram Engine 15.0 (see corpus/README.md).")

(defun wolfram-nb-groups--derived (styles)
  "Return the nesting of cells of STYLES, as new cells in a notebook with groups.
The format is that of the recorded file."
  (with-temp-buffer
    (setq wolfram-nb--group-info (make-hash-table)
          wolfram-nb--group-chains (make-hash-table :test 'equal)
          wolfram-nb--group-uuids (make-hash-table :test 'equal))
    (let* ((cells (cl-loop for style in styles for i from 1
                           collect (format "Cell[\"c%d\", \"%s\"]" i style)))
           (chains (car (wolfram-nb--resolve-chains cells)))
           (stack '())
           (top '()))
      (cl-labels ((add (x) (if stack (push x (cdr (car stack))) (push x top)))
                  (close ()
                    (let ((group (pop stack)))
                      (add (concat "(G (" (mapconcat #'identity (reverse (cdr group)) " ") "))")))))
        (cl-loop for style in styles for i from 0
                 do (let* ((chain (aref chains i))
                           (current (reverse (mapcar #'car stack)))
                           (shared (cl-loop for a in current for b in chain
                                            while (equal a b) count t)))
                      (while (> (length stack) shared) (close))
                      (dolist (id (nthcdr shared chain)) (push (list id) stack))
                      (add style)))
        (while stack (close)))
      (concat "(" (mapconcat #'identity (nreverse top) " ") ")"))))

(ert-deftest wolfram-nb-groups-test-new-cells-are-grouped-like-the-front-end ()
  "For lists of cells as a notebook has them, the groups made for new cells are
those the Front End makes.  The Front End also groups two cells in a row that
are both Print, Title or Subtitle; that is not reproduced."
  (let ((checked 0) (wrong '()))
    (with-temp-buffer
      (insert-file-contents wolfram-nb-groups--fe-file)
      (dolist (line (split-string (buffer-string) "\n" t))
        (let* ((parts (split-string line "\t"))
               (styles (split-string (car parts) ","))
               (skip (cl-loop for (a b) on styles
                              thereis (and b (equal a b)
                                           (member a '("Print" "Title" "Subtitle"))))))
          (unless skip
            (setq checked (1+ checked))
            (let ((mine (wolfram-nb-groups--derived styles)))
              (unless (equal mine (cadr parts))
                (push (list (car parts) (cadr parts) mine) wrong)))))))
    (should (> checked 1000))
    (should-not (seq-take (nreverse wrong) 3))))

(provide 'test-groups)
;;; test-groups.el ends here
