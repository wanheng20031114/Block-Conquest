"""Render on a private Windows desktop, without activating it or sending input.

The job object owns the entire process tree. Closing it also cleans up a failed
or timed-out renderer. No SwitchDesktop/foreground/input APIs are used.
"""
import argparse
import ctypes as c
from ctypes import wintypes as w
from pathlib import Path
import subprocess
import tempfile
import uuid


class Startup(c.Structure):
    _fields_ = [("cb", w.DWORD), ("reserved", w.LPWSTR), ("desktop", w.LPWSTR),
                ("title", w.LPWSTR), ("x", w.DWORD), ("y", w.DWORD),
                ("width", w.DWORD), ("height", w.DWORD), ("cx", w.DWORD),
                ("cy", w.DWORD), ("fill", w.DWORD), ("flags", w.DWORD),
                ("show", w.WORD), ("reserved_size", w.WORD),
                ("reserved_bytes", c.c_void_p), ("stdin", w.HANDLE),
                ("stdout", w.HANDLE), ("stderr", w.HANDLE)]


class Process(c.Structure):
    _fields_ = [("process", w.HANDLE), ("thread", w.HANDLE),
                ("pid", w.DWORD), ("tid", w.DWORD)]


class Limits(c.Structure):
    _fields_ = [("process_time", c.c_int64), ("job_time", c.c_int64),
                ("flags", w.DWORD), ("min_ws", c.c_size_t),
                ("max_ws", c.c_size_t), ("active", w.DWORD),
                ("affinity", c.c_size_t), ("priority", w.DWORD),
                ("scheduling", w.DWORD)]


class ExtendedLimits(c.Structure):
    _fields_ = [("basic", Limits), ("io", c.c_uint64 * 6),
                ("process_memory", c.c_size_t), ("job_memory", c.c_size_t),
                ("peak_process", c.c_size_t), ("peak_job", c.c_size_t)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("script", nargs="?")
    parser.add_argument("--output", required=True)
    parser.add_argument("--timeout", type=int, default=150)
    parser.add_argument("--godot", default=r"C:\Program Files\Godot\Godot.exe",
                        help="Explicit engine executable for version-specific validation")
    parser.add_argument("--real-time", action="store_true",
                        help="Use real frame delta for native multiplayer clock tests")
    parser.add_argument("--main-pack", help="Load an exported PCK instead of source resources")
    parser.add_argument("--project-dir", help="Isolated empty project directory for PCK verification")
    parser.add_argument("--headless", action="store_true", help="Run protocol checks without a renderer")
    parser.add_argument("--exported", action="store_true",
                        help="Run the actual exported EXE and adjacent PCK, without editor-only path/script overrides")
    parser.add_argument("--script-arg", action="append", default=[],
                        help="Extra Godot script argument; use --script-arg=--flag for flags")
    args = parser.parse_args()
    if args.exported and (args.script or args.main_pack):
        parser.error("An exported executable uses its adjacent PCK and packaged test entry point")
    if not args.exported and not args.script:
        parser.error("A script is required unless --exported is used")
    project = Path(__file__).resolve().parents[1]
    run_project = Path(args.project_dir).resolve() if args.project_dir else project
    run_project.mkdir(parents=True, exist_ok=True)
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    kernel = c.WinDLL("kernel32", use_last_error=True)
    user = c.WinDLL("user32", use_last_error=True)
    user.CreateDesktopW.argtypes = [w.LPCWSTR, w.LPCWSTR, c.c_void_p, w.DWORD, w.DWORD, c.c_void_p]
    user.CreateDesktopW.restype = w.HANDLE
    user.CloseDesktop.argtypes = [w.HANDLE]
    kernel.CreateJobObjectW.argtypes = [c.c_void_p, w.LPCWSTR]
    kernel.CreateJobObjectW.restype = w.HANDLE
    kernel.SetInformationJobObject.argtypes = [w.HANDLE, c.c_int, c.c_void_p, w.DWORD]
    kernel.CreateProcessW.argtypes = [w.LPCWSTR, w.LPWSTR, c.c_void_p, c.c_void_p,
                                     w.BOOL, w.DWORD, c.c_void_p, w.LPCWSTR,
                                     c.POINTER(Startup), c.POINTER(Process)]
    kernel.AssignProcessToJobObject.argtypes = [w.HANDLE, w.HANDLE]
    kernel.ResumeThread.argtypes = [w.HANDLE]
    kernel.WaitForSingleObject.argtypes = [w.HANDLE, w.DWORD]
    kernel.GetExitCodeProcess.argtypes = [w.HANDLE, c.POINTER(w.DWORD)]
    kernel.TerminateProcess.argtypes = [w.HANDLE, w.UINT]
    kernel.CloseHandle.argtypes = [w.HANDLE]

    def require(ok):
        if not ok:
            raise c.WinError(c.get_last_error())

    name = "BlockWarReview_" + uuid.uuid4().hex
    desktop = user.CreateDesktopW(name, None, None, 0, 0x01FF, None)
    require(desktop)
    job = None
    process = Process()
    log = Path(tempfile.gettempdir()) / (name + ".log")
    try:
        job = kernel.CreateJobObjectW(None, None)
        require(job)
        limits = ExtendedLimits()
        limits.basic.flags = 0x2000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        require(kernel.SetInformationJobObject(job, 9, c.byref(limits), c.sizeof(limits)))
        executable = str(Path(args.godot).resolve())
        command = subprocess.list2cmdline([
            executable, *( ["--headless"] if args.headless else []),
            *([] if args.exported else ["--path", str(run_project)]),
            *( ["--main-pack", str(Path(args.main_pack).resolve())] if args.main_pack else []),
            "--audio-driver", "Dummy",
            "--rendering-method", "forward_plus", "--resolution", "960x540",
            "--max-fps", "24", *([] if args.real_time else ["--fixed-fps", "24"]), "--log-file", str(log),
            *([] if args.exported else ["--script", args.script]), "--", str(output), *args.script_arg])
        startup = Startup()
        startup.cb = c.sizeof(startup)
        startup.desktop = "WinSta0\\" + name
        # Suspended until assigned to the cleanup job; below-normal priority.
        require(kernel.CreateProcessW(executable, c.create_unicode_buffer(command),
                                      None, None, False, 0x08004004, None,
                                      str(run_project), c.byref(startup), c.byref(process)))
        if not kernel.AssignProcessToJobObject(job, process.process):
            kernel.TerminateProcess(process.process, 3)
            require(False)
        print(f"PRIVATE_DESKTOP pid={process.pid} desktop={name}", flush=True)
        kernel.ResumeThread(process.thread)
        waited = kernel.WaitForSingleObject(process.process, args.timeout * 1000)
        if waited != 0:
            raise TimeoutError("Private renderer exceeded its time limit")
        code = w.DWORD()
        require(kernel.GetExitCodeProcess(process.process, c.byref(code)))
        print(log.read_text(encoding="utf-8", errors="replace") if log.exists() else "No renderer log")
        if code.value:
            raise RuntimeError(f"Renderer exited with {code.value}")
    finally:
        if job:
            kernel.CloseHandle(job)
        if process.process:
            kernel.WaitForSingleObject(process.process, 5000)
            kernel.CloseHandle(process.thread)
            kernel.CloseHandle(process.process)
        require(user.CloseDesktop(desktop))
        print(f"PRIVATE_DESKTOP closed; log={log}", flush=True)


if __name__ == "__main__":
    main()
