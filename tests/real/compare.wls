(* Judge the copies roundtrip.el wrote.

     wolframscript -file real/compare.wls LIST OUTDIR

   For each notebook of LIST that has a copy in OUTDIR, prints a line
   `NNNN kind key=value;...` with the result of WolframNBCompare`compare, for
   the unedited copy (kind U) and the forced-edit copy (kind E). *)
Get[FileNameJoin[{DirectoryName[$InputFileName], "..", "corpus", "compare.wl"}]];
args = Rest[$ScriptCommandLine];
files = Select[StringSplit[Import[args[[1]], "Text"], "\n"], # =!= "" &];
outDir = args[[2]];
Do[
  Do[
    With[{saved = FileNameJoin[{outDir, StringPadLeft[ToString[i], 4, "0"] <> If[kind === "E", "-e", ""] <> ".nb"}]},
      If [FileExistsQ[saved],
        Print[StringPadLeft[ToString[i], 4, "0"], " ", kind, " ",
          TimeConstrained[WolframNBCompare`compare[files[[i]], saved], 300, "TIMEOUT"]]]],
    {kind, {"U", "E"}}],
  {i, Length[files]}]
