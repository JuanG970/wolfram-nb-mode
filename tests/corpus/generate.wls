#!/usr/bin/env wolframscript
(* generate.wls

   Builds the synthetic notebook corpus used by tests/test-corpus.el.  The
   boxes come from the kernel (MakeBoxes/ToBoxes), so they have the shapes the
   Front End writes.  Every file gets the Front End's header and its trailing
   cache comment, which contains look-alikes of Cell[...].

   Run:  wolframscript -file generate.wls [output-directory]
   The output is deterministic for one Wolfram Language version. *)

SeedRandom[20261029]

outDir = If [Length[$ScriptCommandLine] > 1, $ScriptCommandLine[[2]], DirectoryName[$InputFileName]]

(* ---------------------------------------------------------------------- *)
(* File layout                                                             *)
(* ---------------------------------------------------------------------- *)

header =
    "(* Content-type: application/vnd.wolfram.mathematica *)\n\n" <>
    "(*** Wolfram Notebook File ***)\n" <>
    "(* http://www.wolfram.com/nb *)\n\n" <>
    "(* CreatedBy='Mathematica 14.0' *)\n\n" <>
    "(*CacheID: 234*)\n" <>
    "(* Internal cache information:\n" <>
    "NotebookFileLineBreakTest\n" <>
    "NotebookFileLineBreakTest\n" <>
    "NotebookDataPosition[       158,          7]\n" <>
    "NotebookDataLength[      9999,        300]\n" <>
    "NotebookOptionsPosition[      8888,        280]\n" <>
    "NotebookOutlinePosition[      9300,        297]\n" <>
    "CellTagsIndexPosition[      9257,        294]\n" <>
    "WindowFrame->Normal*)\n\n" <>
    "(* Beginning of Notebook Content *)\n"

(* The cache comment lists every cell as Cell[...] without content. *)
footer[n_Integer] :=
    "\n(* End of Notebook Content *)\n\n" <>
    "(* Internal cache information *)\n" <>
    "(*CellTagsOutline\n" <>
    "CellTagsIndex->{}\n" <>
    "*)\n" <>
    "(*CellTagsIndex\n" <>
    "CellTagsIndex->{}\n" <>
    "*)\n" <>
    "(*NotebookFileOutline\n" <>
    "Notebook[{\n" <>
    StringRiffle[
        Table["Cell[" <> ToString[100 + 10 i] <> ", 5, 40, 3, \"Text\",ExpressionUUID->\"" <> ToString[i] <> "-fake\"]", {i, n}],
        ",\n"
    ] <>
    "\n}\n]\n*)\n\n" <>
    "(* End of internal cache information *)\n"

manifest = {}

cellsOf[Cell[CellGroupData[l_List, ___], ___]] := Flatten[cellsOf /@ l]
cellsOf[c_Cell] := {c}
leafCount[nb_Notebook] := Length[Flatten[cellsOf /@ First[nb]]]

Options[writeNotebook] = {"RawUnicode" -> False, "Raw" -> {}}

writeNotebook[name_String, notebook_, OptionsPattern[]] :=
    Module[{tmp, text, stream, file = FileNameJoin[{outDir, name}], cells},
        tmp = FileNameJoin[{$TemporaryDirectory, "wnb-corpus-" <> ToString[RandomInteger[10^9]] <> ".nb"}];
        Put[notebook, tmp];
        text = Import[tmp, "Text"];
        DeleteFile[tmp];
        (* Cells whose text cannot be built as an expression without running it. *)
        Do[
            text = StringReplace[text, "\"@@" <> First[raw] <> "@@\"" -> Last[raw]],
            {raw, OptionValue["Raw"]}
        ];
        If [TrueQ[OptionValue["RawUnicode"]],
            text = StringReplace[text, {
                "\\:" ~~ h : (HexadecimalCharacter ~~ HexadecimalCharacter ~~ HexadecimalCharacter ~~ HexadecimalCharacter) :>
                    FromCharacterCode[FromDigits[h, 16]],
                "\\[" ~~ n : (LetterCharacter ~~ WordCharacter ...) ~~ "]" :>
                    With[{c = ToExpression["\"\\[" <> n <> "]\""]}, If [StringLength[c] === 1 && First[ToCharacterCode[c]] > 127, c, "\\[" <> n <> "]"]]
            }]
        ];
        cells = Length[Cases[notebook, _Cell, Infinity]];
        stream = OpenWrite[file, CharacterEncoding -> "UTF-8"];
        WriteString[stream, header <> text <> footer[cells]];
        Close[stream];
        AppendTo[manifest, StringRiffle[{name, ToString[leafCount[notebook]], ToString[Length[Rest[notebook]]]}, " "]];
        Print[name, ": ", FileByteCount[file], " bytes, ", leafCount[notebook], " cells, ", Length[Rest[notebook]], " options"]
    ]

