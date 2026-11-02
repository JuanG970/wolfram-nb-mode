;;; roundtrip.el --- Round-trip every notebook of a list through the mode -*- lexical-binding: t; -*-

;; Usage (from tests/):
;;   emacs --batch -Q -L .. -L . -l real/roundtrip.el LIST OUTDIR [FIRST LAST]
;; LIST holds one notebook path per line.  FIRST and LAST, when given, limit the
;; run to those lines of LIST (numbers stay those of LIST), so that several
;; Emacs can share one list and one OUTDIR.  For notebook number N the saved
;; copies are OUTDIR/NNNN.nb (cells left as they were) and OUTDIR/NNNN-e.nb
;; (every cell converted as if edited).  One line per notebook is printed:
;; OK or ERR, the number, the seconds and the path.  `compare.sh' judges the
;; copies with the kernel.  The notebooks themselves are never changed.

;;; Code:

(require 'cl-lib)
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name ".." dir))
  (add-to-list 'load-path (expand-file-name "../.." dir)))
(require 'wolfram-nb-mode)
(require 'test-corpus)

(let* ((list-file (nth 0 command-line-args-left))
       (out-dir (file-name-as-directory (nth 1 command-line-args-left)))
       (all (with-temp-buffer (insert-file-contents list-file)
                              (split-string (buffer-string) "\n" t)))
       (first (if (nth 2 command-line-args-left)
                  (string-to-number (nth 2 command-line-args-left))
                1))
       (last (if (nth 3 command-line-args-left)
                 (string-to-number (nth 3 command-line-args-left))
               (length all)))
       (files (seq-subseq all (1- first) (min last (length all))))
       (n (1- first)))
  (setq command-line-args-left nil)
  (make-directory out-dir t)
  (dolist (file files)
    (setq n (1+ n))
    (let ((start (float-time)))
      (condition-case err
          (progn
            (dolist (forced '(nil t))
              (let ((run (wolfram-nb-corpus--run file forced)))
                (let ((coding-system-for-write 'utf-8-unix))
                  (with-temp-file (format "%s%04d%s.nb" out-dir n (if forced "-e" ""))
                    (insert (wolfram-nb-corpus-run-nb run))))))
            (message "OK %d %.1f %s" n (- (float-time) start) file))
        (error (message "ERR %d %S %s" n (error-message-string err) file))))))
;;; roundtrip.el ends here
