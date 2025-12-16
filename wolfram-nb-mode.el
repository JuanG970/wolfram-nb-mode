;;; wolfram-nb-mode.el --- Edit Wolfram Notebook files as Org-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Juan Gonzalez

;; Author: Juan Gonzalez <juan.angel19@hotmail.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "26.1"))
;; Keywords: wolfram, mathematica, notebook, org
;; URL: https://github.com/juang970/wolfram-nb-mode

;; This file is not part of GNU Emacs.

;;; Commentary:

;; wolfram-nb-mode provides an Emacs interface for editing Wolfram Language
;; Notebook (.nb) files. It translates the Cell[...] structure of notebooks
;; into an org-mode-like buffer for easier editing, while maintaining the
;; backend Cell structure for proper serialization.
;;
;; Features:
;; - Parse Notebook[{...}] files into org-mode structure
;; - Edit sections, subsections, text, and code cells
;; - Maintain bidirectional mapping between org and Cell structures
;; - Save changes back to .nb format
;;
;; Usage:
;;   M-x wolfram-nb-mode RET to enable in a .nb file
;;   C-c C-c to reparse current buffer
;;   C-x C-s to save changes back to .nb format
;;
;; Supported cell types:
;; - Section, Subsection, Subsubsection -> Org headlines
;; - Text -> Org paragraphs
;; - Item -> Org list items
;; - Code/Input -> Org source blocks
;;
;; Note: This mode is designed for static documents. Dynamic content
;; (Dynamic[], Manipulate[], etc.) is preserved as code but not rendered.

;;; Code:

