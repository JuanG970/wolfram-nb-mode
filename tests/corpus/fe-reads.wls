(* Ask the Front End what it sees in a notebook and in the copy Emacs saved.

     wolframscript -file fe-reads.wls ORIGINAL SAVED [EVALUATED]

   Needs a Front End (Wolfram Engine ships a headless one).  Not part of
   test-all.sh, which has no Front End to rely on; run it by hand.  Prints
   whether the Front End reads ORIGINAL and SAVED as the same cells and the
   same cell groups, and, for EVALUATED, how an evaluated notebook is
   structured.  Run `ps` afterwards: a hard-killed Front End leaves a kernel. *)
args = Rest[$ScriptCommandLine];
cellsOf[nb_] := First[NotebookGet[nb]]
shape[Cell[CellGroupData[l_List, st___], ___]] := {"G", st, shape /@ l}
shape[Cell[_, s_String, ___]] := s
shape[_] := "?"
UsingFrontEnd[
  a = NotebookOpen[args[[1]], Visible -> False];
  b = NotebookOpen[args[[2]], Visible -> False];
  ca = cellsOf[a]; cb = cellsOf[b];
  Print["same cells: ", ca === cb];
  Print["same groups: ", shape /@ ca === shape /@ cb];
  If [ca =!= cb,
    Do[If [ca[[i]] =!= cb[[i]],
        Print["differs at ", i, ": ", InputForm[ca[[i]]], "\n   vs ", InputForm[cb[[i]]]]],
      {i, Min[Length[ca], Length[cb]]}]];
  NotebookClose[a]; NotebookClose[b];
  If [Length[args] >= 3,
    c = NotebookOpen[args[[3]], Visible -> False];
    Print["structure: ", shape /@ cellsOf[c]];
    NotebookClose[c]]];