(* ---------------------------------------------------------------------- *)
(* Cell builders                                                           *)
(* ---------------------------------------------------------------------- *)

SetAttributes[codeBoxes, HoldAll]
codeBoxes[expr_] := BoxData[MakeBoxes[expr, StandardForm]]

SetAttributes[inputCell, HoldFirst]
inputCell[expr_, opts___] := Cell[codeBoxes[expr], "Input", opts]

outputCell[expr_, opts___] := Cell[BoxData[ToBoxes[expr, StandardForm]], "Output", opts]

group[cells_List, state_ : Open] := Cell[CellGroupData[cells, state]]

uuid[n_Integer] := StringTemplate["`1`-aaaa-bbbb-cccc-dddddddd`2`"][IntegerString[n, 16, 8], IntegerString[n, 16, 4]]

(* Cells whose boxes would be evaluated if written as expressions are written as text. *)
rawCell[id_String, style_String, opts___] := Cell["@@" <> id <> "@@", style, opts]

mk[cells_List, extra___] := Notebook[cells, notebookOptions[extra]]

notebookOptions[extra___] :=
    Sequence[
        extra,
        WindowSize -> {808, 911},
        WindowMargins -> {{4, Automatic}, {Automatic, 0}},
        FrontEndVersion -> "14.0 for Linux x86 (64-bit) (December 12, 2023)",
        StyleDefinitions -> "Default.nb",
        ExpressionUUID -> "11111111-2222-3333-4444-555555555555"
    ]

(* ---------------------------------------------------------------------- *)
(* 1. structure.nb: every style, nesting, options                          *)
(* ---------------------------------------------------------------------- *)

structure =
    mk[
        {
            Cell["A Title", "Title", ExpressionUUID -> uuid[1]],
            Cell["A Subtitle", "Subtitle", ExpressionUUID -> uuid[2]],
            group[{
                Cell["First chapter", "Chapter", ExpressionUUID -> uuid[3]],
                Cell["Text under the chapter.", "Text", ExpressionUUID -> uuid[4]],
                group[{
                    Cell["A section", "Section", ExpressionUUID -> uuid[5]],
                    Cell["Text under the section.", "Text", ExpressionUUID -> uuid[6]],
                    group[{
                        Cell["A subsection", "Subsection", ExpressionUUID -> uuid[7]],
                        group[{
                            Cell["A subsubsection", "Subsubsection", ExpressionUUID -> uuid[8]],
                            Cell["Deep text.", "Text", ExpressionUUID -> uuid[9]],
                            inputCell[Plus[1, 2, 3], CellLabel -> "In[1]:=", ExpressionUUID -> uuid[10]],
                            outputCell[6, CellLabel -> "Out[1]=", ExpressionUUID -> uuid[11]]
                        }]
                    }, Closed]
                }]
            }],
            Cell["Bulleted items", "Subsection", ExpressionUUID -> uuid[12]],
            Cell["First item", "Item", ExpressionUUID -> uuid[13]],
            Cell["Second item", "Item", ExpressionUUID -> uuid[14]],
            Cell["A sub item", "Subitem", ExpressionUUID -> uuid[15]],
            Cell["A sub sub item", "Subsubitem", ExpressionUUID -> uuid[16]],
            Cell["Numbered one", "ItemNumbered", ExpressionUUID -> uuid[17]],
            Cell["Numbered two", "ItemNumbered", ExpressionUUID -> uuid[18]],
            Cell["Numbered sub", "SubitemNumbered", ExpressionUUID -> uuid[19]],
            Cell["Code style cell", "Code", ExpressionUUID -> uuid[20]],
            Cell["Print(\"hello\")", "Print", ExpressionUUID -> uuid[21]],
            Cell["Message text", "Message", "MSG", ExpressionUUID -> uuid[22]],
            Cell["Echo output", "Echo", ExpressionUUID -> uuid[23]],
            Cell["A custom style", "MyCustomStyle", ExpressionUUID -> uuid[24]],
            Cell[TextData["Item paragraph"], "ItemParagraph", ExpressionUUID -> uuid[25]]
        }
    ]

