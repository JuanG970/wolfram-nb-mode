;;; test-styles.el --- Inline formatting as the Front End writes it -*- lexical-binding: t; -*-

;;; Commentary:
;; The Front End writes bold, italic, underlined and code text as
;; StyleBox["w", Bold], StyleBox["w", FontSlant->Italic], and so on.  The default
;; stylesheet has no style named "Bold" or "Italic", so a StyleBox with such a
;; name, which this mode used to write, shows nothing.  These tests read every
;; form, write the ones that work, and keep what Org cannot show (colours,
;; sizes) while a span's text is not edited.

;;; Code:

(require 'ert)
(require 'cl-lib)
(add-to-list 'load-path
             (file-name-directory
              (directory-file-name
               (file-name-directory (or load-file-name buffer-file-name default-directory)))))
(require 'wolfram-nb-mode)

(ert-deftest wolfram-nb-styles-test-every-form-is-read ()
  (cl-flet ((flags (&rest options) (wolfram-nb--span-flags options)))
    (should (equal (flags "Bold") '(?b)))
    (should (equal (flags "\"Bold\"") '(?b)))
    (should (equal (flags "FontWeight->Bold") '(?b)))
    (should (equal (flags "FontWeight -> \"Bold\"") '(?b)))
    (should (equal (flags "FontWeight->\"SemiBold\"") '(?b)))
    (should (equal (flags "Italic") '(?i)))
    (should (equal (flags "FontSlant->Italic") '(?i)))
    (should (equal (flags "FontSlant->\"Oblique\"") '(?i)))
    (should (equal (flags "Underlined") '(?u)))
    (should (equal (flags "FontVariations->{\"Underline\"->True}") '(?u)))
    (should (equal (flags "FontFamily->\"Courier\"") '(?c)))
    (should (equal (flags "\"Courier\"") '(?c)))
    ;; several at once, in any arrangement
    (should (equal (flags "Bold" "Italic") '(?b ?i)))
    (should (equal (flags "FontWeight->Bold" "FontSlant->Italic") '(?b ?i)))
    (should (equal (flags "{FontWeight->Bold, FontSlant->Italic}") '(?b ?i)))
    ;; things that are not formatting
    (should-not (flags "FontColor->RGBColor[1, 0, 0]"))
    (should-not (flags "StripOnInput->False"))
    (should-not (flags "FontSize->20"))))

;; What the Front End wrote for Bold, Italic, Underlined, FontFamily and colours
;; is in corpus/fe-styles.nb.
(defconst wolfram-nb-styles--fe-file
  (expand-file-name "corpus/fe-styles.nb"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "A notebook the Front End wrote with every kind of inline formatting.")

(ert-deftest wolfram-nb-styles-test-the-front-ends-own-notebook-keeps-its-formatting ()
  "The Front End's formatting is read, and written back exactly, edited or not."
  (let ((file wolfram-nb-styles--fe-file))
    (with-temp-buffer
      (wolfram-nb-mode)
      (let* ((cells (wolfram-nb--parse-notebook file))
             (org (wolfram-nb--cells-to-org cells)))
        (should (string-match-p
                 "plain \\*bold\\* /italic/ _underlined_ =code= \\*weight\\* /slant/ end\\." org))
        (setq wolfram-nb--box-sources nil)
        (let ((back (mapcar #'substring-no-properties (wolfram-nb--org-to-cells org))))
          ;; the same forms the Front End wrote, and the colours kept
          (should (cl-some (lambda (c) (string-match-p (regexp-quote "StyleBox[\"bold\", FontWeight->Bold]") c)) back))
          (should (cl-some (lambda (c) (string-match-p (regexp-quote "FontColor->RGBColor[1, 0, 0]") c)) back)))))))

(defun wolfram-nb-styles--read (part)
  "Return the Org text of the TextData content PART."
  (with-temp-buffer
    (wolfram-nb-mode)
    (wolfram-nb--parse-textdata-content (format "{%s}" part))))

(ert-deftest wolfram-nb-styles-test-spans-become-org-markup ()
  (should (equal (wolfram-nb-styles--read "\"a \", StyleBox[\"b\", Bold], \" c\"") "a *b* c"))
  (should (equal (wolfram-nb-styles--read "StyleBox[\"b\", FontWeight->Bold]") "*b*"))
  (should (equal (wolfram-nb-styles--read "StyleBox[\"i\", FontSlant->Italic]") "/i/"))
  (should (equal (wolfram-nb-styles--read "StyleBox[\"u\", FontVariations->{\"Underline\"->True}]") "_u_"))
  (should (equal (wolfram-nb-styles--read "StyleBox[\"c\", FontFamily->\"Courier\"]") "=c="))
  ;; both: bold outside, italic inside
  (should (equal (wolfram-nb-styles--read "StyleBox[\"w\", Bold, Italic]") "*/w/*"))
  ;; styling Org cannot show leaves the text plain
  (should (equal (wolfram-nb-styles--read "StyleBox[\"red\", FontColor->RGBColor[1, 0, 0]]") "red")))

(defun wolfram-nb-styles--cell (org)
  "Return the cell string for the Org paragraph ORG, converted as an edited cell."
  (with-temp-buffer
    (wolfram-nb-mode)
    (car (wolfram-nb--org-to-cells org))))

(ert-deftest wolfram-nb-styles-test-formatting-is-written-in-forms-that-work ()
  (let ((cell (wolfram-nb-styles--cell "A *bold*, /italic/, _underlined_ and =code= word.\n")))
    (should (string-match-p (regexp-quote "StyleBox[\"bold\", FontWeight->Bold]") cell))
    (should (string-match-p (regexp-quote "StyleBox[\"italic\", FontSlant->Italic]") cell))
    (should (string-match-p (regexp-quote "StyleBox[\"underlined\", FontVariations->{\"Underline\"->True}]") cell))
    (should (string-match-p (regexp-quote "StyleBox[\"code\", FontFamily->\"Courier\"]") cell))
    ;; the style names the stylesheet does not define are gone
    (should-not (string-match-p ", \"\\(?:Bold\\|Italic\\|Underlined\\|Courier\\)\"\\]" cell))))

(ert-deftest wolfram-nb-styles-test-formatting-survives-a-round-trip ()
  (let ((cell (wolfram-nb-styles--cell "A *bold*, /italic/, _underlined_ and =code= word.\n")))
    ;; read what was written, write it again: the same cell
    (with-temp-buffer
      (wolfram-nb-mode)
      (let ((file (make-temp-file "wolfram-nb-styles" nil ".nb")))
        (unwind-protect
            (progn
              (with-temp-file file (insert "Notebook[{\n" (substring-no-properties cell) "\n}]\n"))
              (let ((org (wolfram-nb--cells-to-org (wolfram-nb--parse-notebook file))))
                (should (string-match-p "A \\*bold\\*, /italic/, _underlined_ and =code= word\\." org))
                (setq wolfram-nb--box-sources nil)
                (should (equal (substring-no-properties (car (wolfram-nb--org-to-cells org)))
                               (substring-no-properties cell)))))
          (delete-file file))))))

(ert-deftest wolfram-nb-styles-test-earlier-style-names-are-still-read-and-upgraded ()
  (with-temp-buffer
    (wolfram-nb-mode)
    (let ((file (make-temp-file "wolfram-nb-styles" nil ".nb")))
      (unwind-protect
          (progn
            (with-temp-file file
              (insert "Notebook[{\nCell[TextData[{\"an \", StyleBox[\"old\", \"Bold\"], \" word\"}], \"Text\"]\n}]\n"))
            (let ((org (wolfram-nb--cells-to-org (wolfram-nb--parse-notebook file))))
              (should (string-match-p "an \\*old\\* word" org))
              (setq wolfram-nb--box-sources nil)
              (should (string-match-p (regexp-quote "StyleBox[\"old\", FontWeight->Bold]")
                                      (car (wolfram-nb--org-to-cells org))))))
        (delete-file file)))))

(defconst wolfram-nb-styles--coloured
  (concat "Notebook[{\nCell[TextData[{\"before \", "
          "StyleBox[\"red bold\", FontWeight->Bold, FontColor->RGBColor[1, 0, 0]], "
          "\" after\"}], \"Text\"]\n}]\n")
  "A notebook whose bold span is also red.")

(defun wolfram-nb-styles--edit (text from to)
  "Open the notebook TEXT, replace FROM by TO in its Org form, return the cell."
  (with-temp-buffer
    (wolfram-nb-mode)
    (let ((file (make-temp-file "wolfram-nb-styles" nil ".nb")))
      (unwind-protect
          (progn
            (with-temp-file file (insert text))
            (let* ((org (wolfram-nb--cells-to-org (wolfram-nb--parse-notebook file)))
                   (edited (replace-regexp-in-string (regexp-quote from) to org t t)))
              (setq wolfram-nb--box-sources nil)
              (substring-no-properties (car (wolfram-nb--org-to-cells edited)))))
        (delete-file file)))))

(ert-deftest wolfram-nb-styles-test-a-span-keeps-its-colour-while-its-text-is-not-edited ()
  (let ((cell (wolfram-nb-styles--edit wolfram-nb-styles--coloured "before" "changed")))
    (should (string-match-p "\"changed \"" cell))
    (should (string-match-p (regexp-quote "FontColor->RGBColor[1, 0, 0]") cell))))

(ert-deftest wolfram-nb-styles-test-editing-a-spans-text-keeps-its-formatting ()
  "The new text is still bold, though the colour of the old text is not kept."
  (let ((cell (wolfram-nb-styles--edit wolfram-nb-styles--coloured "red bold" "blue bold")))
    (should (string-match-p (regexp-quote "StyleBox[\"blue bold\", FontWeight->Bold]") cell))))

(defconst wolfram-nb-styles--sized
  (concat "Notebook[{\nCell[TextData[{\"one \", StyleBox[\"red\", FontColor->RGBColor[1, 0, 0]], "
          "\" two \", StyleBox[\"big\", FontSize->20], \" three\"}], \"Text\", "
          "ExpressionUUID->\"c-1\"]\n}]\n")
  "A notebook with two spans that Org cannot show: a colour and a size.")

(ert-deftest wolfram-nb-styles-test-colours-and-sizes-come-back-with-their-text ()
  "Editing words around a coloured span leaves the span coloured."
  (let ((cell (wolfram-nb-styles--edit wolfram-nb-styles--sized "one" "uno")))
    (should (string-match-p "TextData" cell))
    (should (string-match-p (regexp-quote "StyleBox[\"red\", FontColor->RGBColor[1, 0, 0]]") cell))
    (should (string-match-p (regexp-quote "StyleBox[\"big\", FontSize->20]") cell))
    (should (string-match-p "\"uno \"" cell))))

(ert-deftest wolfram-nb-styles-test-an-edited-span-does-not-hold-up-the-others ()
  (let ((cell (wolfram-nb-styles--edit wolfram-nb-styles--sized "red" "green")))
    (should-not (string-match-p "FontColor" cell))
    (should (string-match-p (regexp-quote "StyleBox[\"big\", FontSize->20]") cell))))

(ert-deftest wolfram-nb-styles-test-a-cell-with-only-unflagged-spans-stays-text-data ()
  (let ((cell (wolfram-nb-styles--edit wolfram-nb-styles--sized "two" "2")))
    (should (string-match-p "\\`Cell\\[TextData\\[{" cell))
    (should (string-match-p (regexp-quote "StyleBox[\"red\", FontColor->RGBColor[1, 0, 0]]") cell))))

(ert-deftest wolfram-nb-styles-test-a-span-is-not-put-back-inside-another-word ()
  "The red span `red' must not land in `Colored'."
  (let* ((text (concat "Notebook[{\nCell[TextData[{\"Colored \", "
                       "StyleBox[\"red\", FontColor->RGBColor[1, 0, 0]], "
                       "\" text.\"}], \"Text\", ExpressionUUID->\"c-2\"]\n}]\n"))
         (cell (wolfram-nb-styles--edit text "text." "words.")))
    (should (string-match-p (regexp-quote "\"Colored \", StyleBox[\"red\", FontColor->RGBColor[1, 0, 0]]")
                            cell))
    (should-not (string-match-p "\"Colo\"" cell))))

(provide 'test-styles)
;;; test-styles.el ends here