(require 'org)
(require 'org-element)

(defgroup wolfram-nb nil
  "Edit Wolfram Notebook files in Emacs."
  :group 'languages
  :prefix "wolfram-nb-")

(defcustom wolfram-nb-indent-level 2
  "Indentation level for nested structures."
  :type 'integer
  :group 'wolfram-nb)

(defcustom wolfram-nb-auto-save t
  "Whether to automatically parse on opening .nb files."
  :type 'boolean
  :group 'wolfram-nb)

;;; Data Structures

(defvar-local wolfram-nb--cells nil
  "List of parsed cell structures from the original notebook.
Each element is a plist with :type, :content, :style, :position.")

(defvar-local wolfram-nb--original-file nil
  "Original .nb file path.")

(defvar-local wolfram-nb--modified nil
  "Whether the notebook has been modified.")

;;; Parsing Functions

(defun wolfram-nb--unescape-string (str)
  "Unescape a Mathematica string STR.
Handles \\\\, \\\", and \\n."
  (with-temp-buffer
    (insert str)
    (goto-char (point-min))
    (let ((result "")
          (i 0)
          (len (length str)))
      (while (< i len)
        (if (and (< i (1- len))
                 (= (aref str i) ?\\))
            (let ((next-char (aref str (1+ i))))
              (cond
               ((= next-char ?n)
                (setq result (concat result "\n"))
                (setq i (+ i 2)))
               ((= next-char ?\")
                (setq result (concat result "\""))
                (setq i (+ i 2)))
               ((= next-char ?\\)
                (setq result (concat result "\\"))
                (setq i (+ i 2)))
               (t
                (setq result (concat result (string (aref str i))))
                (setq i (1+ i)))))
          (setq result (concat result (string (aref str i))))
          (setq i (1+ i))))
      result)))

(defun wolfram-nb--escape-string (str)
  "Escape STR for inclusion in a Mathematica string literal."
  (let ((result ""))
    (dotimes (i (length str))
      (let ((char (aref str i)))
        (cond
         ((= char ?\\)
          (setq result (concat result "\\\\")))
         ((= char ?\")
          (setq result (concat result "\\\"")))
         ((= char ?\n)
          (setq result (concat result "\\n")))
         (t
          (setq result (concat result (string char)))))))
    result))

(defun wolfram-nb--parse-cell (cell-string)
  "Parse a single Cell[...] structure from CELL-STRING.
Returns a plist with :content and :style."
  (when (string-match "^Cell\\[\"\\(\\(?:[^\"\\\\]\\|\\\\.\\)*\\)\",[ \t]*\"\\([^\"]+\\)\"\\]" cell-string)
    (let* ((content-raw (match-string 1 cell-string))
           (style (match-string 2 cell-string))
           (content (wolfram-nb--unescape-string content-raw)))
      (list :content content :style style))))

(defun wolfram-nb--find-cell-end (start)
  "Find the end position of a Cell[...] starting at START.
Returns the position after the closing bracket."
  (save-excursion
    (goto-char start)
    (when (looking-at "Cell\\[")
      (goto-char (match-end 0))
      (let ((depth 1)
            (in-string nil)
            (escape-next nil))
        (while (and (> depth 0) (not (eobp)))
          (let ((char (char-after)))
            (cond
             (escape-next
              (setq escape-next nil))
             ((and (= char ?\\) in-string)
              (setq escape-next t))
             ((= char ?\")
              (setq in-string (not in-string)))
             ((and (not in-string) (= char ?\[))
              (setq depth (1+ depth)))
             ((and (not in-string) (= char ?\]))
              (setq depth (1- depth)))))
          (forward-char))
        (point)))))

(defun wolfram-nb--parse-notebook (file)
  "Parse a Wolfram Notebook FILE and return a list of cell structures."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    ;; Find the Notebook[{...}] structure
    (if (re-search-forward "Notebook\\[{" nil t)
        (let ((cells '()))
          ;; Parse individual cells
          (while (re-search-forward "Cell\\[" nil t)
            (goto-char (match-beginning 0))
            (let* ((cell-start (point))
                   (cell-end (wolfram-nb--find-cell-end cell-start)))
              (when cell-end
                (let* ((cell-str (buffer-substring-no-properties cell-start cell-end))
                       (parsed (wolfram-nb--parse-cell cell-str)))
                  (when parsed
                    (push parsed cells)))
                (goto-char cell-end))))
          (nreverse cells))
      (error "Not a valid Notebook file"))))

;;; Conversion Functions

(defun wolfram-nb--cell-to-org (cell)
  "Convert a CELL plist to org-mode text."
  (let ((content (plist-get cell :content))
        (style (plist-get cell :style)))
    (pcase style
      ("Section" (format "* %s\n" content))
      ("Subsection" (format "** %s\n" content))
      ("Subsubsection" (format "*** %s\n" content))
      ("Text" (format "%s\n\n" content))
      ("Item" 
       ;; Remove leading bullet if present
       (let ((text (replace-regexp-in-string "^[•●◦-][ \t]*" "" content)))
         (format "- %s\n" text)))
      ((or "Code" "Input")
       (format "#+begin_src wolfram\n%s\n#+end_src\n\n" content))
      ("Output"
       (format "#+begin_example\n%s\n#+end_example\n\n" content))
      (_ 
       ;; Unknown cell type - preserve as comment
       (format "# Cell[%S, %S]\n\n" content style)))))

(defun wolfram-nb--cells-to-org (cells)
  "Convert a list of CELLS to org-mode text."
  (mapconcat #'wolfram-nb--cell-to-org cells ""))

;;; Org to Cell Conversion

(defun wolfram-nb--make-cell (content style)
  "Create a Cell[...] string with CONTENT and STYLE."
  (format "Cell[\"%s\", \"%s\"]"
          (wolfram-nb--escape-string (string-trim content))
          style))

(defun wolfram-nb--org-to-cells (org-text)
  "Parse ORG-TEXT and convert to a list of Cell structures."
  (with-temp-buffer
    (insert org-text)
    (org-mode)
    (let ((tree (org-element-parse-buffer))
          (cells '()))
      (org-element-map tree '(headline paragraph plain-list src-block example-block)
        (lambda (element)
          (pcase (org-element-type element)
            ('headline
             (let* ((level (org-element-property :level element))
                    (title (org-element-property :title element))
                    (title-text (org-element-interpret-data title))
                    (style (pcase level
                            (1 "Section")
                            (2 "Subsection")
                            (_ "Subsubsection"))))
               (push (wolfram-nb--make-cell title-text style) cells)))
            
            ('paragraph
             ;; Check if inside a list item
             (let ((parent (org-element-property :parent element)))
               (unless (eq (org-element-type parent) 'item)
                 (let ((text (org-element-interpret-data element)))
                   (when (not (string-blank-p text))
                     (push (wolfram-nb--make-cell text "Text") cells))))))
            
            ('plain-list
             ;; Process items
             (org-element-map element 'item
               (lambda (item)
                 (let* ((contents (org-element-contents item))
                        (text (string-trim
                               (mapconcat
                                (lambda (el)
                                  (if (stringp el)
                                      el
                                    (org-element-interpret-data el)))
                                contents ""))))
                   (when (not (string-blank-p text))
                     (push (wolfram-nb--make-cell text "Item") cells))))))
            
            ('src-block
             (let* ((lang (org-element-property :language element))
                    (value (org-element-property :value element)))
               (push (wolfram-nb--make-cell value "Code") cells)))
            
            ('example-block
             (let ((value (org-element-property :value element)))
               (push (wolfram-nb--make-cell value "Output") cells))))))
      (nreverse cells))))

(defun wolfram-nb--cells-to-notebook (cells)
  "Convert a list of CELLS to a Notebook[{...}] string."
  (let ((cells-str (string-join cells ",\n")))
    (format "Notebook[{\n%s\n}]\n" cells-str)))

;;; Interactive Commands

;;;###autoload
(defun wolfram-nb-open (file)
  "Open a Wolfram Notebook FILE in org-mode representation."
  (interactive "fOpen Wolfram Notebook: ")
  (let ((cells (wolfram-nb--parse-notebook file))
        (org-text-buffer (generate-new-buffer 
                          (format "*wolfram-nb: %s*" 
                                  (file-name-nondirectory file)))))
    (with-current-buffer org-text-buffer
      (wolfram-nb-mode)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (wolfram-nb--cells-to-org cells))
        (goto-char (point-min))
        (set-buffer-modified-p nil))
      (setq wolfram-nb--cells cells
            wolfram-nb--original-file file
            wolfram-nb--modified nil))
    (switch-to-buffer org-text-buffer)))

(defun wolfram-nb-save ()
  "Save the current org-mode buffer back to .nb format."
  (interactive)
  (unless wolfram-nb--original-file
    (error "No associated .nb file"))
  (let* ((org-text (buffer-substring-no-properties (point-min) (point-max)))
         (cells (wolfram-nb--org-to-cells org-text))
         (notebook-text (wolfram-nb--cells-to-notebook cells)))
    (with-temp-file wolfram-nb--original-file
      (insert notebook-text))
    (setq wolfram-nb--cells cells
          wolfram-nb--modified nil)
    (set-buffer-modified-p nil)
    (message "Saved to %s" wolfram-nb--original-file)))

(defun wolfram-nb-reparse ()
  "Reparse the current buffer to update cell mappings."
  (interactive)
  (let* ((org-text (buffer-substring-no-properties (point-min) (point-max)))
         (cells (wolfram-nb--org-to-cells org-text)))
    (setq wolfram-nb--cells cells
          wolfram-nb--modified t)
    (message "Reparsed %d cells" (length cells))))

(defun wolfram-nb-view-cells ()
  "View the raw Cell structures for the current buffer."
  (interactive)
  (unless wolfram-nb--cells
    (wolfram-nb-reparse))
  (let ((buf (get-buffer-create "*Wolfram NB Cells*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (wolfram-nb--cells-to-notebook wolfram-nb--cells))
        (goto-char (point-min)))
      (special-mode))
    (display-buffer buf)))

;;;###autoload
(defun wolfram-nb-create-new (file)
  "Create a new Wolfram Notebook FILE."
  (interactive "FCreate Wolfram Notebook: ")
  (let ((buf (generate-new-buffer
              (format "*wolfram-nb: %s*"
                      (file-name-nondirectory file)))))
    (with-current-buffer buf
      (wolfram-nb-mode)
      (setq wolfram-nb--original-file file
            wolfram-nb--cells '()
            wolfram-nb--modified nil)
      (insert "* New Notebook\n\n")
      (insert "Welcome to wolfram-nb-mode!\n\n")
      (insert "Edit this buffer as org-mode, then save with C-x C-s.\n\n")
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Mode Definition

(defvar wolfram-nb-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") 'wolfram-nb-reparse)
    (define-key map (kbd "C-c C-v") 'wolfram-nb-view-cells)
    (define-key map (kbd "C-x C-s") 'wolfram-nb-save)
    map)
  "Keymap for `wolfram-nb-mode'.")

;;;###autoload
(define-derived-mode wolfram-nb-mode org-mode "Wolfram-NB"
  "Major mode for editing Wolfram Notebook files as Org-mode.

This mode parses .nb files into an org-mode representation while
maintaining the underlying Cell[...] structure. Changes are saved
back to proper Notebook format.

\\{wolfram-nb-mode-map}"
  (setq-local write-contents-functions '(wolfram-nb-save))
  (message "Wolfram Notebook mode enabled. Save with C-x C-s"))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.nb\\'" . wolfram-nb-open-auto))

(defun wolfram-nb-open-auto ()
  "Automatically open .nb files with wolfram-nb-mode."
  (when wolfram-nb-auto-save
    (let ((file (buffer-file-name)))
      (when file
        (wolfram-nb-open file)
        (kill-buffer (current-buffer))))))

(provide 'wolfram-nb-mode)
;;; wolfram-nb-mode.el ends here
