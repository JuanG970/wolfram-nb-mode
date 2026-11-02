;;; test-fuzz.el --- Seeded fuzzing of the cell <-> Org conversion -*- lexical-binding: t; -*-

;;; Commentary:
;; Builds cells from fragments chosen to confuse Org (headline keywords, tags,
;; block delimiters, list markers, markup, entities, links, quotes and
;; backslashes), writes them as a notebook, converts every cell to Org and back
;; as if it had been edited, and checks that the text and the surrounding cells
;; survive.  The generator is seeded, so a failure is reproducible.
;;
;; The environment variable WNB_FUZZ_N sets the number of cases per style
;; (default 60); WNB_FUZZ_SEED changes the seed.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'subr-x)
(add-to-list 'load-path
             (file-name-directory
              (directory-file-name
               (file-name-directory (or load-file-name buffer-file-name default-directory)))))
(require 'wolfram-nb-mode)

;;; Fragments, written as they appear inside a Wolfram string literal

(defconst wolfram-nb-fuzz--words
  '("word" "foo" "Bar" "x1" "naïve" "日本語" "α" "😀" "\\[Alpha]" "\\[Dash]" "\\:03b1"
    "\\.e9" "hello,world" "(parenthesis)" "{brace}" "a.b" "q?" "it's")
  "Harmless fragments.")

(defconst wolfram-nb-fuzz--blanks
  '(" " "  " "\\n" "\\n\\n" "\\t" " \\n ")
  "Whitespace fragments (a space, a newline escape, a tab escape).")

(defconst wolfram-nb-fuzz--org
  '("* " "** " "- " "+ " "1. " "2) " "#" "#+begin_src" "#+end_src" "#+end_example"
    "#+TITLE: t" "#+NAME: n" ":PROPERTIES:" ":END:" "| a | b |" "-----" ": fixed"
    "[[a][b]]" "[[x]]" "https://x.y/z" "<https://q.r>" "*b*" "/i/" "_u_" "=v=" "~c~"
    "+s+" "*" "/" "_" "=" "~" "+" "a_b" "a^b" "a_{b}" "\\\\alpha" "\\\\\\\\" "$x$"
    "$$y$$" "<2026-10-29 Thu>" "[1/3]" "[50%]" "[fn:1]" "{{{m(a)}}}" "<<t>>"
    "src_python{1}" "@@html:b@@" "TODO " "DONE " "COMMENT " "[#A] " " :tag:" ":a:b:"
    "\\\\begin{x}" "\\\\(z\\\\)" ",*" ",#+" "\\\"" "\\\\" "(*" "*)" "[" "]" ";" "<" ">")
  "Fragments that mean something to Org.")

(defun wolfram-nb-fuzz--pick (list)
  "Return a random element of LIST."
  (nth (random (length list)) list))

(defun wolfram-nb-fuzz--fragments (n)
  "Return a list of N random fragments."
  (cl-loop repeat n
           collect (let ((roll (random 10)))
                     (cond ((< roll 3) (wolfram-nb-fuzz--pick wolfram-nb-fuzz--words))
                           ((< roll 5) (wolfram-nb-fuzz--pick wolfram-nb-fuzz--blanks))
                           (t (wolfram-nb-fuzz--pick wolfram-nb-fuzz--org))))))

;;; Reading a string literal body like the Front End does