(* ---------------------------------------------------------------------- *)
(* 2. richtext.nb: TextData, links, inline cells, named characters         *)
(* ---------------------------------------------------------------------- *)

richtext =
    mk[
        {
            Cell["Rich text", "Section", ExpressionUUID -> uuid[101]],
            Cell[TextData[{"Some ", StyleBox["bold", FontWeight -> "Bold"], " and ", StyleBox["italic", "Italic"], " and ", StyleBox["underlined", "Underlined"], " and ", StyleBox["code", "Courier"], "."}], "Text", ExpressionUUID -> uuid[102]],
            Cell[TextData[{StyleBox["Bold start", "Bold"], " then plain, ending ", StyleBox["italic", "Italic"]}], "Text", ExpressionUUID -> uuid[103]],
            Cell[TextData[{StyleBox["Note: ", "Italic"], "the space is inside the styled text."}], "Text", ExpressionUUID -> uuid[104]],
            Cell[TextData[{"A link: ", ButtonBox["Wolfram", BaseStyle -> "Hyperlink", ButtonData -> {URL["https://www.wolfram.com"], None}, ButtonNote -> "https://www.wolfram.com"], " and more text."}], "Text", ExpressionUUID -> uuid[105]],
            Cell[TextData[{"Inline formula ", Cell[BoxData[FractionBox["a", "b"]], "InlineFormula"], " inside text."}], "Text", ExpressionUUID -> uuid[106]],
            Cell[TextData[{"Colored ", StyleBox["red", FontColor -> RGBColor[1, 0, 0]], " text."}], "Text", ExpressionUUID -> uuid[107]],
            Cell["Plain text with a named character \[Alpha] and a dash \[Dash] and a Greek \[CapitalOmega].", "Text", ExpressionUUID -> uuid[108]],
            Cell["Plain text with quotes \" and backslash \\ and a tab \t and a\nnewline.", "Text", ExpressionUUID -> uuid[109]],
            Cell["Two paragraphs\n\nseparated by a blank line.", "Text", ExpressionUUID -> uuid[110]],
            Cell["Lines that look like Org syntax:\n* not a headline\n- not a list\n1. not numbered\n#+not a keyword\n| not | a table |\n: not fixed width", "Text", ExpressionUUID -> uuid[111]],
            Cell["Literal markers in plain text: 5 * 3 * 2, a *star* here, /slashes/ there, _under_ and =equals= and ~tilde~.", "Text", ExpressionUUID -> uuid[112]],
            Cell["A plain link https://www.wolfram.com/mathematica and [[not a link]].", "Text", ExpressionUUID -> uuid[113]],
            Cell["", "Text", ExpressionUUID -> uuid[114]],
            Cell["   ", "Text", ExpressionUUID -> uuid[115]],
            Cell["  leading and trailing blanks  ", "Text", ExpressionUUID -> uuid[116]],
            Cell[StringRepeat["A very long line of text without any line break. ", 60], "Text", ExpressionUUID -> uuid[117]],
            Cell["Headline with \[Alpha] and trailing blank ", "Subsection", ExpressionUUID -> uuid[118]],
            Cell["- looks like a list", "Text", ExpressionUUID -> uuid[119]],
            Cell["Item with *literal* markers", "Item", ExpressionUUID -> uuid[120]],
            Cell[TextData[{"Item with a ", ButtonBox["link", BaseStyle -> "Hyperlink", ButtonData -> {URL["https://example.com"], None}]}], "Item", ExpressionUUID -> uuid[121]],
            Cell[TextData[{"Title with ", StyleBox["style", "Bold"]}], "Subsection", ExpressionUUID -> uuid[122]]
        }
    ]

(* ---------------------------------------------------------------------- *)
(* 3. code.nb: Input boxes that come from the kernel                       *)
(* ---------------------------------------------------------------------- *)

codeCellFrom[Hold[e_], {n_}] :=
    Cell[BoxData[MakeBoxes[e, StandardForm]], "Input", CellLabel -> "In[" <> ToString[n] <> "]:=", ExpressionUUID -> uuid[200 + n]]

SetAttributes[codeCells, HoldAll]
codeCells[exprs___] := MapIndexed[codeCellFrom, List @@ Map[Hold, Hold[exprs]]]

statements =
    BoxData[{
        MakeBoxes[x = 1;, StandardForm],
        "\n",
        MakeBoxes[y = x + 2;, StandardForm],
        "\n",
        MakeBoxes[Print[x, y], StandardForm]
    }]

