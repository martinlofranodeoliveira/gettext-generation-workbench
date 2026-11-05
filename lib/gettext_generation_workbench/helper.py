#!/usr/bin/python3
"""Linux retained-anchor runner. Profiles and executables are package-owned."""
import ctypes
import json
import os
import selectors
import signal
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.realpath(__file__))
RUBY = "/usr/local/bin/ruby"
TOOLS = {"msgfmt": "/usr/bin/msgfmt", "msgmerge": "/usr/bin/msgmerge",
         "msgunfmt": "/usr/bin/msgunfmt", "msgattrib": "/usr/bin/msgattrib"}
PROFILES = {
    "extract": [RUBY, os.path.join(HERE, "extractor.rb")],
    "render": [RUBY, os.path.join(HERE, "worker.rb")],
    "compile": [TOOLS["msgfmt"], "--check", "--check-format", "-o", "catalog.mo", "catalog.po"],
    "merge": [TOOLS["msgmerge"], "--quiet", "--no-fuzzy-matching", "--no-wrap",
              "--sort-output", "-o", "merged.po", "old.po", "messages.pot"],
    "obsolete": [TOOLS["msgattrib"], "--only-obsolete", "--clear-obsolete", "--no-wrap",
                 "--force-po", "-o", "obsolete.po", "catalog.po"],
    "inspect": [TOOLS["msgunfmt"], "--force-po", "--no-wrap", "--sort-output", "-o", "inspected.po", "catalog.mo"],
}
for name, executable in TOOLS.items():
    PROFILES["version_" + name] = [executable, "--version"]
for mode in ("normal", "hang", "flood"):
    PROFILES["probe_" + mode] = [RUBY, os.path.join(HERE, "probe.rb"), mode]


def main():
    profile, job = sys.argv[1:]
    if profile not in PROFILES or not os.path.isabs(job):
        raise RuntimeError("profile")
    with open(os.path.join(job, ".job"), "rb") as marker:
        if marker.read(80) != b"gettext-generation-workbench job 0.1.0\n":
            raise RuntimeError("identity")
    # Ignored dispositions survive exec. Explicitly revoke inherited SIGCHLD
    # ignore before spawning: auto-reap would destroy the WNOWAIT PID anchor.
    inherited_sigchld_ignored = signal.getsignal(signal.SIGCHLD) == signal.SIG_IGN
    signal.signal(signal.SIGCHLD, signal.SIG_DFL)
    sigchld_default_before_spawn = signal.getsignal(signal.SIGCHLD) == signal.SIG_DFL
    # This helper has no alternate reaper.
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(36, 1, 0, 0, 0) != 0:  # PR_SET_CHILD_SUBREAPER
        raise RuntimeError("subreaper")
    control = 3
    os.set_inheritable(control, False)
    os.set_inheritable(4, False)
    os.set_blocking(control, False)
    selector = selectors.DefaultSelector()
    selector.register(control, selectors.EVENT_READ)
    leader = subprocess.Popen(PROFILES[profile], cwd=job, start_new_session=True,
                              close_fds=True, stdin=subprocess.DEVNULL)
    deadline = time.monotonic() + 5.0
    reason = "exit"
    observed = False
    while True:
        # WNOWAIT observes the leader WITHOUT freeing its PID/session anchor.
        status = os.waitid(os.P_PID, leader.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
        if status is not None:
            observed = True
            break
        if time.monotonic() >= deadline:
            reason = "deadline"
            break
        if selector.select(0.005):
            data = os.read(control, 256)
            reason = "stop" if data else "parent_closed"
            break
    events = []
    # All group signals happen while the direct child remains unreaped.
    for sig, label in ((signal.SIGTERM, "term"), (signal.SIGKILL, "kill")):
        try:
            os.killpg(leader.pid, sig)
        except ProcessLookupError:
            pass
        events.append(label)
    sealed = True
    events.append("seal")
    # No signaling is permitted below this line, even on cleanup errors.
    assert sealed
    code = leader.wait()
    events.append("reap")
    empty = False
    reap_deadline = time.monotonic() + 0.5
    while time.monotonic() < reap_deadline:
        try:
            pid, _ = os.waitpid(-1, os.WNOHANG)
            if pid == 0:
                time.sleep(0.002)
        except ChildProcessError:
            empty = True
            break
    report = {"reason": reason, "exit": code, "events": events,
              "children_empty": empty, "observed_exit": observed,
              "inherited_sigchld_ignored": inherited_sigchld_ignored,
              "sigchld_default_before_spawn": sigchld_default_before_spawn,
              "python": ".".join(map(str, sys.version_info[:3]))}
    os.write(4, json.dumps(report, separators=(",", ":")).encode("ascii"))
    selector.close()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Private diagnostics deliberately contain no arguments or paths.
        os.write(2, b"E_HELPER\n")
        sys.exit(2)
