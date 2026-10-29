;;; wolfram-nb-kernel.el --- Persistent Wolfram kernel for wolfram-nb-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Juan Gonzalez

;; Author: Juan Gonzalez <juan.angel19@hotmail.com>
;; Package-Requires: ((emacs "26.1"))
;; Keywords: wolfram, mathematica, notebook

;; This file is not part of GNU Emacs.

;; Permission is hereby granted, free of charge, to any person obtaining
;; a copy of this software and associated documentation files (the
;; "Software"), to deal in the Software without restriction, including
;; without limitation the rights to use, copy, modify, merge, publish,
;; distribute, sublicense, and/or sell copies of the Software, and to
;; permit persons to whom the Software is furnished to do so, subject to
;; the following conditions:
;;
;; The above copyright notice and this permission notice shall be
;; included in all copies or substantial portions of the Software.

;;; Commentary:

;; A long-lived Wolfram kernel driven over stdin/stdout.  This is what lets
;; a notebook behave like a Front End session: definitions made in one cell
;; are visible in the next, `%' works, and graphics are rendered by the same
;; kernel that evaluated them.
;;
;; The kernel is `WolframKernel -noprompt'.  Emacs sends it the bootstrap
;; file `wolfram-nb-kernel-boot.wl' as its first input line; the bootstrap
;; then reads one request per line and answers with tagged, base64-encoded
;; lines (see that file for the wire format).  Because the whole protocol is
;; plain text on stdin/stdout, a remote kernel is the same thing behind a
;; command prefix:
;;
;;   (setq wolfram-nb-kernel-command
;;         '("ssh" "-T" "buildbox" "WolframKernel" "-noprompt"))
;;
;; Public API:
;;   `wolfram-nb-kernel-start', `wolfram-nb-kernel-stop'
;;   `wolfram-nb-kernel-eval' (async), `wolfram-nb-kernel-eval-sync'
;;   `wolfram-nb-kernel-live-p', `wolfram-nb-kernel-ready-p'
;;
;; Results are plists: (:status :seconds :stdout :messages :result :png
;; :boxes :error).  :png is a unibyte string of PNG bytes.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(define-error 'wolfram-nb-kernel-error "Wolfram kernel error")

;;;; Customization

(defgroup wolfram-nb-kernel nil
  "Persistent Wolfram kernel sessions for `wolfram-nb-mode'."
  :group 'applications
  :prefix "wolfram-nb-kernel-")

(defcustom wolfram-nb-kernel-command nil
  "Full command (a list of strings) that starts a kernel speaking on stdio.
When nil, the command is built from `wolfram-nb-kernel-program' and
`wolfram-nb-kernel-args'.  Set this to run the kernel somewhere else, for
example through ssh.  The command must end up running
`WolframKernel -noprompt' with its stdin/stdout connected to the process."
  :type '(choice (const :tag "Automatic" nil)
                 (repeat :tag "Command" string))
  :group 'wolfram-nb-kernel)

(defcustom wolfram-nb-kernel-program nil
  "Path to the WolframKernel executable, or nil to look for it."
  :type '(choice (const :tag "Automatic" nil) file)
  :group 'wolfram-nb-kernel)

(defcustom wolfram-nb-kernel-args '("-noprompt")
  "Arguments passed to `wolfram-nb-kernel-program'."
  :type '(repeat string)
  :group 'wolfram-nb-kernel)

(defcustom wolfram-nb-kernel-detach t
  "Whether to start a kernel found automatically in its own session.
Killing a kernel can leave its licence slot allocated on the server, and
Emacs sends SIGHUP to a process group when a process is deleted or Emacs
exits.  Detached with `setsid -w', the kernel does not get those signals; it
exits by itself, and releases its licence, when its input closes.  Has no
effect without `setsid' or when `wolfram-nb-kernel-command' is set."
  :type 'boolean
  :group 'wolfram-nb-kernel)

(defcustom wolfram-nb-kernel-stop-grace 5
  "Seconds to wait for a kernel to exit by itself when it is stopped.
A kernel that is killed instead of quitting may not give its licence back."
  :type 'integer
  :group 'wolfram-nb-kernel)

(defcustom wolfram-nb-kernel-startup-timeout 120
  "Seconds to wait for a kernel to report ready before giving up."
  :type 'integer
  :group 'wolfram-nb-kernel)

;;;; Kernel object

(cl-defstruct (wolfram-nb-kernel
               (:constructor wolfram-nb-kernel--make)
               (:copier nil))
  process
  (state 'starting)            ; starting, ready or dead
  version
  (queue nil)                  ; requests waiting for READY, oldest first
  (pending nil)                ; alist of (ID . request) in flight
  (partial nil)                ; reversed chunks of an unfinished line
  (next-id 0)
  stderr-buffer
  startup-timer
  command
  last-error
  (noise nil))                 ; newest-first untagged lines, for diagnostics

(cl-defstruct (wolfram-nb-kernel--request
               (:constructor wolfram-nb-kernel--request-make)
               (:copier nil))
  id line callback (acc nil))

(defvar wolfram-nb-kernel--directory
  (file-name-directory (or load-file-name buffer-file-name default-directory))
  "Directory holding `wolfram-nb-kernel-boot.wl'.")

;;;; Locating the kernel

(defconst wolfram-nb-kernel--mac-candidates
  '("/Applications/Wolfram.app/Contents/MacOS/WolframKernel"
    "/Applications/Mathematica.app/Contents/MacOS/WolframKernel"
    "/Applications/Wolfram Desktop.app/Contents/MacOS/WolframKernel"
    "/Applications/Wolfram Engine.app/Contents/MacOS/WolframKernel")
  "Usual kernel locations on macOS.")

(defun wolfram-nb-kernel--version-of (path)
  "Return the installation version found in PATH as a list of numbers."
  (when (string-match "/\\([0-9]+\\(?:\\.[0-9]+\\)*\\)/SystemFiles/" path)
    (mapcar #'string-to-number (split-string (match-string 1 path) "\\."))))

(defun wolfram-nb-kernel--newer-p (a b)
  "Return non-nil when kernel path A is a newer installation than B."
  (version-list-< (or (wolfram-nb-kernel--version-of b) '(0))
                  (or (wolfram-nb-kernel--version-of a) '(0))))

(defun wolfram-nb-kernel--candidate-paths ()
  "Return kernel executables found in the usual installation directories."
  (append
   (cl-remove-if-not #'file-executable-p wolfram-nb-kernel--mac-candidates)
   (sort (cl-remove-if-not
          #'file-executable-p
          (file-expand-wildcards
           "/usr/local/Wolfram/*/*/SystemFiles/Kernel/Binaries/*/WolframKernel"))
         #'wolfram-nb-kernel--newer-p)
   (cl-remove-if-not
    #'file-executable-p
    (file-expand-wildcards
     "/opt/Wolfram/*/*/SystemFiles/Kernel/Binaries/*/WolframKernel"))))

(defun wolfram-nb-kernel--ask-wolframscript ()
  "Ask wolframscript where its kernel lives, or return nil."
  (let ((ws (executable-find
             (if (boundp 'wolfram-nb-wolframscript-path)
                 (symbol-value 'wolfram-nb-wolframscript-path)
               "wolframscript"))))
    (when ws
      (with-temp-buffer
        (when (eq 0 (call-process
                     ws nil '(t nil) nil "-code"
                     (concat "WriteString[\"stdout\", FileNameJoin[{"
                             "$InstallationDirectory, \"SystemFiles\", "
                             "\"Kernel\", \"Binaries\", $SystemID, "
                             "\"WolframKernel\"}]]")))
          (let ((path (string-trim (buffer-string))))
            (and (file-executable-p path) path)))))))

(defun wolfram-nb-kernel-find-program ()
  "Return the path of a local WolframKernel executable, or nil."
  (or wolfram-nb-kernel-program
      (executable-find "WolframKernel")
      (car (wolfram-nb-kernel--candidate-paths))
      (wolfram-nb-kernel--ask-wolframscript)))

(defun wolfram-nb-kernel--build-command ()
  "Return the command list used to start a kernel, or nil if none is known."
  (or wolfram-nb-kernel-command
      (let ((program (wolfram-nb-kernel-find-program)))
        (when program
          (let ((command (cons program wolfram-nb-kernel-args)))
            (if (and wolfram-nb-kernel-detach (executable-find "setsid"))
                (append '("setsid" "-w") command)
              command))))))

(defun wolfram-nb-kernel-available-p ()
  "Return non-nil if a kernel command can be built."
  (and (wolfram-nb-kernel--build-command) t))

;;;; Wire format

(defun wolfram-nb-kernel--boot-file ()
  "Return the path of `wolfram-nb-kernel-boot.wl', or signal an error.
It is looked for next to the loaded library, then next to the source file
the library was built from: a package manager may link only the .el files
into its build directory."
  (let* ((name "wolfram-nb-kernel-boot.wl")
         (source (let ((el (locate-library "wolfram-nb-kernel.el" t)))
                   (and el (file-name-directory (file-truename el)))))
         (dirs (delq nil (delete-dups (list wolfram-nb-kernel--directory source)))))
    (or (cl-some (lambda (dir)
                   (let ((file (expand-file-name name dir)))
                     (and (file-exists-p file) file)))
                 dirs)
        (signal 'wolfram-nb-kernel-error
                (list (format "%s not found in %s; install it with the package (recipe :files \"*.el\" \"*.wl\")"
                              name (mapconcat #'identity dirs ", ")))))))

(defun wolfram-nb-kernel--boot-line ()
  "Return the single input line that installs the evaluation loop."
  (let* ((file (wolfram-nb-kernel--boot-file))
         (source (with-temp-buffer
                   (insert-file-contents file)
                   (buffer-string)))
         (b64 (base64-encode-string (encode-coding-string source 'utf-8) t)))
    (format "Get[StringToStream[ByteArrayToString[BaseDecode[\"%s\"], \"UTF-8\"]]]\n"
            b64)))

(defun wolfram-nb-kernel--format-request (id code timeout flags)
  "Build the wire line for request ID evaluating CODE.
TIMEOUT is in seconds or nil, FLAGS is a string of flag letters."
  (format "REQ %s %s %s %s\n"
          id
          (if timeout (format "%s" timeout) "Infinity")
          (if (and flags (not (string-empty-p flags))) flags "-")
          (base64-encode-string (encode-coding-string code 'utf-8) t)))

(defun wolfram-nb-kernel--decode-text (payload)
  "Decode the base64 PAYLOAD of a text item."
  (decode-coding-string (base64-decode-string payload) 'utf-8))

(defconst wolfram-nb-kernel--line-regexp
  "\\`@@WNB \\([^ ]+\\) \\([A-Z]+\\)\\(?: \\(.*\\)\\)?\\'"
  "Matches a tagged line written by the bootstrap.")

;;;; Process plumbing

(defvar wolfram-nb-kernel--registry nil
  "Kernels started by this Emacs that may still be running.")

(defun wolfram-nb-kernel--stderr-tail (kernel)
  "Return what KERNEL last said outside the protocol, stderr and stdout."
  (let* ((buf (wolfram-nb-kernel-stderr-buffer kernel))
         (err (if (buffer-live-p buf)
                  (with-current-buffer buf
                    (string-trim (buffer-substring-no-properties
                                  (max (point-min) (- (point-max) 600))
                                  (point-max))))
                ""))
         (out (mapconcat #'identity
                         (reverse (wolfram-nb-kernel-noise kernel)) " ")))
    (string-trim (concat err " " out))))

(defun wolfram-nb-kernel--deliver (request result)
  "Hand RESULT to the callback of REQUEST, containing any error it raises."
  (let ((callback (wolfram-nb-kernel--request-callback request)))
    (when callback
      (condition-case err
          (funcall callback result)
        (error (message "wolfram-nb kernel callback failed: %s"
                        (error-message-string err)))))))

(defun wolfram-nb-kernel--fail-all (kernel message)
  "Report MESSAGE to every request still waiting on KERNEL."
  (let ((requests (append (mapcar #'cdr (wolfram-nb-kernel-pending kernel))
                          (wolfram-nb-kernel-queue kernel))))
    (setf (wolfram-nb-kernel-pending kernel) nil
          (wolfram-nb-kernel-queue kernel) nil)
    (dolist (request requests)
      (wolfram-nb-kernel--deliver
       request (list :status "error" :error message)))))

(defun wolfram-nb-kernel--transmit (kernel request)
  "Write REQUEST to KERNEL and register it as pending."
  (push (cons (wolfram-nb-kernel--request-id request) request)
        (wolfram-nb-kernel-pending kernel))
  (process-send-string (wolfram-nb-kernel-process kernel)
                       (wolfram-nb-kernel--request-line request)))

(defun wolfram-nb-kernel--mark-ready (kernel version)
  "Record that KERNEL reported VERSION and flush the queued requests."
  (when (timerp (wolfram-nb-kernel-startup-timer kernel))
    (cancel-timer (wolfram-nb-kernel-startup-timer kernel))
    (setf (wolfram-nb-kernel-startup-timer kernel) nil))
  (setf (wolfram-nb-kernel-state kernel) 'ready
        (wolfram-nb-kernel-version kernel) version)
  (let ((queued (wolfram-nb-kernel-queue kernel)))
    (setf (wolfram-nb-kernel-queue kernel) nil)
    (dolist (request queued)
      (wolfram-nb-kernel--transmit kernel request))))

(defun wolfram-nb-kernel--accumulate (request tag payload)
  "Store the item TAG with PAYLOAD in REQUEST."
  (let ((key (pcase tag
               ("STDOUT" :stdout)
               ("MESSAGES" :messages)
               ("RESULT" :result)
               ("PNG" :png)
               ("BOXES" :boxes))))
    (when key
      (push (cons key
                  (if (eq key :png)
                      (base64-decode-string payload)
                    (wolfram-nb-kernel--decode-text payload)))
            (wolfram-nb-kernel--request-acc request)))))

(defun wolfram-nb-kernel--finish (kernel request payload)
  "Complete REQUEST on KERNEL; PAYLOAD is \"<seconds> <status>\"."
  (setf (wolfram-nb-kernel-pending kernel)
        (assoc-delete-all (wolfram-nb-kernel--request-id request)
                          (wolfram-nb-kernel-pending kernel)))
  (let* ((fields (split-string (or payload "") " " t))
         (result (list :status (or (cadr fields) "ok")
                       :seconds (string-to-number (or (car fields) "0")))))
    (dolist (entry (reverse (wolfram-nb-kernel--request-acc request)))
      (setq result (plist-put result (car entry) (cdr entry))))
    (wolfram-nb-kernel--deliver request result)))

(defun wolfram-nb-kernel--note-noise (kernel line)
  "Remember the untagged output LINE of KERNEL, keeping only the newest."
  (unless (string-empty-p (string-trim line))
    (let ((noise (cons (string-trim line) (wolfram-nb-kernel-noise kernel))))
      (setf (wolfram-nb-kernel-noise kernel)
            (if (> (length noise) 8) (butlast noise) noise)))))

(defun wolfram-nb-kernel--handle-line (kernel line)
  "Dispatch one LINE of kernel output.  Untagged lines are only remembered."
  (if (not (string-match wolfram-nb-kernel--line-regexp line))
      (wolfram-nb-kernel--note-noise kernel line)
    (let ((id (match-string 1 line))
          (tag (match-string 2 line))
          (payload (match-string 3 line)))
      (if (equal id "0")
          (when (equal tag "READY")
            (wolfram-nb-kernel--mark-ready kernel payload))
        (let ((request (cdr (assoc id (wolfram-nb-kernel-pending kernel)))))
          (when request
            (if (equal tag "DONE")
                (wolfram-nb-kernel--finish kernel request payload)
              (wolfram-nb-kernel--accumulate request tag payload))))))))

(defun wolfram-nb-kernel--filter (process chunk)
  "Process filter for kernel PROCESS receiving CHUNK."
  (let ((kernel (process-get process 'wolfram-nb-kernel)))
    (when kernel
      (let ((pos 0))
        (while (string-match "\n" chunk pos)
          (let* ((end (match-beginning 0))
                 (line (apply #'concat
                              (nreverse
                               (cons (substring chunk pos end)
                                     (wolfram-nb-kernel-partial kernel))))))
            (setf (wolfram-nb-kernel-partial kernel) nil)
            (setq pos (match-end 0))
            (wolfram-nb-kernel--handle-line
             kernel (string-trim-right line "\r"))))
        (when (< pos (length chunk))
          (push (substring chunk pos) (wolfram-nb-kernel-partial kernel)))))))

(defun wolfram-nb-kernel--sentinel (process event)
  "Process sentinel: fail outstanding requests when PROCESS exits (EVENT).
Safe to call more than once; only the first call after the exit reports."
  (let ((kernel (process-get process 'wolfram-nb-kernel)))
    (when (and kernel (memq (process-status process) '(exit signal)))
      (setq wolfram-nb-kernel--registry
            (delq kernel wolfram-nb-kernel--registry))
      (when (timerp (wolfram-nb-kernel-startup-timer kernel))
        (cancel-timer (wolfram-nb-kernel-startup-timer kernel))
        (setf (wolfram-nb-kernel-startup-timer kernel) nil))
      (unless (eq (wolfram-nb-kernel-state kernel) 'dead)
        (let* ((was-ready (eq (wolfram-nb-kernel-state kernel) 'ready))
               (detail (wolfram-nb-kernel--stderr-tail kernel))
               (message
                (format "Wolfram kernel %s (%s)%s"
                        (if was-ready "exited" "failed to start")
                        (string-trim event)
                        (if (string-empty-p detail) "" (concat ": " detail)))))
          (setf (wolfram-nb-kernel-state kernel) 'dead
                (wolfram-nb-kernel-last-error kernel) message)
          (wolfram-nb-kernel--fail-all kernel message)))
      (when (buffer-live-p (wolfram-nb-kernel-stderr-buffer kernel))
        (kill-buffer (wolfram-nb-kernel-stderr-buffer kernel))))))

(defun wolfram-nb-kernel--settle (kernel)
  "Handle the exit of KERNEL's process if Emacs has not reported it yet."
  (let ((process (wolfram-nb-kernel-process kernel)))
    (when (and (processp process)
               (not (process-live-p process))
               (not (eq (wolfram-nb-kernel-state kernel) 'dead)))
      (accept-process-output process 0.05)
      (wolfram-nb-kernel--sentinel
       process
       (if (eq (process-status process) 'signal)
           (format "killed by signal %s" (process-exit-status process))
         (format "exited abnormally with code %s"
                 (process-exit-status process)))))))

;;;; Public API

(defun wolfram-nb-kernel-live-p (kernel)
  "Return non-nil if KERNEL is a running kernel (ready or still starting)."
  (and (wolfram-nb-kernel-p kernel)
       (memq (wolfram-nb-kernel-state kernel) '(starting ready))
       (process-live-p (wolfram-nb-kernel-process kernel))))

(defun wolfram-nb-kernel-ready-p (kernel)
  "Return non-nil if KERNEL has finished starting."
  (and (wolfram-nb-kernel-live-p kernel)
       (eq (wolfram-nb-kernel-state kernel) 'ready)))

(defun wolfram-nb-kernel-start (&optional command)
  "Start a kernel and return it.  The kernel finishes booting in the background.
COMMAND overrides the configured command.  Signals `wolfram-nb-kernel-error'
when no kernel executable can be found."
  (let ((command (or command (wolfram-nb-kernel--build-command))))
    (unless command
      (signal 'wolfram-nb-kernel-error
              '("No WolframKernel found; set `wolfram-nb-kernel-program' or `wolfram-nb-kernel-command'")))
    (let* ((boot-line (wolfram-nb-kernel--boot-line))
           (kernel (wolfram-nb-kernel--make :command command))
           (stderr (generate-new-buffer " *wolfram-nb-kernel-stderr*"))
           (process (condition-case err
                        (make-process
                         :name "wolfram-nb-kernel"
                         :command command
                         :buffer nil
                         :stderr stderr
                         :coding 'utf-8-unix
                         :connection-type 'pipe
                         :noquery t
                         :filter #'wolfram-nb-kernel--filter
                         :sentinel #'wolfram-nb-kernel--sentinel)
                      (error (kill-buffer stderr)
                             (signal 'wolfram-nb-kernel-error
                                     (list (error-message-string err)))))))
      (set-process-query-on-exit-flag process nil)
      (let ((stderr-process (get-buffer-process stderr)))
        (when stderr-process
          (set-process-query-on-exit-flag stderr-process nil)))
      (process-put process 'wolfram-nb-kernel kernel)
      (push kernel wolfram-nb-kernel--registry)
      (setf (wolfram-nb-kernel-process kernel) process
            (wolfram-nb-kernel-stderr-buffer kernel) stderr)
      ;; A kernel that dies at once is reported by the sentinel.
      (ignore-errors (process-send-string process boot-line))
      (setf (wolfram-nb-kernel-startup-timer kernel)
            (run-at-time wolfram-nb-kernel-startup-timeout nil
                         (lambda ()
                           (when (eq (wolfram-nb-kernel-state kernel) 'starting)
                             (setf (wolfram-nb-kernel-last-error kernel)
                                   "Timed out waiting for the Wolfram kernel to start")
                             (when (process-live-p process)
                               (delete-process process))
                             (wolfram-nb-kernel--fail-all
                              kernel (wolfram-nb-kernel-last-error kernel))
                             (setf (wolfram-nb-kernel-state kernel) 'dead)))))
      kernel)))

(defun wolfram-nb-kernel--wait-exit (process seconds)
  "Wait up to SECONDS for PROCESS to exit; return non-nil if it did."
  (let ((deadline (+ (float-time) seconds)))
    (while (and (process-live-p process) (< (float-time) deadline))
      (accept-process-output process 0.05))
    (not (process-live-p process))))

(defun wolfram-nb-kernel-stop (kernel)
  "Shut KERNEL down, letting it quit so that it returns its licence.
The kernel is asked to quit and its input is closed.  A kernel that is still
booting finishes booting and then exits by itself; it is only killed if it
is still around a minute later."
  (when (wolfram-nb-kernel-p kernel)
    (let ((process (wolfram-nb-kernel-process kernel)))
      (when (timerp (wolfram-nb-kernel-startup-timer kernel))
        (cancel-timer (wolfram-nb-kernel-startup-timer kernel))
        (setf (wolfram-nb-kernel-startup-timer kernel) nil))
      (unless (eq (wolfram-nb-kernel-state kernel) 'dead)
        (setf (wolfram-nb-kernel-state kernel) 'dead)
        (wolfram-nb-kernel--fail-all kernel "Wolfram kernel stopped"))
      (when (process-live-p process)
        (ignore-errors
          (process-send-string process "QUIT\n")
          (process-send-eof process))
        (unless (wolfram-nb-kernel--wait-exit process
                                              wolfram-nb-kernel-stop-grace)
          (run-at-time 60 nil
                       (lambda ()
                         (when (process-live-p process)
                           (delete-process process))))))
      (when (buffer-live-p (wolfram-nb-kernel-stderr-buffer kernel))
        (kill-buffer (wolfram-nb-kernel-stderr-buffer kernel))))))

(defun wolfram-nb-kernel-stop-all ()
  "Stop every kernel this Emacs started, waiting for each to exit."
  (let ((kernels wolfram-nb-kernel--registry))
    (dolist (kernel kernels)
      (wolfram-nb-kernel-stop kernel))
    (dolist (kernel kernels)
      (let ((process (wolfram-nb-kernel-process kernel)))
        (when (process-live-p process)
          (wolfram-nb-kernel--wait-exit process 30)
          (when (process-live-p process)
            (delete-process process)))))))

(add-hook 'kill-emacs-hook #'wolfram-nb-kernel-stop-all)

(cl-defun wolfram-nb-kernel-eval (kernel code callback &key timeout flags)
  "Evaluate CODE on KERNEL and call CALLBACK with the result plist.
TIMEOUT is the in-kernel time limit in seconds (nil for none).  FLAGS is a
string: \"g\" adds a PNG when the result is graphical, \"b\" adds its boxes,
\"p\" forces a PNG for any result.  Returns the request id."
  (when (wolfram-nb-kernel-p kernel)
    (wolfram-nb-kernel--settle kernel))
  (unless (wolfram-nb-kernel-live-p kernel)
    (signal 'wolfram-nb-kernel-error
            (list (or (and (wolfram-nb-kernel-p kernel)
                           (wolfram-nb-kernel-last-error kernel))
                      "Wolfram kernel is not running"))))
  (let* ((id (number-to-string
              (cl-incf (wolfram-nb-kernel-next-id kernel))))
         (request (wolfram-nb-kernel--request-make
                   :id id
                   :line (wolfram-nb-kernel--format-request
                          id code timeout flags)
                   :callback callback)))
    (if (eq (wolfram-nb-kernel-state kernel) 'ready)
        (wolfram-nb-kernel--transmit kernel request)
      (setf (wolfram-nb-kernel-queue kernel)
            (append (wolfram-nb-kernel-queue kernel) (list request))))
    id))

(cl-defun wolfram-nb-kernel-eval-sync (kernel code &key timeout flags wait)
  "Evaluate CODE on KERNEL, blocking until the result plist is available.
WAIT bounds the total wait in seconds; by default it is TIMEOUT plus the
startup time when the kernel is still booting.  Signals
`wolfram-nb-kernel-error' when the kernel dies or does not answer."
  (let* ((result nil)
         (done nil)
         (budget (or wait
                     (+ (or timeout 3600)
                        (if (wolfram-nb-kernel-ready-p kernel)
                            15
                          wolfram-nb-kernel-startup-timeout))))
         (deadline (+ (float-time) budget)))
    (wolfram-nb-kernel-eval kernel code
                            (lambda (r) (setq result r done t))
                            :timeout timeout :flags flags)
    (while (and (not done) (< (float-time) deadline)
                (wolfram-nb-kernel-live-p kernel))
      (accept-process-output (wolfram-nb-kernel-process kernel) 0.1))
    ;; The process may have exited before its sentinel ran.
    (unless done
      (wolfram-nb-kernel--settle kernel))
    (cond
     ((not done)
      (wolfram-nb-kernel-stop kernel)
      (signal 'wolfram-nb-kernel-error
              (list (or (wolfram-nb-kernel-last-error kernel)
                        "Wolfram kernel did not answer in time"))))
     ((plist-get result :error)
      (signal 'wolfram-nb-kernel-error (list (plist-get result :error))))
     (t result))))

(provide 'wolfram-nb-kernel)
;;; wolfram-nb-kernel.el ends here
