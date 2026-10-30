(* wolfram-nb-kernel-boot.wl

   Kernel-side evaluation loop for wolfram-nb-mode.

   Emacs starts `WolframKernel -noprompt' and sends this file as the first
   input line.  The loop then reads one request per line from stdin and
   answers with tagged lines on stdout.  Everything else the kernel prints
   (banners, init.m noise) is ignored by Emacs.

   Request (one line):
       REQ <id> <timeout-seconds> <flags> <base64(utf-8 code)>
   flags: "-" for none, otherwise any of
       g  also return a PNG when the result is graphical
       p  return a PNG of the result whatever it is
       b  also return the StandardForm boxes of a graphical result

   Reply (one line per item, <payload> is base64 of utf-8 text, or of the
   PNG bytes for PNG):
       @@WNB <id> STDOUT <payload>     text written by Print etc.
       @@WNB <id> MESSAGES <payload>   messages issued by the evaluation
       @@WNB <id> RESULT <payload>     OutputForm of the result
       @@WNB <id> PNG <payload>
       @@WNB <id> BOXES <payload>
       @@WNB <id> DONE <seconds> <status>   status: ok | timeout | aborted
*)

BeginPackage["WolframNB`Kernel`"]

Begin["`Private`"]

graphicalQ[expr_] :=
    MatchQ[expr,
        _Graphics | _Graphics3D | _Image | _Image3D | _Legended |
        _GraphicsGrid | _GraphicsRow | _GraphicsColumn | _Graph |
        _Manipulate | _Dynamic | _DynamicModule
    ]

b64[str_String] :=
    StringReplace[
        BaseEncode[StringToByteArray[str, "UTF-8"]],
        WhitespaceCharacter -> ""
    ]

b64[bytes_ByteArray] :=
    StringReplace[BaseEncode[bytes], WhitespaceCharacter -> ""]

emit[id_, tag_String, payload_String] :=
    WriteString["stdout", "@@WNB " <> id <> " " <> tag <> " " <> payload <> "\n"]

readCapture[stream_OutputStream] :=
    Module[{file = First[stream], text},
        Close[stream];
        text = Quiet @ Import[file, "Text"];
        Quiet @ DeleteFile[file];
        If [StringQ[text], text, ""]
    ]

pngOf[expr_] :=
    Quiet @ Check[
        ExportByteArray[Rasterize[expr, ImageResolution -> 144], "PNG"],
        $Failed
    ]

evaluate[code_String, timeout_] :=
    Module[{outStream, msgStream, held, result, status = "ok", t0 = AbsoluteTime[]},
        $Line++;
        outStream = OpenWrite[FormatType -> OutputForm];
        msgStream = OpenWrite[FormatType -> OutputForm];
        (* Lines are separate expressions: Hold[a;, b;, c].  Run them as one
           sequence so the result is the last value, not a Sequence that would
           splice into the reply. *)
        held = Block[{$Messages = {msgStream}},
            Replace[
                ToExpression[code, InputForm, Hold],
                {
                    Hold[] :> Hold[Null],
                    Hold[e__] :> Hold[CompoundExpression[e]]
                }
            ]
        ];
        result =
            Block[{$Output = {outStream}, $Messages = {msgStream}},
                CheckAbort[
                    TimeConstrained[
                        ReleaseHold[held],
                        timeout,
                        status = "timeout";
                        $Aborted
                    ]
                    ,
                    status = "aborted";
                    $Aborted
                ]
            ];
        {
            readCapture[outStream],
            readCapture[msgStream],
            result,
            status,
            AbsoluteTime[] - t0
        }
    ]

record[result_] :=
    (
        If [result =!= Null,
            Unprotect[Out];
            Out[$Line] = result
        ]
    )

handle[id_String, timeout_, flags_String, b64code_String] :=
    Module[{code},
        code = Quiet @ Check[
            ByteArrayToString[BaseDecode[b64code], "UTF-8"],
            $Failed
        ];
        If [StringQ[code],
            respond[id, code, timeout, flags]
            ,
            emit[id, "MESSAGES", b64["WolframNB: could not decode request"]];
            emit[id, "DONE", "0 aborted"]
        ]
    ]

respond[id_String, code_String, timeout_, flags_String] :=
    Module[{out, msgs, result, status, secs, png, boxes, graphical},
        {out, msgs, result, status, secs} = evaluate[code, timeout];
        record[result];
        graphical = status === "ok" && graphicalQ[result];
        If [out =!= "", emit[id, "STDOUT", b64[out]]];
        If [msgs =!= "", emit[id, "MESSAGES", b64[msgs]]];
        emit[id, "RESULT",
            b64[
                If [result === Null,
                    "",
                    ToString[result, OutputForm, PageWidth -> 150]
                ]
            ]
        ];
        If [
            status === "ok" && (
                (graphical && StringContainsQ[flags, "g"]) ||
                StringContainsQ[flags, "p"]
            )
            ,
            png = pngOf[result];
            If [ByteArrayQ[png], emit[id, "PNG", b64[png]]]
        ];
        (* The boxes of a result are what the Front End stores in its Output
           cell.  A graphic always sends them; any other result only when
           they are not huge. *)
        If [status === "ok" && result =!= Null && StringContainsQ[flags, "b"],
            boxes = Quiet @ Check[
                ToString[ToBoxes[result, StandardForm], InputForm, PageWidth -> Infinity],
                $Failed
            ];
            If [StringQ[boxes] && (graphical || StringLength[boxes] <= 100000),
                emit[id, "BOXES", b64[boxes]]]
        ];
        emit[id, "DONE", ToString[Round[secs, 0.01]] <> " " <> status]
    ]

(* One line, one request.  EOF on stdin means Emacs closed the pipe. *)
loop[] :=
    Module[{line, parts},
        While[True,
            line = InputString[""];
            If [!StringQ[line], Break[]];
            parts = StringSplit[line, " ", 5];
            Which[
                parts === {},
                    Null,
                parts[[1]] === "PING",
                    WriteString["stdout", "@@WNB 0 PONG " <> $Version <> "\n"],
                parts[[1]] === "QUIT",
                    Break[],
                parts[[1]] === "REQ" && Length[parts] === 5,
                    handle[
                        parts[[2]],
                        Quiet @ Check[ToExpression[parts[[3]]], Infinity],
                        parts[[4]],
                        parts[[5]]
                    ],
                True,
                    WriteString["stdout", "@@WNB 0 BADREQUEST\n"]
            ]
        ];
        Exit[0]
    ]

WriteString["stdout", "@@WNB 0 READY " <> $Version <> "\n"];

End[]

EndPackage[]

WolframNB`Kernel`Private`loop[]
