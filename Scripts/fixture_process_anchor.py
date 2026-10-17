#!/usr/bin/env python3
"""Private gate/anchor for the synthetic fixture collector; never launches descendants itself."""

import os
import signal
import socket
import sys


def run(role, descriptor, command):
    with socket.socket(fileno=descriptor) as control:
        if role == "anchor":
            # Caught handlers survive here, but would reset across exec. This
            # process never execs or forks; it remains a live group member.
            for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
                signal.signal(sig, lambda *_: None)
            control.sendall(b"R")
            if control.recv(1) != b"":
                raise RuntimeError("Unexpected anchor control message")
            return
        if role != "command" or not command:
            raise RuntimeError("Invalid fixture helper role/command")
        control.sendall(b"R")
        if control.recv(1) != b"G":
            raise RuntimeError("Fixture command was not released")
    # Restore Popen's ordinary exec signal semantics after this Python gate.
    for name in ("SIGPIPE", "SIGXFZ", "SIGXFSZ"):
        if hasattr(signal, name):
            signal.signal(getattr(signal, name), signal.SIG_DFL)
    os.execvpe(command[0], command, os.environ)


if __name__ == "__main__":
    run(sys.argv[1], int(sys.argv[2]), sys.argv[3:])
