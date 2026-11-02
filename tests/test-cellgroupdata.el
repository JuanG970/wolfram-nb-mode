;;; test-cellgroupdata.el --- CellGroupData tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Test CellGroupData unwrapping with proper ERT framework.

;;; Code:

(require 'ert)
(add-to-list 'load-path
             (file-name-directory
              (directory-file-name
               (file-name-directory (or load-file-name buffer-file-name default-directory)))))
(require 'wolfram-nb-mode)

(ert-deftest wolfram-nb-test-cgd-simple-group ()
  "Extract cells from a simple CellGroupData."
  (let ((cells (wolfram-nb--extract-cells-from-group
                "Cell[CellGroupData[{Cell[\"Heading\", \"Section\"],Cell[\"Body\", \"Text\"]}]]")))
    (should (= (length cells) 2))
    (should (string= (wolfram-nb-cell-style (nth 0 cells)) "Section"))
    (should (string= (wolfram-nb-cell-content (nth 0 cells)) "Heading"))
    (should (string= (wolfram-nb-cell-style (nth 1 cells)) "Text"))))

(ert-deftest wolfram-nb-test-cgd-nested ()
  (let ((cells (wolfram-nb--extract-cells-from-group
                (concat "Cell[CellGroupData[{"
                        "Cell[\"Outer\", \"Section\"],"
                        "Cell[CellGroupData[{"
                        "Cell[\"Inner\", \"Subsection\"],"
                        "Cell[\"Deep\", \"Text\"]"
                        "}]]"
                        "}]]"))))
    (should (= (length cells) 3))
    (should (string= (wolfram-nb-cell-content (nth 0 cells)) "Outer"))
    (should (string= (wolfram-nb-cell-content (nth 1 cells)) "Inner"))
    (should (string= (wolfram-nb-cell-content (nth 2 cells)) "Deep"))))

(ert-deftest wolfram-nb-test-cgd-code ()
  (let ((cells (wolfram-nb--extract-cells-from-group
                (concat "Cell[CellGroupData[{"
                        "Cell[\"Demo\", \"Section\"],"
                        "Cell[\"x = 5\", \"Input\"],"
                        "Cell[\"5\", \"Output\"]"
                        "}]]"))))
    (should (= (length cells) 3))
    (should (string= (wolfram-nb-cell-style (nth 1 cells)) "Input"))
    (should (string= (wolfram-nb-cell-style (nth 2 cells)) "Output"))))

(ert-deftest wolfram-nb-test-cgd-notebook-parse ()
  "CellGroupData is unwrapped at notebook level."
  (let ((f (make-temp-file "wolfram-nb-cgd" nil ".nb")))
    (with-temp-file f
      (insert "Notebook[{\n"
              "Cell[CellGroupData[{"
              "Cell[\"Title\", \"Title\"],"
              "Cell[\"Body\", \"Text\"]"
              "}]],\n"
              "Cell[CellGroupData[{"
              "Cell[\"Sec\", \"Section\"],"
              "Cell[\"Code\", \"Input\"]"
              "}]]\n"
              "}]\n"))
    (unwind-protect
        (let ((cells (wolfram-nb--parse-notebook f)))
          (should (= (length cells) 4))
          (should (string= (wolfram-nb-cell-style (nth 0 cells)) "Title"))
          (should (string= (wolfram-nb-cell-style (nth 1 cells)) "Text"))
          (should (string= (wolfram-nb-cell-style (nth 2 cells)) "Section"))
          (should (string= (wolfram-nb-cell-style (nth 3 cells)) "Input")))
      (delete-file f))))

(ert-deftest wolfram-nb-test-cgd-empty ()
  (should (= (length (wolfram-nb--extract-cells-from-group
                       "Cell[CellGroupData[{}]]")) 0)))

(ert-deftest wolfram-nb-test-cgd-escaped-strings ()
  (let ((cells (wolfram-nb--extract-cells-from-group
                (concat "Cell[CellGroupData[{"
                        "Cell[\"Hello\\nWorld\", \"Text\"],"
                        "Cell[\"Quote: \\\"test\\\"\", \"Text\"]"
                        "}]]"))))
    (should (= (length cells) 2))
    (should (string= (wolfram-nb-cell-content (nth 0 cells)) "Hello\nWorld"))
    (should (string= (wolfram-nb-cell-content (nth 1 cells)) "Quote: \"test\""))))

(ert-deftest wolfram-nb-test-cgd-deeply-nested ()
  "Three levels of nesting."
  (let ((cells (wolfram-nb--extract-cells-from-group
                (concat "Cell[CellGroupData[{"
                        "Cell[\"L1\", \"Chapter\"],"
                        "Cell[CellGroupData[{"
                        "Cell[\"L2\", \"Section\"],"
                        "Cell[CellGroupData[{"
                        "Cell[\"L3\", \"Subsection\"],"
                        "Cell[\"Bottom\", \"Text\"]"
                        "}]]"
                        "}]]"
                        "}]]"))))
    (should (= (length cells) 4))
    (should (string= (wolfram-nb-cell-content (nth 0 cells)) "L1"))
    (should (string= (wolfram-nb-cell-content (nth 3 cells)) "Bottom"))))

(provide 'test-cellgroupdata)
;;; test-cellgroupdata.el ends here
