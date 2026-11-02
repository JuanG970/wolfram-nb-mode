;;; test-faces.el --- Highlighting of notebook buffers -*- lexical-binding: t; -*-

;;; Commentary:
;; Wolfram highlighting belongs in `wolfram' source blocks only.  Prose,
;; headlines, lists and output blocks of a notebook are left to Org; they once
;; got code faces, so that "This" and "Define" looked like type names.

;;; Code:

(require 'ert)
(require 'cl-lib)
(add-to-list 'load-path
             (file-name-directory
              (directory-file-name
               (file-name-directory (or load-file-name buffer-file-name default-directory)))))
(require 'wolfram-nb-mode)

(defconst wolfram-nb-faces--code-faces
  '(font-lock-type-face font-lock-builtin-face font-lock-function-name-face
    font-lock-variable-name-face font-lock-keyword-face font-lock-comment-face)
  "The faces the Wolfram highlighting uses.")

(defconst wolfram-nb-faces--text
  (concat "** Define Plot Section\n"
          "This is Plot of a Function: x = Sin[y] -> Table.\n"
          "\n"
          "- Item with Map and Range\n"
          "\n"
          "#+begin_src wolfram\n"
          "Plot[Sin[x_] + Foo, {x, 0, 2 Pi}]\n"
          "#+end_src\n"
          "\n"
          "#+begin_example\n"
          "Plot Table\n"
          "#+end_example\n"
          "\n"
          "#+begin_src wolfram-raw\n"
          "Plot Table\n"
          "#+end_src\n"))

(defun wolfram-nb-faces--code-faces-at (word)
  "Return the Wolfram highlighting faces on the first WORD found after point."
  (search-forward word)
  (let* ((face (get-text-property (match-beginning 0) 'face))
         (faces (if (listp face) face (list face))))
    (cl-intersection faces wolfram-nb-faces--code-faces)))

(defmacro wolfram-nb-faces--with-buffer (&rest body)
  "Run BODY in a fontified buffer holding `wolfram-nb-faces--text'."
  (declare (indent 0))
  `(with-temp-buffer
     (wolfram-nb-mode)
     (insert wolfram-nb-faces--text)
     (font-lock-mode 1)
     (font-lock-ensure)
     (goto-char (point-min))
     ,@body))

(ert-deftest wolfram-nb-faces-test-prose-has-no-code-faces ()
  (wolfram-nb-faces--with-buffer
    (dolist (word '("Define" "Section" "This" "Function" "Sin" "Table" "Map" "Range"))
      (should-not (wolfram-nb-faces--code-faces-at word)))))

(ert-deftest wolfram-nb-faces-test-source-block-is-highlighted ()
  (wolfram-nb-faces--with-buffer
    (re-search-forward "^#\\+begin_src wolfram$")
    (should (memq 'font-lock-builtin-face (wolfram-nb-faces--code-faces-at "Plot")))
    (should (memq 'font-lock-builtin-face (wolfram-nb-faces--code-faces-at "Sin")))
    (should (memq 'font-lock-variable-name-face (wolfram-nb-faces--code-faces-at "x_")))
    (should (memq 'font-lock-type-face (wolfram-nb-faces--code-faces-at "Foo")))))

(ert-deftest wolfram-nb-faces-test-lowercase-names-are-not-types ()
  "A case-insensitive search would paint `x' and `y' as type names."
  (wolfram-nb-faces--with-buffer
    (re-search-forward "^#\\+begin_src wolfram$")
    (search-forward "{x")
    (should-not (memq 'font-lock-type-face
                      (let ((face (get-text-property (1- (point)) 'face)))
                        (if (listp face) face (list face)))))))

(ert-deftest wolfram-nb-faces-test-output-and-raw-blocks-are-left-alone ()
  (wolfram-nb-faces--with-buffer
    (re-search-forward "^#\\+begin_example$")
    (should-not (wolfram-nb-faces--code-faces-at "Plot"))
    (re-search-forward "^#\\+begin_src wolfram-raw$")
    (should-not (wolfram-nb-faces--code-faces-at "Plot"))))

(provide 'test-faces)
;;; test-faces.el ends here
