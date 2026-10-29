(* compare.wl

   Used by tests/test-corpus.el.  WolframNBCompare`compare[original, saved]
   loads two notebook files as Wolfram expressions and describes how they
   differ, as a string of key=value pairs.  Nothing but counts is reported. *)

BeginPackage["WolframNBCompare`"]

compare::usage = "compare[original, saved] describes how two notebook files differ."

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
                "nbopts=" <> ToString[Rest[o] === Rest[s]],
                "gfx=" <> ratio[Count[g, i_ /; fo[[i]] === fs[[i]]], Length[g]],
                "text=" <> ratio[Count[t, i_ /; textOf[fo[[i]]] === textOf[fs[[i]]]], Length[t]],
                "code=" <> ratio[Count[c, i_ /; codeOf[fo[[i]]] === codeOf[fs[[i]]] && codeOf[fo[[i]]] =!= $Failed], Length[c]],
                "opts=" <> ratio[Count[op, i_ /; Drop[List @@ fo[[i]], 2] === Drop[List @@ fs[[i]], 2]], Length[op]]
            },
            ";"
        ]
    ]

End[]

EndPackage[]
