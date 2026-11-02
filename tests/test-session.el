;;; test-session.el --- Tests for session/kernel connection -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for session endpoint parsing, TaggingRules roundtrip,
;; smart dispatch, and session-related interactive commands.

;;; Code:

(require 'ert)
(add-to-list 'load-path
             (file-name-directory
              (directory-file-name
               (file-name-directory (or load-file-name buffer-file-name default-directory)))))
(require 'wolfram-nb-mode)

;;; Endpoint parsing

(ert-deftest wolfram-nb-test-parse-endpoint-host-port ()
  (should (equal (wolfram-nb--parse-endpoint "localhost:6061")
                 '("localhost" 6061 "/"))))

(ert-deftest wolfram-nb-test-parse-endpoint-port-only ()
  (should (equal (wolfram-nb--parse-endpoint "6061")
                 '("localhost" 6061 "/"))))

(ert-deftest wolfram-nb-test-parse-endpoint-custom-host ()
  (should (equal (wolfram-nb--parse-endpoint "192.168.1.10:8080")
                 '("192.168.1.10" 8080 "/"))))

(ert-deftest wolfram-nb-test-parse-endpoint-with-path ()
  (should (equal (wolfram-nb--parse-endpoint "localhost:6061/evaluate")
                 '("localhost" 6061 "/evaluate"))))

(ert-deftest wolfram-nb-test-parse-endpoint-nil ()
  (should (null (wolfram-nb--parse-endpoint nil))))

(ert-deftest wolfram-nb-test-parse-endpoint-empty ()
  (should (null (wolfram-nb--parse-endpoint "")))
  (should (null (wolfram-nb--parse-endpoint "   "))))

;;; Session from org buffer

(ert-deftest wolfram-nb-test-session-from-org ()
  (with-temp-buffer
    (wolfram-nb-mode)
    (insert "#+TITLE: Test\n#+WOLFRAM_SESSION: localhost:7070\n\n* Section\n")
    (should (equal (wolfram-nb--session-from-org) "localhost:7070"))))

(ert-deftest wolfram-nb-test-session-from-org-absent ()
  (with-temp-buffer
    (wolfram-nb-mode)
    (insert "#+TITLE: Test\n\n* Section\n")
    (should (null (wolfram-nb--session-from-org)))))

(ert-deftest wolfram-nb-test-session-from-org-trims-whitespace ()
  (with-temp-buffer
    (wolfram-nb-mode)
    (insert "#+WOLFRAM_SESSION:   localhost:9090  \n")
    (should (equal (wolfram-nb--session-from-org) "localhost:9090"))))

;;; Session from TaggingRules

(ert-deftest wolfram-nb-test-session-from-tagging-rules ()
  (should (equal (wolfram-nb--session-from-tagging-rules
                  "TaggingRules -> {\"WolframNBSession\" -> \"localhost:6061\"}, FrontEndVersion -> \"14.0\"")
                 "localhost:6061")))

(ert-deftest wolfram-nb-test-session-from-tagging-rules-absent ()
  (should (null (wolfram-nb--session-from-tagging-rules
                 "FrontEndVersion -> \"14.0\"")))
  (should (null (wolfram-nb--session-from-tagging-rules nil))))

;;; Refresh session

(ert-deftest wolfram-nb-test-refresh-session-from-org ()
  (with-temp-buffer
    (wolfram-nb-mode)
    (insert "#+WOLFRAM_SESSION: localhost:5050\n")
    (wolfram-nb--refresh-session)
    (should (equal wolfram-nb--session-endpoint '("localhost" 5050 "/")))
    (should (equal wolfram-nb--session-raw "localhost:5050"))))

(ert-deftest wolfram-nb-test-refresh-session-nothing ()
  (with-temp-buffer
    (wolfram-nb-mode)
    (let ((wolfram-nb-default-session nil))
      (wolfram-nb--refresh-session)
      (should (null wolfram-nb--session-endpoint))
      (should (null wolfram-nb--session-raw)))))

(ert-deftest wolfram-nb-test-refresh-session-default ()
  (with-temp-buffer
    (wolfram-nb-mode)
    (insert "#+TITLE: Test\n")
    (let ((wolfram-nb-default-session "myhost:9999"))
      (wolfram-nb--refresh-session)
      (should (equal wolfram-nb--session-endpoint '("myhost" 9999 "/"))))))

;;; Session active-p

(ert-deftest wolfram-nb-test-session-active-p-yes ()
  (with-temp-buffer
    (wolfram-nb-mode)
    (setq wolfram-nb--session-endpoint '("localhost" 6061 "/"))
    (should (wolfram-nb--session-active-p))))

(ert-deftest wolfram-nb-test-session-active-p-nil ()
  (with-temp-buffer
    (wolfram-nb-mode)
    (setq wolfram-nb--session-endpoint nil)
    (should-not (wolfram-nb--session-active-p))))

(ert-deftest wolfram-nb-test-session-active-p-zero-port ()
  (with-temp-buffer
    (wolfram-nb-mode)
    (setq wolfram-nb--session-endpoint '("localhost" 0 "/"))
    (should-not (wolfram-nb--session-active-p))))

;;; Session URL

(ert-deftest wolfram-nb-test-session-url ()
  (with-temp-buffer
    (wolfram-nb-mode)
    (setq wolfram-nb--session-endpoint '("localhost" 6061 "/"))
    (should (equal (wolfram-nb--session-url) "http://localhost:6061/"))))

(ert-deftest wolfram-nb-test-session-url-custom-path ()
  (with-temp-buffer
    (wolfram-nb-mode)
    (setq wolfram-nb--session-endpoint '("localhost" 6061 "/eval"))
    (should (equal (wolfram-nb--session-url) "http://localhost:6061/eval"))))

(ert-deftest wolfram-nb-test-session-url-no-session ()
  (with-temp-buffer
    (wolfram-nb-mode)
    (setq wolfram-nb--session-endpoint nil)
    (should (null (wolfram-nb--session-url)))))

(ert-deftest wolfram-nb-test-parse-endpoint-with-path-preserves-path ()
  (should (equal (wolfram-nb--parse-endpoint "localhost:3840/evaluate")
                 '("localhost" 3840 "/evaluate"))))

(ert-deftest wolfram-nb-test-session-url-uses-endpoint-path ()
  (with-temp-buffer
    (wolfram-nb-mode)
    (setq wolfram-nb--session-endpoint '("localhost" 3840 "/evaluate"))
    (should (equal (wolfram-nb--session-url) "http://localhost:3840/evaluate"))))

(ert-deftest wolfram-nb-test-refresh-session-preserves-path ()
  (with-temp-buffer
    (wolfram-nb-mode)
    (insert "#+WOLFRAM_SESSION: localhost:3840/evaluate\n")
    (wolfram-nb--refresh-session)
    (should (equal wolfram-nb--session-endpoint '("localhost" 3840 "/evaluate")))
    (should (equal (wolfram-nb--session-url) "http://localhost:3840/evaluate"))))

;;; TaggingRules injection

(ert-deftest wolfram-nb-test-inject-tagging-rules-new ()
  (let ((result (wolfram-nb--inject-tagging-rules nil "localhost:6061")))
    (should (string-match "WolframNBSession" result))
    (should (string-match "localhost:6061" result))))

(ert-deftest wolfram-nb-test-inject-tagging-rules-append-to-existing ()
  (let* ((opts "FrontEndVersion -> \"14.0\"")
         (result (wolfram-nb--inject-tagging-rules opts "localhost:6061")))
    (should (string-match "WolframNBSession" result))
    (should (string-match "FrontEndVersion" result))))

(ert-deftest wolfram-nb-test-inject-tagging-rules-update-existing ()
  (let* ((opts "TaggingRules -> {\"WolframNBSession\" -> \"localhost:6061\"}, FrontEndVersion -> \"14.0\"")
         (result (wolfram-nb--inject-tagging-rules opts "myhost:7070")))
    (should (string-match "myhost:7070" result))
    (should-not (string-match "localhost:6061" result))
    (should (string-match "FrontEndVersion" result))))

(ert-deftest wolfram-nb-test-inject-tagging-rules-nil-session ()
  (let* ((opts "TaggingRules -> {\"WolframNBSession\" -> \"localhost:6061\"}, FrontEndVersion -> \"14.0\"")
         (result (wolfram-nb--inject-tagging-rules opts nil)))
    (should (equal result opts))))

;;; Full TaggingRules roundtrip via cells-to-notebook

(ert-deftest wolfram-nb-test-notebook-serialization-with-session ()
  (with-temp-buffer
    (wolfram-nb-mode)
    (setq wolfram-nb--session-raw "localhost:6061"
          wolfram-nb--session-endpoint '("localhost" 6061 "/")
          wolfram-nb--notebook-options nil)
    (let* ((cells (list "Cell[\"Test\", \"Text\"]"))
           (nb-text (wolfram-nb--cells-to-notebook cells)))
      (should (string-match "WolframNBSession" nb-text))
      (should (string-match "localhost:6061" nb-text)))))

;;; cells-to-org includes session line

(ert-deftest wolfram-nb-test-cells-to-org-with-session ()
  (with-temp-buffer
    (wolfram-nb-mode)
    (setq wolfram-nb--session-raw "localhost:6061")
    (let* ((cells (list (wolfram-nb-cell-create :content "Test" :style "Text")))
           (org-text (wolfram-nb--cells-to-org cells)))
      (should (string-match "#\\+WOLFRAM_SESSION: localhost:6061" org-text)))))

(ert-deftest wolfram-nb-test-cells-to-org-without-session ()
  (with-temp-buffer
    (wolfram-nb-mode)
    (setq wolfram-nb--session-raw nil)
    (let* ((cells (list (wolfram-nb-cell-create :content "Test" :style "Text")))
           (org-text (wolfram-nb--cells-to-org cells)))
      (should-not (string-match "#\\+WOLFRAM_SESSION:" org-text)))))

;;; Full .nb file roundtrip with TaggingRules

(ert-deftest wolfram-nb-test-tagging-rules-roundtrip ()
  (let ((temp-file (make-temp-file "wolfram-nb-test-" nil ".nb")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "Notebook[{\nCell[\"Hello\", \"Text\"]\n},\nTaggingRules -> {\"WolframNBSession\" -> \"localhost:6061\"}]\n"))
          (with-temp-buffer
            (wolfram-nb-mode)
            (let* ((cells (wolfram-nb--parse-notebook temp-file)))
              (should (equal wolfram-nb--session-raw "localhost:6061"))
              (should (equal wolfram-nb--session-endpoint '("localhost" 6061 "/")))
              (let ((org-text (wolfram-nb--cells-to-org cells)))
                (should (string-match "#\\+WOLFRAM_SESSION: localhost:6061" org-text))))))
      (delete-file temp-file))))

;;; set-session interactive command

(ert-deftest wolfram-nb-test-set-session-inserts-keyword ()
  (with-temp-buffer
    (wolfram-nb-mode)
    (insert "#+TITLE: Test\n\n* Section\n")
    (wolfram-nb-set-session "localhost:8080")
    (goto-char (point-min))
    (should (re-search-forward "#\\+WOLFRAM_SESSION: localhost:8080" nil t))
    (should (equal wolfram-nb--session-raw "localhost:8080"))
    (should (equal wolfram-nb--session-endpoint '("localhost" 8080 "/")))))

(ert-deftest wolfram-nb-test-set-session-updates-existing ()
  (with-temp-buffer
    (wolfram-nb-mode)
    (insert "#+WOLFRAM_SESSION: localhost:6061\n#+TITLE: Test\n")
    (wolfram-nb-set-session "myhost:9999")
    (goto-char (point-min))
    (should (re-search-forward "#\\+WOLFRAM_SESSION: myhost:9999" nil t))
    (should-not (string-match "localhost:6061" (buffer-string)))))

(provide 'test-session)
;;; test-session.el ends here