(defun wolfram-nb-fuzz--decode (body)
  "Return the text of the string literal BODY.
Only backslash, quote, newline and tab escapes are decoded; others stay."
  (let ((i 0) (n (length body)) (out nil))
    (while (< i n)
      (let ((c (aref body i)))
        (if (and (eq c ?\\) (< (1+ i) n))
            (let ((next (aref body (1+ i))))
              (pcase next
                (?\\ (push ?\\ out) (setq i (+ i 2)))
                (?\" (push ?\" out) (setq i (+ i 2)))
                (?n (push ?\n out) (setq i (+ i 2)))
                (?t (push ?\t out) (setq i (+ i 2)))
                (_ (push c out) (setq i (1+ i)))))
          (push c out)
          (setq i (1+ i)))))
    (apply #'string (nreverse out))))

;;; Running one case

(defvar wolfram-nb-fuzz--uuid 0)

(defun wolfram-nb-fuzz--notebook (cells)
  "Return notebook text for the cell strings CELLS."
  (concat "Notebook[{\n" (string-join cells ",\n") "\n}]\n"))

(defun wolfram-nb-fuzz--round-trip (cells)
  "Convert the cell strings CELLS to Org and back as if edited.
Return the list of resulting cell strings."
  (let ((file (make-temp-file "wolfram-nb-fuzz" nil ".nb")))
    (unwind-protect
        (with-temp-buffer
          (wolfram-nb-mode)
          (with-temp-file file (insert (wolfram-nb-fuzz--notebook cells)))
          (let* ((parsed (wolfram-nb--parse-notebook file))
                 (org (wolfram-nb--cells-to-org parsed)))
            (setq wolfram-nb--box-sources nil)
            (cons org (wolfram-nb--org-to-cells org))))
      (delete-file file))))

(defun wolfram-nb-fuzz--body-of (cell-string)
  "Return the string literal body of CELL-STRING if it is a plain string cell."
  (when (string-match "\\`Cell\\[\"" cell-string)
    (let ((i (match-end 0)) (n (length cell-string)))
      (while (and (< i n) (not (eq (aref cell-string i) ?\")))
        (setq i (+ i (if (eq (aref cell-string i) ?\\) 2 1))))
      (and (< i n) (substring cell-string (match-end 0) i)))))

(defun wolfram-nb-fuzz--tabs-as-spaces (body)
  "Return BODY with a tab escape read as a space (see the known limits)."
  (replace-regexp-in-string "\\\\t" " " body))

(defun wolfram-nb-fuzz--trim-body (body)
  "Trim blanks, written as spaces and \\n or \\t escapes, from both ends of BODY."
  (let ((again t))
    (while again
      (setq again nil)
      (cond ((string-prefix-p " " body) (setq body (substring body 1) again t))
            ((string-match "\\`\\\\[nt]" body) (setq body (substring body 2) again t))
            ((string-suffix-p " " body) (setq body (substring body 0 -1) again t))
            ((and (string-match "\\\\[nt]\\'" body)
                  (let ((k 0) (j (- (length body) 3)))
                    (while (and (>= j 0) (eq (aref body j) ?\\))
                      (setq k (1+ k) j (1- j)))
                    (= (% k 2) 0)))
             (setq body (substring body 0 -2) again t)))))
  body)

(defun wolfram-nb-fuzz--text-of (cell-string)
  "Return the text a saved CELL-STRING shows, and its style."
  (let ((cell (wolfram-nb--parse-cell cell-string)))
    (and cell (cons (wolfram-nb-cell-style cell)
                    ;; the mark that tells an escaped backslash from the start of
                    ;; a character escape is not part of the text
                    (replace-regexp-in-string "\\\\\u200c" "\\"
                                              (wolfram-nb-cell-content cell) t t)))))

(defconst wolfram-nb-fuzz--single-line-styles
  '("Title" "Subtitle" "Chapter" "Section" "Subsection" "Subsubsection"
    "Item" "Subitem" "Subsubitem" "ItemNumbered" "SubitemNumbered")
  "Styles whose text is one line in Org.")

(defun wolfram-nb-fuzz--same-meaning (text)
  "Return TEXT with spellings that mean the same thing made equal.
`~code~' and `=verbatim=' are both a Courier span, and a tab after an Org
object is read as a space."
  (replace-regexp-in-string "[~=]" "="
                            (replace-regexp-in-string "\t" " " text)))

(defun wolfram-nb-fuzz--squash (text)
  "Return TEXT with every run of whitespace removed."
  (replace-regexp-in-string "[ \t\n​]+" "" text))

(defun wolfram-nb-fuzz--case (style fragments)
  "Run one case: a cell of STYLE holding FRAGMENTS between two plain cells.
Return nil when it round-trips, else a description of what went wrong."
  (let* ((body (apply #'concat fragments))
         (id (cl-incf wolfram-nb-fuzz--uuid))
         (cell (format "Cell[\"%s\", \"%s\", ExpressionUUID -> \"fz%d\"]" body style id))
         (cells (list "Cell[\"before\", \"Text\"]" cell "Cell[\"after\", \"Text\"]"))
         (expected (string-trim (wolfram-nb-fuzz--decode body)))
         (single (member style wolfram-nb-fuzz--single-line-styles))
         (result (condition-case err
                     (wolfram-nb-fuzz--round-trip cells)
                   (error (list :error (format "ERROR %S" err))))))
    (cond
     ((keywordp (car result))
      (list :style style :body body :problem (cadr result)))
     (t
      (let* ((org (car result)) (back (cdr result))
             (parts (mapcar #'wolfram-nb-fuzz--text-of back)))
        (cond
         ((/= (length back) 3)
          (list :style style :body body :org org
                :problem (format "%d cells instead of 3: %S" (length back) back)))
         ((not (equal (car (nth 1 parts)) style))
          (list :style style :body body :org org
                :problem (format "style became %S" (car (nth 1 parts)))))
         ((not (equal (cdr (nth 0 parts)) "before"))
          (list :style style :body body :org org :problem "the cell before changed"))
         ((not (equal (cdr (nth 2 parts)) "after"))
          (list :style style :body body :org org :problem "the cell after changed"))
         ;; A plain string cell must keep exactly the text that was in the file.
         ((and (not single)
               (member style '("Text" "Input" "Code" "Output" "Print" "Message"))
               (wolfram-nb-fuzz--body-of (nth 1 back))
               (not (equal (wolfram-nb-fuzz--tabs-as-spaces (wolfram-nb-fuzz--body-of (nth 1 back)))
                           (wolfram-nb-fuzz--tabs-as-spaces (wolfram-nb-fuzz--trim-body body)))))
          (list :style style :body body :org org
                :expected (wolfram-nb-fuzz--trim-body body)
                :got (wolfram-nb-fuzz--body-of (nth 1 back))
                :problem "the text in the file changed"))
         ((if single
              (not (equal (wolfram-nb-fuzz--squash
                           (wolfram-nb-fuzz--same-meaning (cdr (nth 1 parts))))
                          (wolfram-nb-fuzz--squash
                           (wolfram-nb-fuzz--same-meaning expected))))
            (not (equal (wolfram-nb-fuzz--same-meaning (cdr (nth 1 parts)))
                        (wolfram-nb-fuzz--same-meaning expected))))
          (list :style style :body body :org org :expected expected
                :got (cdr (nth 1 parts)) :problem "text changed"))))))))

;;; Driving

(defun wolfram-nb-fuzz--count ()
  "Return the number of cases per style."
  (string-to-number (or (getenv "WNB_FUZZ_N") "60")))

(defun wolfram-nb-fuzz--run (styles)
  "Fuzz every style in STYLES and return the list of failures."
  (random (or (getenv "WNB_FUZZ_SEED") "wolfram-nb-fuzz-1"))
  (let ((failures nil))
    (dolist (style styles)
      (dotimes (_ (wolfram-nb-fuzz--count))
        (let ((result (wolfram-nb-fuzz--case
                       style (wolfram-nb-fuzz--fragments (1+ (random 7))))))
          (when result (push result failures)))))
    (nreverse failures)))

(defun wolfram-nb-fuzz--report (failures)
  "Return a readable summary of the first FAILURES."
  (mapconcat
   (lambda (f)
     (format "[%s] %s\n  body:     %S\n  org:      %S\n  expected: %S\n  got:      %S"
             (plist-get f :style)
             (substring-no-properties (format "%s" (plist-get f :problem)))
             (plist-get f :body)
             (and (plist-get f :org)
                  (let ((o (substring-no-properties (plist-get f :org))))
                    (substring o (min 7 (length o)) (min (length o) 300))))
             (and (plist-get f :expected) (substring-no-properties (plist-get f :expected)))
             (and (plist-get f :got) (substring-no-properties (plist-get f :got)))))
   (cl-subseq failures 0 (min 6 (length failures)))
   "\n"))

(defmacro wolfram-nb-fuzz--deftest (name styles)
  "Define a fuzz test NAME over STYLES."
  `(ert-deftest ,name ()
     (let ((failures (wolfram-nb-fuzz--run ',styles)))
       (when failures
         (message "%d failure(s)\n%s" (length failures)
                  (wolfram-nb-fuzz--report failures)))
       (should-not failures))))

(wolfram-nb-fuzz--deftest wolfram-nb-fuzz-test-paragraphs ("Text"))
(wolfram-nb-fuzz--deftest wolfram-nb-fuzz-test-headings
  ("Title" "Subtitle" "Chapter" "Section" "Subsection" "Subsubsection"))
(wolfram-nb-fuzz--deftest wolfram-nb-fuzz-test-list-items
  ("Item" "Subitem" "Subsubitem" "ItemNumbered" "SubitemNumbered"))
(wolfram-nb-fuzz--deftest wolfram-nb-fuzz-test-code ("Input" "Code"))
(wolfram-nb-fuzz--deftest wolfram-nb-fuzz-test-output ("Output" "Print" "Message"))

;;; Several cells in one notebook
;;
;; Some failures need neighbours: a block opened in one cell and closed by a
;; later one swallows the cells between them.

(defconst wolfram-nb-fuzz--mixed-styles
  '("Text" "Text" "Text" "Section" "Subsection" "Item" "Subitem" "ItemNumbered"
    "Input" "Code" "Output" "Print" "Title")
  "Styles used in mixed notebooks.")

(defun wolfram-nb-fuzz--mixed-case (count)
  "Round-trip a notebook of COUNT random cells; return the problems found."
  (let* ((specs (cl-loop for i from 1 to count
                         collect (let* ((style (wolfram-nb-fuzz--pick wolfram-nb-fuzz--mixed-styles))
                                        (body (apply #'concat (wolfram-nb-fuzz--fragments (1+ (random 6))))))
                                   (list style body i))))
         (cells (mapcar (lambda (spec)
                          (format "Cell[\"%s\", \"%s\", ExpressionUUID -> \"mx%d\"]"
                                  (nth 1 spec) (nth 0 spec) (nth 2 spec)))
                        specs))
         (result (condition-case err (wolfram-nb-fuzz--round-trip cells)
                   (error (list :error (format "%S" err)))))
         (problems nil))
    (if (keywordp (car result))
        (list (list :problem (cadr result)))
      (let ((back (cdr result)))
        (if (/= (length back) count)
            (list (list :problem (format "%d cells became %d" count (length back))
                        :specs specs))
          (cl-loop for spec in specs for out in back
                   do (let* ((parsed (wolfram-nb-fuzz--text-of out))
                             (style (nth 0 spec)) (body (nth 1 spec))
                             (single (member style wolfram-nb-fuzz--single-line-styles))
                             (expected (string-trim (wolfram-nb-fuzz--decode body))))
                        (cond
                         ((not (equal (car parsed) style))
                          (push (list :problem (format "style %s became %s" style (car parsed))
                                      :spec spec) problems))
                         ((if single
                              (not (equal (wolfram-nb-fuzz--squash
                                           (wolfram-nb-fuzz--same-meaning (cdr parsed)))
                                          (wolfram-nb-fuzz--squash
                                           (wolfram-nb-fuzz--same-meaning expected))))
                            (not (equal (wolfram-nb-fuzz--same-meaning (cdr parsed))
                                        (wolfram-nb-fuzz--same-meaning expected))))
                          (push (list :problem "text changed" :spec spec
                                      :expected expected :got (cdr parsed))
                                problems)))))
          (nreverse problems))))))

(ert-deftest wolfram-nb-fuzz-test-mixed-notebooks ()
  (random (or (getenv "WNB_FUZZ_SEED") "wolfram-nb-fuzz-mixed"))
  (let (problems)
    (dotimes (_ (max 5 (/ (wolfram-nb-fuzz--count) 6)))
      (setq problems (append problems (wolfram-nb-fuzz--mixed-case 30))))
    (when problems
      (message "%d problem(s)\n%s" (length problems)
               (mapconcat (lambda (p) (format "%S" p))
                          (cl-subseq problems 0 (min 6 (length problems))) "\n")))
    (should-not problems)))

;;; Rich text, judged by the kernel

(defun wolfram-nb-fuzz--rich-part (depth)
  "Return a random piece of TextData as source text."
  (let ((roll (random 12)))
    (cond
     ((< roll 4) (format "\"%s\"" (apply #'concat (wolfram-nb-fuzz--fragments (1+ (random 3))))))
     ((< roll 6) (format "StyleBox[\"%s\", \"%s\"]"
                         (apply #'concat (wolfram-nb-fuzz--fragments (1+ (random 3))))
                         (wolfram-nb-fuzz--pick '("Bold" "Italic" "Underlined" "Courier"))))
     ((= roll 6) (format "StyleBox[\"%s\", FontColor -> RGBColor[1, 0, 0]]"
                         (apply #'concat (wolfram-nb-fuzz--fragments (1+ (random 3))))))
     ((= roll 7) (format "ButtonBox[\"%s\", BaseStyle -> \"Hyperlink\", ButtonData -> {URL[\"https://e.x/%d\"], None}]"
                         (apply #'concat (wolfram-nb-fuzz--fragments (1+ (random 3)))) (random 100)))
     ((= roll 8) (format "Cell[BoxData[FractionBox[\"a\", \"%d\"]], \"InlineFormula\"]" (random 9)))
     ((and (= roll 9) (< depth 1))
      (format "StyleBox[{%s, %s}, \"%s\"]"
              (wolfram-nb-fuzz--rich-part (1+ depth)) (wolfram-nb-fuzz--rich-part (1+ depth))
              (wolfram-nb-fuzz--pick '("Bold" "Italic"))))
     (t (format "\"%s\"" (wolfram-nb-fuzz--pick wolfram-nb-fuzz--words))))))

(defun wolfram-nb-fuzz--rich-cell (i)
  "Return a random TextData cell string numbered I."
  (format "Cell[TextData[{%s}], \"%s\", ExpressionUUID -> \"rf%d\"]"
          (mapconcat #'identity
                     (cl-loop repeat (1+ (random 5)) collect (wolfram-nb-fuzz--rich-part 0))
                     ", ")
          (wolfram-nb-fuzz--pick '("Text" "Text" "Section" "Item" "Subsection"))
          i))

(ert-deftest wolfram-nb-fuzz-test-rich-text-judged-by-the-kernel ()
  "Edited rich cells keep their words, whatever is mixed into them."
  (unless (wolfram-nb-kernel-available-p) (ert-skip "No Wolfram kernel found"))
  (let* ((compare (expand-file-name "corpus/compare.wl"
                                    (file-name-directory
                                     (or load-file-name buffer-file-name default-directory))))
         (kernel (wolfram-nb-kernel-start))
         (original (make-temp-file "wolfram-nb-rich" nil ".nb"))
         (saved (make-temp-file "wolfram-nb-rich" nil ".nb")))
    (unwind-protect
        (progn
          (condition-case err
              (wolfram-nb-kernel-eval-sync kernel (format "Get[%S]" compare) :wait 120)
            (wolfram-nb-kernel-error
             (ert-skip (format "The Wolfram kernel could not be started: %s" (cadr err)))))
          (random (or (getenv "WNB_FUZZ_SEED") "wolfram-nb-fuzz-rich"))
          (let* ((count (max 100 (* 4 (wolfram-nb-fuzz--count))))
                 (cells (cl-loop for i from 1 to count collect (wolfram-nb-fuzz--rich-cell i))))
            (with-temp-file original (insert (wolfram-nb-fuzz--notebook cells)))
            ;; convert first: writing a file switches to a buffer of its own
            (let ((text (with-temp-buffer
                          (wolfram-nb-mode)
                          (let ((org (wolfram-nb--cells-to-org
                                      (wolfram-nb--parse-notebook original))))
                            (setq wolfram-nb--box-sources nil)
                            (wolfram-nb--cells-to-notebook (wolfram-nb--org-to-cells org))))))
              (with-temp-file saved (insert text)))
            (let ((differ (plist-get
                           (wolfram-nb-kernel-eval-sync
                            kernel (format "WolframNBCompare`wordsDiffer[%S, %S]" original saved)
                            :timeout 120 :wait 180)
                           :result)))
              (should (equal differ "0")))))
      (wolfram-nb-kernel-stop kernel)
      (delete-file original)
      (delete-file saved))))

(provide 'test-fuzz)
;;; test-fuzz.el ends here
