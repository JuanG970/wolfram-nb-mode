(* compare.wl

   Used by tests/test-corpus.el.  WolframNBCompare`compare[original, saved]
   loads two notebook files as Wolfram expressions and describes how they
   differ, as a string of key=value pairs.  Nothing but counts is reported. *)

BeginPackage["WolframNBCompare`"]

compare::usage = "compare[original, saved] describes how two notebook files differ."
wordsDiffer::usage = "wordsDiffer[original, saved] returns the number of cells whose words differ."

Begin["`Private`"]

cellsOf[Cell[CellGroupData[l_List, ___], ___]] := Flatten[cellsOf /@ l]
cellsOf[c_Cell] := {c}
flatCells[nb_] := Flatten[cellsOf /@ First[nb]]

styleOf[Cell[_, s_String, ___]] := s
styleOf[_] := None

optionlessStyleQ[s_] :=
    MemberQ[{"Title", "Subtitle", "Item", "Subitem", "Subsubitem", "ItemNumbered", "SubitemNumbered", "SubsubitemNumbered"}, s]

graphicalQ[Cell[c_, ___]] :=
    !FreeQ[c, GraphicsBox | Graphics3DBox | RasterBox | DynamicModuleBox | TemplateBox]

textLikeQ[c_Cell] :=
    !graphicalQ[c] && MemberQ[{"Title", "Subtitle", "Chapter", "Section", "Subsection", "Subsubsection", "Text", "Item", "Subitem", "Subsubitem", "ItemNumbered", "SubitemNumbered", "ItemParagraph", "Quote"}, styleOf[c]]

(* The words of a text cell, without styling or whitespace. *)
textOf[Cell[c_String, ___]] := StringReplace[c, WhitespaceCharacter .. -> ""]
textOf[Cell[c_, ___]] :=
    StringReplace[
        StringJoin[
            Cases[c /. StyleBox[x_, ___] :> x /. ButtonBox[x_, ___] :> x /. TooltipBox[x_, ___] :> x, _String, Infinity]
        ],
        WhitespaceCharacter .. -> ""
    ]

normalizeHold[h_Hold] := DeleteCases[h, Null, {1}]

codeQ[c_Cell] := MatchQ[styleOf[c], "Input" | "Code"] && !graphicalQ[c]
codeOf[Cell[b_BoxData, ___]] := normalizeHold @ Quiet @ ToExpression[b, StandardForm, Hold]
codeOf[Cell[s_String, ___]] := normalizeHold @ Quiet @ ToExpression[s, InputForm, Hold]
codeOf[_] := $Failed

(* Code that does not parse (a cell that shows broken code on purpose) cannot be
   compared as an expression; it is the same when the cell is the same. *)
sameCode[a_, b_] :=
    With[{ca = codeOf[a], cb = codeOf[b]},
        If [ca === $Failed, a === b, ca === cb]]

(* The nesting of cell groups, with each group's Open/Closed state, and the
   styles of the cells: what the cell brackets of the Front End show.  A group
   with no cell shows nothing, so it is left out. *)
shape[Cell[CellGroupData[l_List, state___], ___]] :=
    With[{inner = shape /@ l}, If [inner === {}, Nothing, {"Group", state, inner}]]
shape[Cell[_, s_String, ___]] := s
shape[_] := "?"
shapeOf[nb_] := shape /@ First[nb]

(* The formatting of a text cell as the Front End shows it: its text, with the
   flags (bold, italic, underline, code) of the spans around each piece.  A
   style name the stylesheet does not define shows nothing, but is counted as
   what it was meant to be, since earlier versions wrote those. *)
flagOf[Bold | "Bold" | (FontWeight -> (Bold | "Bold" | "SemiBold"))] := "b"
flagOf[Italic | "Italic" | (FontSlant -> (Italic | "Italic" | "Oblique"))] := "i"
flagOf[Underlined | "Underlined"] := "u"
flagOf[FontVariations -> v_] /; !FreeQ[v, "Underline" -> True] := "u"
flagOf[FontFamily -> ("Courier" | "Courier New" | "Courier Std")] := "c"
flagOf["Courier"] := "c"
flagOf[_] := Nothing

spanFlags[opts_List] := Union @ Flatten @ Map[flagOf, Flatten[opts]]

pieces[c_String, flags_] := {{StringReplace[c, WhitespaceCharacter .. -> ""], flags}}
pieces[c_List, flags_] := Flatten[pieces[#, flags] & /@ c, 1]
pieces[StyleBox[x_, opts___], flags_] := pieces[x, Union[flags, spanFlags[{opts}]]]
pieces[(ButtonBox | TooltipBox)[x_, ___], flags_] := pieces[x, flags]
pieces[_, _] := {}

mergePieces[l_List] :=
    Map[{StringJoin[#[[All, 1]]], #[[1, 2]]} &, Split[DeleteCases[l, {"", _}], #1[[2]] === #2[[2]] &]]

styledOf[Cell[TextData[t_], ___]] := mergePieces[pieces[t, {}]]
styledOf[Cell[s_String, ___]] := mergePieces[pieces[s, {}]]
styledOf[_] := $Failed

ratio[n_, total_] := ToString[n] <> "/" <> ToString[total]

compare[original_String, saved_String] :=
    Quiet @ Module[{o = Get[original], s = Get[saved], fo, fs, n, g, t, c, op},
        fo = flatCells[o];
        fs = flatCells[s];
        n = Min[Length[fo], Length[fs]];
        g = Select[Range[n], graphicalQ[fo[[#]]] &];
        t = Select[Range[n], textLikeQ[fo[[#]]] &];
        c = Select[Range[n], codeQ[fo[[#]]] &];
        op = Select[Range[n], !graphicalQ[fo[[#]]] && !optionlessStyleQ[styleOf[fo[[#]]]] &];
        StringRiffle[
            {
                "cells=" <> ratio[Length[fs], Length[fo]],
                "exact=" <> ToString[fo === fs],
                "styles=" <> ToString[styleOf /@ fo === styleOf /@ fs],
                "groups=" <> ToString[shapeOf[o] === shapeOf[s]],
                "nbopts=" <> ToString[Rest[o] === Rest[s]],
                "gfx=" <> ratio[Count[g, i_ /; fo[[i]] === fs[[i]]], Length[g]],
                "text=" <> ratio[Count[t, i_ /; textOf[fo[[i]]] === textOf[fs[[i]]]], Length[t]],
                "styled=" <> ratio[Count[t, i_ /; styledOf[fo[[i]]] === styledOf[fs[[i]]]], Length[t]],
                "code=" <> ratio[Count[c, i_ /; sameCode[fo[[i]], fs[[i]]]], Length[c]],
                "opts=" <> ratio[Count[op, i_ /; Drop[List @@ fo[[i]], 2] === Drop[List @@ fs[[i]], 2]], Length[op]]
            },
            ";"
        ]
    ]

(* The words of a cell, ignoring styles, options and the characters used for markup. *)
words[Cell[c_String, ___]] := strip[c]
words[Cell[c_, ___]] :=
    strip[StringJoin[Cases[c //. {StyleBox[x_, ___] :> x, ButtonBox[x_, ___] :> x}, _String, Infinity]]]
strip[s_String] :=
    StringReplace[s, (WhitespaceCharacter | "*" | "/" | "_" | "=" | "~" | "+" | FromCharacterCode[8203]) .. -> ""]

wordsDiffer[original_String, saved_String] :=
    Quiet @ Module[{fo = flatCells[Get[original]], fs = flatCells[Get[saved]]},
        If [Length[fo] =!= Length[fs] || styleOf /@ fo =!= styleOf /@ fs,
            -1
            ,
            Count[Range[Length[fo]], i_ /; words[fo[[i]]] =!= words[fs[[i]]]]
        ]
    ]

End[]

EndPackage[]
