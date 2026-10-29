;;; test-kernel.el --- Tests for the persistent kernel client -*- lexical-binding: t; -*-

;;; Commentary:
;; Protocol tests run against tests/fake-kernel.py, so they need python3 but
;; no Wolfram.  The tests at the end use a real kernel and are skipped when
;; none can be started.

;;; Code:

(require 'ert)
(require 'cl-lib)
(let ((tests-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory))))
  (add-to-list 'load-path (file-name-directory (directory-file-name tests-dir)))
  (defconst wolfram-nb-test--fake-kernel
    (expand-file-name "fake-kernel.py" tests-dir)
    "The fake kernel script."))
(require 'wolfram-nb-kernel)

(defun wolfram-nb-test--fake-command ()
  "Return the command that starts the fake kernel."
  (list "python3" wolfram-nb-test--fake-kernel))

(defmacro wolfram-nb-test--with-fake-kernel (var &rest body)
  "Run BODY with VAR bound to a started fake kernel, stopping it afterwards."
  (declare (indent 1))
  `(progn
     (unless (executable-find "python3")
       (ert-skip "python3 is not available"))
     (let ((,var (wolfram-nb-kernel-start (wolfram-nb-test--fake-command))))
       (unwind-protect (progn ,@body)
         (wolfram-nb-kernel-stop ,var)))))

(defun wolfram-nb-test--eval (kernel code &rest args)
  "Evaluate CODE on KERNEL synchronously with ARGS, give the result plist."
  (apply #'wolfram-nb-kernel-eval-sync kernel code :wait 20 args))

;;; Wire format

(ert-deftest wolfram-nb-kernel-test-request-line ()
  (should (equal (wolfram-nb-kernel--format-request "7" "x+1" 30 "gb")
                 (format "REQ 7 30 gb %s\n" (base64-encode-string "x+1" t))))
  (should (string-match-p "\\`REQ 1 Infinity - "
                          (wolfram-nb-kernel--format-request "1" "x" nil nil))))

