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
| `wolfram-nb-kernel-detach` | Start the kernel under `setsid -w` so a hard kill of Emacs's process cannot reach it (default t). |
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
These facts were measured on Wolfram Engine 15.0 with a probe entitlement.

- **A start costs at least one billing interval.** The interval is 900 s at 10
  credits per hour, so every kernel start costs 2.5 credits (shown rounded up)
  however briefly it runs. Short-lived kernels are therefore expensive:
  about 40 starts cost 104 credits. Creating an entitlement costs nothing.
- **Graphics start a second licensed kernel.** The first plot launches a
  headless Front End (`WolframPlayer -platform offscreen`), which starts its
  own sandbox `WolframKernel`. A session that renders graphics holds two
  licence slots, so an entitlement with `StandardKernelLimit` 1 cannot render
  graphics; use at least 2.
- **A graceful exit releases every slot.** After a plot and a clean stop the
  entitlement showed `StandardKernelActiveCount -> 0`.
- **A hard kill leaks a slot.** After a plot and a SIGHUP kill, no process was
  left on the machine but the server still reported `StandardKernelActiveCount
  -> 1`. Two such kills fill a limit of 2 and every later start fails with
  "No valid password found." Leaked slots were not billed further in
  the 30 minutes they were watched, but they stay allocated.
- **Stopping is therefore graceful.** `wolfram-nb-kernel-stop` sends `QUIT`,
  closes the kernel's input and waits; a kernel that is still booting is left to
  boot and exit by itself. With `wolfram-nb-kernel-detach` (default), the
  kernel also runs under `setsid -w`, so the SIGHUP Emacs sends to a deleted
  process or at exit does not reach it and it leaves through its own exit path
  when its input closes. This is covered by tests with a fake kernel; it has
  not been checked against the licence server.
- Not established: which exact paths leaked in the first two test runs. The
  first used `delete-process` directly; the second used graceful stops, and
  rendering in flight when a buffer is killed is the main suspect.
- The tests share one kernel per file for this reason.
- Check the counters after any session that starts many kernels:
  `LicenseEntitlements[]`, properties `CreditsSpent` and
  `StandardKernelActiveCount`. `DeleteObject[entitlement]` removes a leaked
  entitlement.
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
