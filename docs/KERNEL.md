# Persistent kernel

Each notebook buffer owns one Wolfram kernel, like a Front End session.
Definitions made in one cell are visible in the next, `%` works, and graphics
are rendered by the kernel that evaluated them.

## How it works

- Emacs starts `WolframKernel -noprompt` and sends `wolfram-nb-kernel-boot.wl`
  as the first input line. That file reads one request per line on stdin and
  answers on stdout with tagged base64 lines (`@@WNB <id> RESULT <payload>`).
  Anything else the kernel prints is ignored.
- `C-c C-c` and `C-c C-b` evaluate through that kernel. A result carries
  printed output, messages, the OutputForm text, and for graphics a PNG and
  the StandardForm boxes.
- Graphics are written to the Org buffer as a short placeholder block. The
  boxes stay in a buffer-local cache and are written back to the `.nb` as a
  real `Cell[BoxData[GraphicsBox[...]], "Output"]`, so Mathematica opens the
  plot as a plot. The PNG is only the preview shown in Emacs.
- Killing the buffer stops the kernel. `C-c C-z` restarts it (forgetting all
  definitions), `C-c C-q` stops it.
- Evaluation time is limited in the kernel (`wolfram-nb-eval-timeout`). A
  timeout aborts that evaluation and keeps the kernel and its definitions.

Precedence: an HTTP session from `#+WOLFRAM_SESSION:` wins, then the kernel,
then a fresh `wolframscript` per evaluation (`wolfram-nb-use-kernel` nil, or no
kernel found).

## Settings

| Variable | Meaning |
|---|---|
| `wolfram-nb-use-kernel` | Use a persistent kernel (default t). |
| `wolfram-nb-kernel-program` | Path to `WolframKernel`; found automatically otherwise. |
| `wolfram-nb-kernel-args` | Arguments, default `("-noprompt")`. |
| `wolfram-nb-kernel-command` | Whole command as a list; overrides the two above. |
| `wolfram-nb-kernel-stop-grace` | Seconds a stopping kernel gets to quit by itself. |

## A kernel somewhere else

The protocol is plain text on stdin and stdout, so a remote kernel is the same
command behind a prefix:

```elisp
(setq wolfram-nb-kernel-command
      '("ssh" "-T" "buildbox" "WolframKernel" "-noprompt"))
```

Nothing from the repository has to exist on the remote side: the bootstrap
travels over the same pipe.

## Licensing and cost

Read this before using an on-demand entitlement (`CreateLicenseEntitlement`).

- A kernel that is killed instead of quitting may not give its licence slot
  back. Stopping therefore sends `QUIT`, closes the kernel's input and waits,
  and only kills a kernel that is still alive a minute later. A kernel that is
  still booting is allowed to finish booting and then exits on its own.
- On the account used while developing this, two entitlements ended with
  `StandardKernelActiveCount -> 2` while no kernel was running, and
  `CreditsSpent` of 46 and 104 within minutes. Check `LicenseEntitlements[]`
  (properties `CreditsSpent`, `StandardKernelActiveCount`) after any session
  that starts many kernels.
- The tests share one kernel per file for this reason.
- For a development machine, a normal activation (`wolframscript -activate`)
  uses no credits.
- On a machine licensed through an entitlement, the kernel needs
  `-pwfile '!cloudlm.wolfram.com' -entitlement <id>`. Do not put the id on a
  command line you share; wrap the launch in a script that reads it from a
  mode 600 file and set `wolfram-nb-kernel-program` to that script.

## Tests

`tests/test-kernel.el` covers the protocol against `tests/fake-kernel.py` (no
Wolfram needed) and, when a licensed kernel exists, against the real one.
`tests/test-e2e.el` opens a notebook, evaluates it, saves it, checks the saved
file with the kernel, reopens it and saves again. Both skip when no kernel can
be started.
