#!/usr/bin/env python3
"""A stand-in for the Wolfram kernel that speaks the wolfram-nb wire protocol.

It lets the Emacs side be tested without Wolfram.  Requests are tiny
commands instead of Wolfram code:

    name=NUMBER;     remember a value, empty result
    name             the value of name, or the name itself
    Print:TEXT       text on STDOUT
    Msg:TEXT         text on MESSAGES
    Png              result -Graphics-, a PNG, and boxes when the flags ask
    Split            a result line written in two pieces with a pause
    Noise            untagged output before the answer
    Sleep:SECONDS    pause, then answer
    Die              exit without answering
    anything else    echoed back as the result
"""
import base64
import os
import sys
import time

PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA"
    "60e6kgAAAABJRU5ErkJggg=="
)


def b64(text):
    return base64.b64encode(text.encode("utf-8")).decode()


def emit(rid, tag, payload):
    sys.stdout.write("@@WNB %s %s %s\n" % (rid, tag, payload))
    sys.stdout.flush()


def mark_clean_exit():
    """Record that the kernel left through its own exit path, not a signal."""
    path = os.environ.get("FAKE_KERNEL_EXIT_MARKER")
    if path:
        with open(path, "w") as marker:
            marker.write("clean\n")


def main():
    sys.stdin.readline()  # the bootstrap line
    sys.stdout.write("Fake kernel banner\n")
    sys.stdout.write("@@WNB 0 READY fake-1.0\n")
    sys.stdout.flush()
    values = {}
    for line in sys.stdin:
        parts = line.rstrip("\n").split(" ", 4)
        if parts[0] == "QUIT":
            break
        if parts[0] != "REQ" or len(parts) != 5:
            continue
        _, rid, _timeout, flags, payload = parts
        code = base64.b64decode(payload).decode("utf-8")
        result = code
        if code == "Die":
            sys.exit(3)
        elif code.startswith("Sleep:"):
            time.sleep(float(code[6:]))
            result = "slept"
        elif code.endswith(";") and "=" in code:
            name, value = code[:-1].split("=", 1)
            values[name] = value
            result = ""
        elif code in values:
            result = values[code]
        elif code.startswith("Print:"):
            emit(rid, "STDOUT", b64(code[6:]))
            result = ""
        elif code.startswith("Msg:"):
            emit(rid, "MESSAGES", b64("\n" + code[4:]))
            result = ""
        elif code == "Noise":
            sys.stdout.write("some stray output\n")
            sys.stdout.flush()
            result = "after noise"
        elif code == "Split":
            text = "@@WNB %s RESULT %s\n" % (rid, b64("split ok"))
            sys.stdout.write(text[:12])
            sys.stdout.flush()
            time.sleep(0.2)
            sys.stdout.write(text[12:])
            sys.stdout.flush()
            emit(rid, "DONE", "0.01 ok")
            continue
        elif code == "Png":
            emit(rid, "RESULT", b64("-Graphics-"))
            emit(rid, "PNG", base64.b64encode(PNG).decode())
            if "b" in flags:
                emit(rid, "BOXES", b64("GraphicsBox[{Circle[{0, 0}]}]"))
            emit(rid, "DONE", "0.01 ok")
            continue
        emit(rid, "RESULT", b64(result))
        emit(rid, "DONE", "0.01 ok")
    mark_clean_exit()


if __name__ == "__main__":
    main()