code =
    mk[
        Join[
            {Cell["Code", "Section", ExpressionUUID -> uuid[199]]},
            codeCells[
                1 + 2,
                x^2 + 3 x + 1,
                (a + b)/(c - d),
                Sqrt[x^2 + y^2],
                Sin[x]^2 + Cos[x]^2,
                f[x_, y_] := x^y + y^x,
                Table[i^2, {i, 1, 10}],
                Sum[1/n^2, {n, 1, Infinity}],
                Integrate[Exp[-x^2], {x, -Infinity, Infinity}],
                D[x^n, x],
                {{1, 2}, {3, 4}} . {{5, 6}, {7, 8}},
                Plot[Sin[x], {x, 0, 2 Pi}, PlotStyle -> Red],
                If[a > 1, "yes", "no"],
                Module[{t = 1}, t++; t^2],
                Map[#^2 &, {1, 2, 3}],
                StringJoin["a", "b\nc", "d\"e", "f\\g"],
                x /. {x -> 1, y -> 2},
                a = b = 3,
                Subscript[a, 1] + Superscript[b, 2],
                Limit[Sin[x]/x, x -> 0],
                {1, 2, 3}[[2]],
                Function[{u, v}, u v][2, 3],
                a && b || ! c,
                x == y,
                x != y,
                x <= y,
                Rule[a, b],
                RuleDelayed[a, b],
                FullSimplify[Sin[x]^2 + Cos[x]^2],
                1.5*^-7 + 2.25,
                "A string with \[Alpha] and \:4e2d",
                Which[a < 0, -1, a == 0, 0, True, 1],
                Do[Print[i], {i, 3}],
                Row[{"a", 1}],
                Integrate[1/(1 + x^2), x],
                Product[k, {k, 1, 5}],
                -x^2,
                a - -b,
                a/b/c,
                f[g[h[x]]],
                Hold[1 + 1]
            ],
            {
                Cell[statements, "Input", ExpressionUUID -> uuid[300]],
                Cell["x^2 + y^2 (* a plain string input *)", "Input", ExpressionUUID -> uuid[301]],
                Cell["Plot[Sin[x], {x, 0, 6}]", "Code", ExpressionUUID -> uuid[302]],
                Cell[BoxData[RowBox[{"(*", " ", "a comment cell", " ", "*)"}]], "Input", ExpressionUUID -> uuid[303]],
                Cell[BoxData[TemplateBox[{"1", "\"m\"", "meters", "\"Meters\""}, "Quantity"]], "Input", ExpressionUUID -> uuid[304]]
            }
        ]
    ]

(* ---------------------------------------------------------------------- *)
(* 4. graphics.nb: outputs that must be kept as they are                   *)
(* ---------------------------------------------------------------------- *)

graphics =
    mk[
        {
            Cell["Graphics", "Section", ExpressionUUID -> uuid[401]],
            inputCell[Plot[Sin[x], {x, 0, 2 Pi}], ExpressionUUID -> uuid[402]],
            outputCell[Plot[Sin[x], {x, 0, 2 Pi}], ExpressionUUID -> uuid[403]],
            outputCell[ListPlot[Table[{i, i^2}, {i, 20}]], ExpressionUUID -> uuid[404]],
            outputCell[Plot3D[Sin[x y], {x, 0, 3}, {y, 0, 3}, PlotPoints -> 10, MaxRecursion -> 0], ExpressionUUID -> uuid[405]],
            outputCell[Graphics[{Red, Disk[], Blue, Rectangle[{1, 1}, {2, 2}], Line[{{0, 0}, {3, 3}}]}], ExpressionUUID -> uuid[406]],
            outputCell[Graphics3D[{Sphere[], Cuboid[{1, 1, 1}]}], ExpressionUUID -> uuid[407]],
            outputCell[Image[RandomReal[1, {12, 12, 3}]], ExpressionUUID -> uuid[408]],
            outputCell[BarChart[{1, 3, 2}], ExpressionUUID -> uuid[409]],
            outputCell[MatrixForm[{{1, 2}, {3, 4}}], ExpressionUUID -> uuid[410]],
            outputCell[Grid[{{"a", "b"}, {1, 2}}], ExpressionUUID -> uuid[411]],
            outputCell[Quantity[3, "Meters"], ExpressionUUID -> uuid[412]],
            outputCell[{1, 2, 3}, ExpressionUUID -> uuid[413]],
            outputCell[x^2/(y + 1), ExpressionUUID -> uuid[414]],
            outputCell[Style["styled", Red, Bold], ExpressionUUID -> uuid[415]],
            rawCell["dyn", "Output", ExpressionUUID -> uuid[416]],
            Cell[BoxData[GraphicsBox[{}, ImageSize -> 100, Method -> {"AxisPadding" -> Scaled[0.02], "DefaultMeshStyle" -> AbsolutePointSize[6]}]], "Output", ExpressionUUID -> uuid[417]],
            Cell[BoxData[GraphicsBox[RasterBox[RandomInteger[255, {8, 8}], {{0, 0}, {8, 8}}, {0, 255}], ImageSize -> 80]], "Output", ExpressionUUID -> uuid[418]],
            Cell["Text after graphics.", "Text", ExpressionUUID -> uuid[419]]
        }
    ]

dynamicBoxes = "BoxData[DynamicModuleBox[{Typeset`a$$ = 1}, SliderBox[Dynamic[Typeset`a$$], {0, 2}]]]"

(* A graphic well over the 50 KB threshold. *)
bigGraphics =
    mk[
        {
            Cell["Large graphics", "Section", ExpressionUUID -> uuid[501]],
            outputCell[ListLinePlot[Accumulate[RandomReal[{-1, 1}, 1200]]], ExpressionUUID -> uuid[502]],
            outputCell[Plot3D[Sin[3 x] Cos[2 y], {x, 0, 3}, {y, 0, 3}, PlotPoints -> 40, MaxRecursion -> 0], ExpressionUUID -> uuid[503]],
            Cell["End.", "Text", ExpressionUUID -> uuid[504]]
        }
    ]

(* ---------------------------------------------------------------------- *)
(* 5. options.nb: awkward cell and notebook options                        *)
(* ---------------------------------------------------------------------- *)

options =
    mk[
        {
            Cell["Options", "Section", ExpressionUUID -> uuid[601], CellTags -> {"intro", "top"}],
            Cell["Text with many options", "Text",
                CellChangeTimes -> {3.91234567891011*^9, 3.91234567891012*^9, 3.9123456789102*^9, 3.9123456789103*^9, 3.9123456789104*^9, 3.9123456789105*^9, 3.9123456789106*^9, 3.9123456789107*^9},
                CellTags -> {"one", "two"}, Background -> RGBColor[0.9, 0.9, 1], CellMargins -> {{20, 10}, {5, 5}},
                ExpressionUUID -> uuid[602]],
            Cell["Initialization", "Input", InitializationCell -> True, ExpressionUUID -> uuid[603]],
            Cell[BoxData[RowBox[{"x", "=", "1"}]], "Input", CellLabel -> "In[10]:=", CellTags -> {"tag, with comma", "quote\"inside"}, ExpressionUUID -> uuid[604]],
            Cell["A label with spaces", "Output", CellLabel -> "Out[10]= ", ExpressionUUID -> uuid[605]],
            Cell["Option with a string containing newline", "Text", TaggingRules -> {"Note" -> "line one\nline two", "List" -> {1, 2, 3}}, ExpressionUUID -> uuid[606]],
            Cell["Option with a nested list", "Text", CellFrameLabels -> {{None, "right"}, {"bottom", None}}, ExpressionUUID -> uuid[607]],
            Cell["Cell without any option", "Text"],
            Cell["Section with options", "Section", CellTags -> "sec", ExpressionUUID -> uuid[608]],
            Cell["Item with options", "Item", ExpressionUUID -> uuid[609], CellTags -> "it"]
        },
        TaggingRules -> {"WolframNBSession" -> "localhost:6061", "Other" -> {"a" -> 1}},
        Evaluator -> "Local",
        Visible -> True,
        DockedCells -> {Cell[TextData[{"Toolbar ", ButtonBox["Go", ButtonFunction :> Null, Appearance -> "Palette"]}], "DockedCell"]},
        InputAutoReplacements -> {"->" -> "\[Rule]"},
        TrackCellChangeTimes -> False
    ]

(* ---------------------------------------------------------------------- *)
(* 6. unicode.nb: raw UTF-8 and escaped characters                         *)
(* ---------------------------------------------------------------------- *)

unicode =
    mk[
        {
            Cell["Unicode \:4e2d\:6587 and Caf\[EAcute] and \[Pi] r\.b2", "Section", ExpressionUUID -> uuid[701]],
            Cell["Raw text: \:65e5\:672c\:8a9e, \[CapitalARing]ngstr\[ODoubleDot]m, \[Euro]5, \[Degree]C, \[RightArrow], \[Infinity].", "Text", ExpressionUUID -> uuid[702]],
            inputCell["h\[EAcute]llo" <> "w\[ODoubleDot]rld", ExpressionUUID -> uuid[703]],
            Cell[TextData[{"Mixed ", StyleBox["\[Alpha]\[Beta]\[Gamma]", "Bold"], " text."}], "Text", ExpressionUUID -> uuid[704]]
        }
    ]

(* ---------------------------------------------------------------------- *)
(* 7. edge.nb, empty.nb, optionsonly.nb                                    *)
(* ---------------------------------------------------------------------- *)

edge =
    Notebook[
        {
            Cell["Before group", "Text"],
            Cell[CellGroupData[{Cell["Only a heading", "Section"]}, Open]],
            Cell[CellGroupData[{Cell["Empty tail group", "Section"], Cell[CellGroupData[{}, Open]]}, Closed]],
            Cell["After groups", "Text"],
            Cell[BoxData[RowBox[{"1", "+", "1"}]], "Input"],
            Cell[BoxData["justastring"], "Input"],
            Cell[BoxData[RowBox[{"f", "[", "x", "]"}]], "Output", GeneratedCell -> True, CellAutoOverwrite -> True],
            Cell["Single char", "Text"],
            Cell["x", "Text"],
            Cell[BoxData[ToBoxes[Plot[x, {x, 0, 1}]]], "Output"]
        }
    ]

empty = Notebook[{}]
optionsOnly = Notebook[{}, WindowSize -> {500, 300}, FrontEndVersion -> "14.0 for Linux x86 (64-bit)", StyleDefinitions -> "Default.nb"]

(* ---------------------------------------------------------------------- *)
(* 8. eval-*.nb: notebooks that are evaluated by the tests                  *)
(* ---------------------------------------------------------------------- *)

evalState =
    Notebook[{
        Cell["Evaluation: state", "Title"],
        Cell["a = 5;", "Input"],
        Cell["a + 1", "Input"],
        Cell["f[x_] := x^2 + a", "Input"],
        Cell["f[3]", "Input"],
        Cell["%", "Input"],
        Cell["b = Range[5]", "Input"],
        Cell["Total[b]", "Input"],
        Cell["Print[\"printed\"]; 42", "Input"],
        Cell["StringJoin[\"w\[ODoubleDot]\", \"rld\"]", "Input"]
    }]

evalGraphics =
    Notebook[{
        Cell["Evaluation: graphics", "Title"],
        Cell["Plot[Sin[x], {x, 0, 2 Pi}]", "Input"],
        Cell["x = 3", "Input"],
        Cell["Graphics3D[Sphere[]]", "Input"],
        Cell["Image[RandomReal[1, {6, 6}]]", "Input"],
        Cell["Plot[x t, {t, 0, 1}]", "Input"],
        Cell["Table[i^2, {i, 4}]", "Input"]
    }]

evalErrors =
    Notebook[{
        Cell["Evaluation: errors", "Title"],
        Cell["ok = 1", "Input"],
        Cell["Sin[1, 2]", "Input"],
        Cell["1 +", "Input"],
        Cell["1/0", "Input"],
        Cell["ok + 1", "Input"]
    }]

(* ---------------------------------------------------------------------- *)
(* Write everything                                                        *)
(* ---------------------------------------------------------------------- *)

If [!DirectoryQ[outDir], CreateDirectory[outDir]]

writeNotebook["structure.nb", structure]
writeNotebook["richtext.nb", richtext]
writeNotebook["code.nb", code]
writeNotebook["graphics.nb", graphics, "Raw" -> {{"dyn", dynamicBoxes}}]
writeNotebook["graphics-large.nb", bigGraphics]
writeNotebook["options.nb", options]
writeNotebook["unicode.nb", unicode]
writeNotebook["unicode-raw.nb", unicode, "RawUnicode" -> True]
writeNotebook["edge.nb", edge]
writeNotebook["empty.nb", empty]
writeNotebook["options-only.nb", optionsOnly]
writeNotebook["eval-state.nb", evalState]
writeNotebook["eval-graphics.nb", evalGraphics]
writeNotebook["eval-errors.nb", evalErrors]

(* name, number of cells (groups unwrapped), number of notebook options *)
Export[FileNameJoin[{outDir, "manifest.txt"}], StringRiffle[manifest, "\n"] <> "\n", "Text"]