(ert-deftest wolfram-nb-kernel-test-request-line-utf8 ()
  "Non-ASCII code travels as UTF-8 and comes back intact."
  (let* ((line (wolfram-nb-kernel--format-request "1" "\"ünï ∑\"" nil nil))
         (payload (car (last (split-string (string-trim line) " ")))))
    (should (equal (decode-coding-string (base64-decode-string payload) 'utf-8)
                   "\"ünï ∑\""))))

(ert-deftest wolfram-nb-kernel-test-boot-line ()
  "The bootstrap travels as one line of base64 inside Get[StringToStream[...]]."
  (let ((line (wolfram-nb-kernel--boot-line)))
    (should (string-prefix-p "Get[StringToStream[ByteArrayToString[BaseDecode[\""
                             line))
    (should (= (length (split-string line "\n" t)) 1))))

(ert-deftest wolfram-nb-kernel-test-boot-file-defines-protocol ()
  "The bootstrap file speaks the protocol this client expects."
  (let ((source (with-temp-buffer
                  (insert-file-contents
                   (expand-file-name "wolfram-nb-kernel-boot.wl"
                                     wolfram-nb-kernel--directory))
                  (buffer-string))))
    (dolist (tag '("READY" "STDOUT" "MESSAGES" "RESULT" "PNG" "BOXES" "DONE"))
      (should (string-match-p (format "[ \"]%s[ \"]" tag) source)))))

;;; Command construction

(ert-deftest wolfram-nb-kernel-test-explicit-command-wins ()
  (let ((wolfram-nb-kernel-command '("ssh" "box" "WolframKernel" "-noprompt")))
    (should (equal (wolfram-nb-kernel--build-command)
                   '("ssh" "box" "WolframKernel" "-noprompt")))))

(ert-deftest wolfram-nb-kernel-test-program-and-args ()
  (let ((wolfram-nb-kernel-command nil)
        (wolfram-nb-kernel-program "/opt/wl/WolframKernel")
        (wolfram-nb-kernel-args '("-noprompt" "-noinit")))
    (should (equal (wolfram-nb-kernel--build-command)
                   '("/opt/wl/WolframKernel" "-noprompt" "-noinit")))))

(ert-deftest wolfram-nb-kernel-test-version-ordering ()
  (should (wolfram-nb-kernel--newer-p
           "/usr/local/Wolfram/Wolfram/15.1/SystemFiles/Kernel/x"
           "/usr/local/Wolfram/Mathematica/14.0/SystemFiles/Kernel/x"))
  (should-not (wolfram-nb-kernel--newer-p
               "/usr/local/Wolfram/Mathematica/9.0/SystemFiles/Kernel/x"
               "/usr/local/Wolfram/Mathematica/14.0/SystemFiles/Kernel/x")))

(ert-deftest wolfram-nb-kernel-test-missing-program-signals ()
  (let ((wolfram-nb-kernel-command '("/nonexistent/WolframKernel")))
    (should-error (progn (wolfram-nb-kernel-start)
                         (sleep-for 0.3))
                  :type 'error)))

;;; Against the fake kernel

(ert-deftest wolfram-nb-kernel-test-state-persists ()
  (wolfram-nb-test--with-fake-kernel k
    (should (equal (plist-get (wolfram-nb-test--eval k "x=5;") :result) ""))
    (should (equal (plist-get (wolfram-nb-test--eval k "x") :result) "5"))
    (should (wolfram-nb-kernel-ready-p k))
    (should (equal (wolfram-nb-kernel-version k) "fake-1.0"))))

(ert-deftest wolfram-nb-kernel-test-result-fields ()
  (wolfram-nb-test--with-fake-kernel k
    (let ((r (wolfram-nb-test--eval k "Print:hello")))
      (should (equal (plist-get r :stdout) "hello"))
      (should (equal (plist-get r :status) "ok"))
      (should (numberp (plist-get r :seconds))))
    (should (equal (string-trim (plist-get (wolfram-nb-test--eval k "Msg:f::bad")
                                           :messages))
                   "f::bad"))))

(ert-deftest wolfram-nb-kernel-test-png-and-boxes ()
  (wolfram-nb-test--with-fake-kernel k
    (let ((r (wolfram-nb-test--eval k "Png" :flags "gb")))
      (should (equal (plist-get r :result) "-Graphics-"))
      (should (equal (substring (plist-get r :png) 1 4) "PNG"))
      (should-not (multibyte-string-p (plist-get r :png)))
      (should (equal (plist-get r :boxes) "GraphicsBox[{Circle[{0, 0}]}]")))
    (should-not (plist-get (wolfram-nb-test--eval k "Png" :flags "g") :boxes))))

(ert-deftest wolfram-nb-kernel-test-untagged-output-ignored ()
  (wolfram-nb-test--with-fake-kernel k
    (should (equal (plist-get (wolfram-nb-test--eval k "Noise") :result)
                   "after noise"))
    (should (member "some stray output" (wolfram-nb-kernel-noise k)))))

(ert-deftest wolfram-nb-kernel-test-split-lines ()
  "A reply that arrives in two pieces is reassembled."
  (wolfram-nb-test--with-fake-kernel k
    (should (equal (plist-get (wolfram-nb-test--eval k "Split") :result)
                   "split ok"))))

(ert-deftest wolfram-nb-kernel-test-requests-before-ready-are-queued ()
  "Requests sent while the kernel boots are answered in order."
  (wolfram-nb-test--with-fake-kernel k
    (let ((seen nil))
      (dolist (code '("a=1;" "a" "Print:two"))
        (wolfram-nb-kernel-eval k code
                                (lambda (r) (push (plist-get r :result) seen))))
      (let ((deadline (+ (float-time) 20)))
        (while (and (< (length seen) 3) (< (float-time) deadline))
          (accept-process-output nil 0.1)))
      (should (equal (nreverse seen) '("" "1" ""))))))

(ert-deftest wolfram-nb-kernel-test-async-callback-error-contained ()
  "A failing callback does not break the kernel."
  (wolfram-nb-test--with-fake-kernel k
    (wolfram-nb-kernel-eval k "x=1;" (lambda (_r) (error "Callback blew up")))
    (should (equal (plist-get (wolfram-nb-test--eval k "x=2;") :result) ""))
    (should (equal (plist-get (wolfram-nb-test--eval k "x") :result) "2"))))

(ert-deftest wolfram-nb-kernel-test-death-fails-pending-requests ()
  (wolfram-nb-test--with-fake-kernel k
    (should (wolfram-nb-test--eval k "x=1;"))
    (let ((err (should-error (wolfram-nb-test--eval k "Die")
                             :type 'wolfram-nb-kernel-error)))
      (should (string-match-p "exited" (cadr err))))
    (should-not (wolfram-nb-kernel-live-p k))
    (should-error (wolfram-nb-kernel-eval k "x" #'ignore)
                  :type 'wolfram-nb-kernel-error)))

(ert-deftest wolfram-nb-kernel-test-stop-fails-queued-requests ()
  (unless (executable-find "python3") (ert-skip "python3 is not available"))
  (let* ((k (wolfram-nb-kernel-start (wolfram-nb-test--fake-command)))
         (result nil))
    (wolfram-nb-kernel-eval k "x" (lambda (r) (setq result r)))
    (wolfram-nb-kernel-stop k)
    (should (equal (plist-get result :status) "error"))
    (should (string-match-p "stopped" (plist-get result :error)))
    (should-not (wolfram-nb-kernel-live-p k))))

(ert-deftest wolfram-nb-kernel-test-stop-is-graceful ()
  "Stopping lets the kernel quit by itself and clears the registry."
  (unless (executable-find "python3") (ert-skip "python3 is not available"))
  (let ((k (wolfram-nb-kernel-start (wolfram-nb-test--fake-command))))
    (wolfram-nb-test--eval k "x=1;")
    (should (memq k wolfram-nb-kernel--registry))
    (wolfram-nb-kernel-stop k)
    (should-not (process-live-p (wolfram-nb-kernel-process k)))
    (should-not (memq k wolfram-nb-kernel--registry))))

(ert-deftest wolfram-nb-kernel-test-startup-failure-reports-output ()
  "Text the kernel printed before dying is part of the error."
  (unless (executable-find "sh") (ert-skip "sh is not available"))
  (let* ((wolfram-nb-kernel-startup-timeout 10)
         (k (wolfram-nb-kernel-start
             '("sh" "-c" "echo 'No valid password found.'; exit 61"))))
    (let ((err (should-error (wolfram-nb-test--eval k "1+1")
                             :type 'wolfram-nb-kernel-error)))
      (should (string-match-p "failed to start" (cadr err)))
      (should (string-match-p "No valid password found" (cadr err))))))

;;; A real kernel
;;
;; Starting a kernel takes a licence and a few seconds, so the tests below
;; share one.  It is stopped when Emacs exits.

(defvar wolfram-nb-test--shared-kernel nil
  "The kernel shared by the real-kernel tests.")

(defun wolfram-nb-test--real-kernel ()
  "Return the shared real kernel, starting it, or skip when there is none."
  (unless (wolfram-nb-kernel-available-p)
    (ert-skip "No Wolfram kernel found"))
  (unless (wolfram-nb-kernel-live-p wolfram-nb-test--shared-kernel)
    (let ((k (wolfram-nb-kernel-start)))
      (condition-case err
          (wolfram-nb-kernel-eval-sync k "1" :wait 120)
        (wolfram-nb-kernel-error
         (ert-skip (format "The Wolfram kernel could not be started: %s"
                           (cadr err)))))
      (setq wolfram-nb-test--shared-kernel k)))
  wolfram-nb-test--shared-kernel)

(defmacro wolfram-nb-test--with-real-kernel (var &rest body)
  "Run BODY with VAR bound to the shared real kernel."
  (declare (indent 1))
  `(let ((,var (wolfram-nb-test--real-kernel)))
     ,@body))

(ert-deftest wolfram-nb-kernel-test-real-state-and-history ()
  (wolfram-nb-test--with-real-kernel k
    (should (equal (plist-get (wolfram-nb-test--eval k "x=5;") :result) ""))
    (should (equal (plist-get (wolfram-nb-test--eval k "x+1") :result) "6"))
    (should (equal (plist-get (wolfram-nb-test--eval k "%+1") :result) "7"))
    (should (equal (plist-get (wolfram-nb-test--eval k "f[n_]:=n^2; f[x]")
                              :result)
                   "25"))))

(ert-deftest wolfram-nb-kernel-test-real-print-messages-syntax ()
  (wolfram-nb-test--with-real-kernel k
    (let ((r (wolfram-nb-test--eval k "Print[\"hi\"]; 2")))
      (should (equal (plist-get r :stdout) "hi"))
      (should (equal (plist-get r :result) "2")))
    (should (string-match-p "argx"
                            (plist-get (wolfram-nb-test--eval k "Sin[1,2]")
                                       :messages)))
    (should (string-match-p "sntx"
                            (plist-get (wolfram-nb-test--eval k "1+") :messages)))
    (should (equal (plist-get (wolfram-nb-test--eval k "\"ünï\"") :result)
                   "ünï"))))

(ert-deftest wolfram-nb-kernel-test-real-timeout-keeps-state ()
  (wolfram-nb-test--with-real-kernel k
    (wolfram-nb-test--eval k "y=3;")
    (let ((r (wolfram-nb-test--eval k "Pause[5]; 1" :timeout 1)))
      (should (equal (plist-get r :status) "timeout")))
    (should (equal (plist-get (wolfram-nb-test--eval k "y") :result) "3"))))

(ert-deftest wolfram-nb-kernel-test-real-graphics ()
  (wolfram-nb-test--with-real-kernel k
    (let ((r (wolfram-nb-test--eval k "Plot[Sin[t], {t, 0, 6}]"
                                    :flags "gb" :timeout 120)))
      (should (equal (plist-get r :result) "-Graphics-"))
      (should (equal (substring (plist-get r :png) 1 4) "PNG"))
      (should (string-prefix-p "GraphicsBox[" (plist-get r :boxes))))
    ;; Boxes convert back to a graphic in the same kernel.
    (let ((r (wolfram-nb-test--eval
              k "Head[ToExpression[BoxData[GraphicsBox[{Circle[]}]], StandardForm]]")))
      (should (equal (plist-get r :result) "Graphics")))
    ;; Plain results carry no image unless forced.
    (should-not (plist-get (wolfram-nb-test--eval k "2+2" :flags "gb") :png))
    (should (plist-get (wolfram-nb-test--eval k "2+2" :flags "p") :png))))

(provide 'test-kernel)
;;; test-kernel.el ends here
