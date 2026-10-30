;;; test-workflow.el --- Opening, saving and reverting notebooks like any file -*- lexical-binding: t; -*-

;;; Commentary:
;; A notebook is opened with `find-file' or from Dired and saved with
;; `save-buffer', `C-x C-s' or Evil's `:w'.  These tests go through the same
;; entry points a user does.  No kernel is needed.  The Evil tests are
;; skipped when Evil is not installed.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'dired)
(add-to-list 'load-path
             (file-name-directory
              (directory-file-name
               (file-name-directory (or load-file-name buffer-file-name default-directory)))))
(require 'wolfram-nb-mode)

(defconst wolfram-nb-workflow--notebook
  (concat "(* Content-type: application/vnd.wolfram.mathematica *)\n\n"
          "Notebook[{\n"
          "Cell[\"Test Notebook\", \"Section\"],\n"
          "Cell[\"A short text.\", \"Text\"],\n"
          "Cell[\"x = 5;\\ny = 10;\\nx + y\", \"Input\"]\n"
          "}]\n")
  "A small notebook to work on.")

(defun wolfram-nb-workflow--text (file)
  "Return the contents of FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

(defmacro wolfram-nb-workflow--with-copy (file &rest body)
  "Run BODY with FILE bound to a fresh notebook file in its own directory.
Buffers visiting the directory's files are discarded afterwards."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "wolfram-nb-workflow" t))
          (,file (expand-file-name "simple.nb" dir)))
     (with-temp-file ,file (insert wolfram-nb-workflow--notebook))
     (unwind-protect
         (progn ,@body)
       (dolist (buf (buffer-list))
         (when (and (buffer-file-name buf)
                    (string-prefix-p dir (buffer-file-name buf)))
           (with-current-buffer buf (set-buffer-modified-p nil))
           (kill-buffer buf)))
       (dolist (buf (buffer-list))
         (when (and (derived-mode-p 'dired-mode)
                    (equal (with-current-buffer buf default-directory)
                           (file-name-as-directory dir)))
           (kill-buffer buf)))
       (delete-directory dir t))))

(defun wolfram-nb-workflow--org-p ()
  "Return non-nil when the buffer shows the Org view of the example notebook."
  (and (string-match-p "^\\*+ Test Notebook$" (buffer-string))
       (string-match-p "^#\\+begin_src wolfram$" (buffer-string))
       (not (string-match-p "Notebook\\[{" (buffer-string)))))

(defun wolfram-nb-workflow--is-notebook-file-p (file)
  "Return non-nil when FILE holds notebook text."
  (string-match-p "\\`\\(?:(\\*\\|Notebook\\[\\)" (wolfram-nb-workflow--text file)))

;;; Opening

(ert-deftest wolfram-nb-workflow-test-find-file-shows-org ()
  (wolfram-nb-workflow--with-copy file
    (with-current-buffer (find-file-noselect file)
      (should (derived-mode-p 'wolfram-nb-mode))
      (should (wolfram-nb-workflow--org-p))
      (should-not (buffer-modified-p))
      (should (equal buffer-file-name file))
      (should (equal wolfram-nb--original-file file)))))

(ert-deftest wolfram-nb-workflow-test-dired-opens-the-org-view ()
  (wolfram-nb-workflow--with-copy file
    (dired (file-name-directory file))
    (dired-goto-file file)
    (dired-find-file)
    (should (derived-mode-p 'wolfram-nb-mode))
    (should (wolfram-nb-workflow--org-p))
    (should-not (buffer-modified-p))))

(ert-deftest wolfram-nb-workflow-test-open-command-reuses-the-buffer ()
  (wolfram-nb-workflow--with-copy file
    (let ((first (wolfram-nb-open file))
          (second (wolfram-nb-open file)))
      (should (eq first second))
      (should (equal (buffer-file-name first) file))
      (should (= 1 (length (cl-remove-if-not
                            (lambda (b) (equal (buffer-file-name b) file))
                            (buffer-list))))))))

(ert-deftest wolfram-nb-workflow-test-unreadable-notebook-stays-raw-and-unsaved ()
  "A file that cannot be parsed is neither shown as Org nor written back."
  (let* ((dir (make-temp-file "wolfram-nb-workflow" t))
         (file (expand-file-name "broken.nb" dir))
         (text "Notebook[{ not a cell list"))
    (with-temp-file file (insert text))
    (unwind-protect
        (with-current-buffer (find-file-noselect file)
          (should buffer-read-only)
          (should (equal (buffer-string) text))
          (should-error (wolfram-nb-save) :type 'wolfram-nb-error)
          (should (equal (wolfram-nb-workflow--text file) text))
          (set-buffer-modified-p nil)
          (kill-buffer))
      (delete-directory dir t))))

;;; Saving

(ert-deftest wolfram-nb-workflow-test-save-buffer-writes-the-notebook ()
  (wolfram-nb-workflow--with-copy file
    (with-current-buffer (find-file-noselect file)
      (goto-char (point-max))
      (insert "\n** Added\nHello from the workflow test.\n")
      (should (buffer-modified-p))
      (save-buffer)
      (should-not (buffer-modified-p))
      (should (wolfram-nb-workflow--is-notebook-file-p file))
      (should (string-match-p "Hello from the workflow test"
                              (wolfram-nb-workflow--text file)))
      ;; Emacs must not think the file changed behind its back.
      (should (verify-visited-file-modtime))
      (insert "\nsecond edit\n")
      (save-buffer)
      (should (string-match-p "second edit" (wolfram-nb-workflow--text file))))))

(ert-deftest wolfram-nb-workflow-test-c-x-c-s-is-save-buffer ()
  "The notebook mode leaves C-x C-s to `save-buffer', which runs the save hooks."
  (with-temp-buffer
    (wolfram-nb-mode)
    (should (eq (key-binding (kbd "C-x C-s")) #'save-buffer))))

(ert-deftest wolfram-nb-workflow-test-write-file-saves-under-the-new-name ()
  (wolfram-nb-workflow--with-copy file
    (let ((other (expand-file-name "copy.nb" (file-name-directory file)))
          (before (wolfram-nb-workflow--text file)))
      (with-current-buffer (find-file-noselect file)
        (goto-char (point-max))
        (insert "\n** Copy only\ntext\n")
        (write-file other)
        (should (wolfram-nb-workflow--is-notebook-file-p other))
        (should (string-match-p "Copy only" (wolfram-nb-workflow--text other)))
        (should (equal (wolfram-nb-workflow--text file) before))))))

(ert-deftest wolfram-nb-workflow-test-new-notebook-saves-like-a-file ()
  (let* ((dir (make-temp-file "wolfram-nb-workflow" t))
         (file (expand-file-name "new.nb" dir)))
    (unwind-protect
        (progn
          (wolfram-nb-create-new file)
          (should (equal buffer-file-name file))
          (save-buffer)
          (should (wolfram-nb-workflow--is-notebook-file-p file))
          (should (string-match-p "Introduction" (wolfram-nb-workflow--text file)))
          (set-buffer-modified-p nil)
          (kill-buffer))
      (delete-directory dir t))))

(ert-deftest wolfram-nb-workflow-test-evil-w-saves ()
  (ignore-errors (require 'package) (package-initialize))
  (skip-unless (require 'evil nil t))
  (wolfram-nb-workflow--with-copy file
    (with-current-buffer (find-file-noselect file)
      (evil-mode 1)
      (unwind-protect
          (progn
            (goto-char (point-max))
            (insert "\n** From evil\nwritten with :w\n")
            (evil-ex-execute "w")
            (should-not (buffer-modified-p))
            (should (wolfram-nb-workflow--is-notebook-file-p file))
            (should (string-match-p "written with :w" (wolfram-nb-workflow--text file))))
        (evil-mode -1)))))

;;; Reverting and re-running the mode

(ert-deftest wolfram-nb-workflow-test-revert-reads-the-file-again ()
  (wolfram-nb-workflow--with-copy file
    (with-current-buffer (find-file-noselect file)
      (goto-char (point-max))
      (insert "\n** Unsaved\nlost on revert\n")
      (let ((other wolfram-nb-workflow--notebook))
        (with-temp-file file
          (insert (replace-regexp-in-string "Test Notebook" "Renamed Notebook" other t t))))
      (revert-buffer t t)
      (should (derived-mode-p 'wolfram-nb-mode))
      (should (string-match-p "^\\*+ Renamed Notebook$" (buffer-string)))
      (should-not (string-match-p "lost on revert" (buffer-string)))
      (should-not (buffer-modified-p))
      (should (verify-visited-file-modtime)))))

(ert-deftest wolfram-nb-workflow-test-open-save-revert-save-is-stable ()
  (wolfram-nb-workflow--with-copy file
    (with-current-buffer (find-file-noselect file)
      (set-buffer-modified-p t)
      (save-buffer)
      (let ((first (wolfram-nb-workflow--text file)))
        (revert-buffer t t)
        (set-buffer-modified-p t)
        (save-buffer)
        (should (equal first (wolfram-nb-workflow--text file)))))))

(ert-deftest wolfram-nb-workflow-test-running-the-mode-again-loses-nothing ()
  "`normal-mode' must keep the tables that let unedited cells be written back."
  (wolfram-nb-workflow--with-copy file
    (with-current-buffer (find-file-noselect file)
      (set-buffer-modified-p t)
      (save-buffer)
      (let ((first (wolfram-nb-workflow--text file))
            (text (buffer-string)))
        (normal-mode)
        (should (derived-mode-p 'wolfram-nb-mode))
        (should (equal text (buffer-string)))
        (should (equal wolfram-nb--original-file file))
        (set-buffer-modified-p t)
        (save-buffer)
        (should (equal first (wolfram-nb-workflow--text file)))))))

(provide 'test-workflow)
;;; test-workflow.el ends here
