;;; demo.el --- Interactive demo of wolfram-nb-mode -*- lexical-binding: t; -*-

;;; Commentary:
;; Run this script to see wolfram-nb-mode in action

;;; Code:

(add-to-list 'load-path default-directory)
(require 'wolfram-nb-mode)

(defun demo-wolfram-nb-mode ()
  "Demonstrate wolfram-nb-mode functionality."
  (interactive)
  
  ;; Open the test notebook
  (message "Opening test.nb...")
  (wolfram-nb-open "test.nb")
  
  (message "\n=== Wolfram Notebook Mode Demo ===\n")
  (message "The test.nb file has been opened as an org-mode buffer.")
  (message "\nYou can now:")
  (message "  - Edit the content like any org-mode file")
  (message "  - C-x C-s to save changes back to .nb format")
  (message "  - C-c C-v to view the raw Cell structures")
  (message "  - C-c C-c to reparse the buffer")
  (message "\nThe buffer should now be visible with the notebook content.\n"))

;; Run the demo if called interactively
(when (not noninteractive)
  (demo-wolfram-nb-mode))

(provide 'demo)
;;; demo.el ends here
