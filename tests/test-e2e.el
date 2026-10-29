;;; test-e2e.el --- End-to-end notebook tests against a real kernel -*- lexical-binding: t; -*-

;;; Commentary:
;; Open a notebook, evaluate it on a persistent kernel, save it, and check the
;; saved file with the kernel itself.  Everything here is skipped when no
;; Wolfram kernel can be started.

;;; Code:

(require 'ert)
(require 'cl-lib)
(add-to-list 'load-path
             (file-name-directory
              (directory-file-name
               (file-name-directory (or load-file-name buffer-file-name default-directory)))))
(require 'wolfram-nb-mode)

(defconst wolfram-nb-e2e--notebook
  (concat "Notebook[{\n"
          "Cell[\"Demo notebook\", \"Title\"],\n"
          "Cell[\"Setup\", \"Section\"],\n"
          "Cell[\"State carries over from cell to cell.\", \"Text\"],\n"
          "Cell[\"total = 0; Do[total += k, {k, 10}]; total\", \"Input\"],\n"
          "Cell[\"total * 2\", \"Input\"],\n"
          "Cell[\"Results\", \"Section\"],\n"
          "Cell[\"Plot[Sin[t], {t, 0, 2 Pi}]\", \"Input\"],\n"
          "Cell[\"Print[\\\"printed\\\"]; Sin[1, 2]\", \"Input\"],\n"
          "Cell[\"The end.\", \"Text\"]\n}]\n")
  "The notebook the end-to-end tests start from.")

(defun wolfram-nb-e2e--count (regexp)
  "Count the matches of REGEXP in the buffer."
  (save-excursion
    (goto-char (point-min))
    (let ((n 0))
      (while (re-search-forward regexp nil t) (setq n (1+ n)))
      n)))

(defun wolfram-nb-e2e--buffer-text ()
  "Return the contents of the current buffer."
  (buffer-substring-no-properties (point-min) (point-max)))

(defvar wolfram-nb-e2e--shared-kernel nil
  "The kernel most notebooks in these tests use; stopped when Emacs exits.")

(defun wolfram-nb-e2e--start-kernel ()
  "Start and probe a kernel, or skip the test when none can be started."
  (unless (wolfram-nb-kernel-available-p)
    (ert-skip "No Wolfram kernel found"))
  (let ((kernel (wolfram-nb-kernel-start)))
    (condition-case err
        (wolfram-nb-kernel-eval-sync kernel "1" :wait 120)
      (wolfram-nb-kernel-error
       (ert-skip (format "The Wolfram kernel could not be started: %s"
                         (cadr err)))))
    kernel))

(defun wolfram-nb-e2e--attach-kernel (&optional own)
  "Give the current buffer a kernel.
With OWN the buffer gets a kernel of its own, which dies with the buffer.
Otherwise it uses the shared kernel, after resetting its definitions."
  (if own
      (progn
        (setq wolfram-nb--kernel (wolfram-nb-e2e--start-kernel))
        (add-hook 'kill-buffer-hook #'wolfram-nb-kernel-quit nil t))
    (unless (wolfram-nb-kernel-live-p wolfram-nb-e2e--shared-kernel)
      (setq wolfram-nb-e2e--shared-kernel (wolfram-nb-e2e--start-kernel)))
    (wolfram-nb-kernel-eval-sync wolfram-nb-e2e--shared-kernel
                                 "Quiet[Clear[\"Global`*\"]]" :wait 30)
    (setq wolfram-nb--kernel wolfram-nb-e2e--shared-kernel))
  wolfram-nb--kernel)

(defvar wolfram-nb-e2e--own-kernel nil
  "Non-nil makes `wolfram-nb-e2e--with-notebook' give each buffer its own kernel.")

(defmacro wolfram-nb-e2e--with-notebook (file text &rest body)
  "Run BODY in a notebook buffer for FILE initialised from TEXT.
FILE is bound to a temporary .nb path.  The buffer and the file are cleaned
up afterwards; a kernel of the buffer's own is stopped with it."
  (declare (indent 2))
  `(let* ((,file (make-temp-file "wolfram-nb-e2e" nil ".nb"))
          (buf nil))
     (with-temp-file ,file (insert ,text))
     (unwind-protect
         (progn
           (wolfram-nb-open ,file)
           (setq buf (current-buffer))
           (with-current-buffer buf
             (let ((wolfram-nb-eval-timeout 120))
               (wolfram-nb-e2e--attach-kernel wolfram-nb-e2e--own-kernel)
               ,@body)))
       (when (buffer-live-p buf) (kill-buffer buf))
       (when (file-exists-p ,file) (delete-file ,file)))))

(defun wolfram-nb-e2e--kernel-eval (code)
  "Evaluate CODE on the current buffer's kernel and return the result text."
  (plist-get (wolfram-nb-kernel-eval-sync wolfram-nb--kernel code
                                          :timeout 60 :flags "-")
             :result))

(defun wolfram-nb-e2e--wait-for (predicate seconds)
  "Wait up to SECONDS for PREDICATE to become true; return its value."
  (let ((deadline (+ (float-time) seconds)) value)
    (while (and (not (setq value (funcall predicate)))
                (< (float-time) deadline))
      (accept-process-output nil 0.1))
    value))

(ert-deftest wolfram-nb-e2e-test-open-evaluate-save-reopen ()
  "The whole loop: open, evaluate, save, check with the kernel, reopen, save."
  (wolfram-nb-e2e--with-notebook file wolfram-nb-e2e--notebook
    ;; Opened as Org.
    (should (string-match-p "^#\\+TITLE: Demo notebook" (wolfram-nb-e2e--buffer-text)))
    (should (= (wolfram-nb-e2e--count "begin_src wolfram\n") 4))

    ;; Evaluate everything top to bottom on one kernel.
    (wolfram-nb-eval-buffer)
    (let ((text (wolfram-nb-e2e--buffer-text)))
      ;; 55 then 110 can only happen if `total' survived between cells.
      (should (string-match-p "begin_example\n55\n#\\+end_example" text))
      (should (string-match-p "begin_example\n110\n#\\+end_example" text))
      ;; Print output and a message are shown with the result.
      (should (string-match-p "printed" text))
      (should (string-match-p "Sin::argx" text))
      ;; The plot is kept as a verbatim Output cell with its preview.
      (should (string-match-p ":style \"Output\" :id \"large-cell-[0-9]+\"" text))
      (should-not (string-match-p "GraphicsBox" text)))
    (should (> (hash-table-count wolfram-nb--png-cache) 0))
    (maphash (lambda (_id png) (should (equal (substring png 1 4) "PNG")))
             wolfram-nb--png-cache)

    ;; Save and look at the file.
    (wolfram-nb-save)
    (let ((saved (with-temp-buffer (insert-file-contents file) (buffer-string))))
      (should (string-prefix-p "Notebook[{" saved))
      (should (string-match-p "Cell\\[BoxData\\[GraphicsBox\\[" saved))
      (should (string-match-p "\"Output\"" saved))
      (should-not (string-match-p "Cell\\[\"GraphicsBox" saved)))

    ;; The kernel reads the saved file as a Notebook whose plot is a real graphic.
    (let ((lit (format "%S" file)))
      (should (equal (wolfram-nb-e2e--kernel-eval
                      (format "Head[Get[%s]]" lit))
                     "Notebook"))
      (should (equal (wolfram-nb-e2e--kernel-eval
                      (format "With[{nb = Get[%s]}, Head[ToExpression[First[Cases[nb, Cell[BoxData[b_], \"Output\", ___] /; !FreeQ[b, GraphicsBox] :> b, Infinity]], StandardForm]]]"
                              lit))
                     "Graphics"))
      (should (equal (wolfram-nb-e2e--kernel-eval
                      (format "Count[Get[%s], Cell[_, \"Input\", ___], Infinity]" lit))
                     "4")))

    ;; Reopen the saved notebook: graphics come back as placeholders, and a
    ;; second save leaves the cells untouched.
    (let ((first-save (with-temp-buffer (insert-file-contents file) (buffer-string)))
          (reopened (wolfram-nb-open file)))
      (ignore reopened)
      (let ((second (current-buffer)))
        (unwind-protect
            (progn
              (should (string-match-p "begin_src wolfram-raw" (wolfram-nb-e2e--buffer-text)))
              (should-not (string-match-p "GraphicsBox" (wolfram-nb-e2e--buffer-text)))
              (wolfram-nb-save)
              (should (equal first-save
                             (with-temp-buffer (insert-file-contents file)
                                               (buffer-string)))))
          (kill-buffer second))))))

(ert-deftest wolfram-nb-e2e-test-kernel-restart-forgets-state ()
  (let ((wolfram-nb-e2e--own-kernel t))
    (wolfram-nb-e2e--with-notebook file wolfram-nb-e2e--notebook
    (ignore file)
    (should (equal (wolfram-nb-e2e--kernel-eval "keep = 41; keep + 1") "42"))
    (let ((old wolfram-nb--kernel))
      (wolfram-nb-kernel-restart)
      (should-not (eq old wolfram-nb--kernel))
      (should-not (wolfram-nb-kernel-live-p old))
      (should (equal (wolfram-nb-e2e--kernel-eval "keep") "keep"))))))

(ert-deftest wolfram-nb-e2e-test-async-evaluation ()
  (wolfram-nb-e2e--with-notebook file wolfram-nb-e2e--notebook
    (ignore file)
    (goto-char (point-min))
    (re-search-forward "^#\\+begin_src wolfram\n")
    (beginning-of-line 0)
    (wolfram-nb-eval-block-async)
    (should (wolfram-nb-e2e--wait-for
             (lambda () (string-match-p "begin_example\n55\n" (wolfram-nb-e2e--buffer-text)))
             120))))

(ert-deftest wolfram-nb-e2e-test-killing-the-buffer-stops-the-kernel ()
  (let ((wolfram-nb-e2e--own-kernel t)
        kernel)
    (wolfram-nb-e2e--with-notebook file wolfram-nb-e2e--notebook
      (ignore file)
      (setq kernel wolfram-nb--kernel)
      (should (wolfram-nb-kernel-live-p kernel)))
    (should-not (wolfram-nb-kernel-live-p kernel))))

(ert-deftest wolfram-nb-e2e-test-org-babel-uses-the-kernel ()
  (wolfram-nb-e2e--with-notebook file wolfram-nb-e2e--notebook
    (ignore file)
    (should (equal (org-babel-execute:wolfram "bab = 6; bab * 7" nil) "42"))
    (should (equal (org-babel-execute:wolfram "bab" nil) "6"))))

(ert-deftest wolfram-nb-e2e-test-timeout-reports-and-recovers ()
  (wolfram-nb-e2e--with-notebook file wolfram-nb-e2e--notebook
    (ignore file)
    (wolfram-nb-e2e--kernel-eval "survivor = 9;")
    (let ((wolfram-nb-eval-timeout 1))
      (should-error (wolfram-nb--eval-detailed "Pause[5]; 1")
                    :type 'wolfram-nb-eval-error))
    (should (equal (wolfram-nb-e2e--kernel-eval "survivor") "9"))))

(provide 'test-e2e)
;;; test-e2e.el ends here
