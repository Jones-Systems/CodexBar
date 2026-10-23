#!/usr/bin/env python3
"""Deterministic compiler admission and fake-child proofs; no Swift compilation."""

from contextlib import ExitStack
from fractions import Fraction
import fcntl
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import build_jobs as jobs


class Clock:
    def __init__(self):
        self.now = 0

    def monotonic(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds


class BuildJobsTests(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.directory = Path(self.stack.enter_context(tempfile.TemporaryDirectory()))
        self.clock = Clock()
        self.stack.enter_context(patch.object(jobs, "PLATFORM", "darwin"))
        self.stack.enter_context(patch.object(jobs.time, "monotonic", self.clock.monotonic))
        self.stack.enter_context(patch.object(jobs.time, "sleep", self.clock.sleep))
        self.stack.enter_context(patch.object(jobs, "lock_directory", return_value=self.directory / "lock"))
        self.stack.enter_context(patch.object(jobs.os, "cpu_count", return_value=12))
        self.stack.enter_context(patch.dict(os.environ, {}, clear=True))
        self.disk = self.stack.enter_context(patch.object(jobs.os, "statvfs", return_value=SimpleNamespace(
            f_bavail=40 * 1024 ** 3, f_frsize=1)))
        self.ticks = 0
        self.cpu = self.stack.enter_context(patch.object(jobs, "cpu_ticks", side_effect=self.read_ticks))

    def read_ticks(self):
        self.ticks += 1
        return (20 * self.ticks, 0, 80 * self.ticks, 0)

    def test_storage_exact_threshold_and_larger_budget(self):
        import ci_swift_test_by_suite as runner
        with patch.object(runner, "_scratch_cleanup_safe", True), \
                patch.object(runner, "_run_command", return_value=37) as execute:
            self.assertEqual(jobs.run(["swift", "build"], "swift"), 37)
            self.assertEqual(execute.call_count, 1)
            with patch.dict(os.environ, {"CODEXBAR_BUILD_PEAK_BYTES": str(10 * 1024 ** 3 + 1)}):
                with self.assertRaisesRegex(jobs.AdmissionError, "insufficient storage"):
                    jobs.run(["swift", "build"], "swift")
                self.assertEqual(execute.call_count, 1)
                self.disk.return_value.f_bavail += 1
                self.assertEqual(jobs.run(["swift", "build"], "swift"), 37)
            self.assertEqual(execute.call_count, 2)

    def test_storage_budget_rejects_invalid_or_lower_values(self):
        for name, minimum in [("CODEXBAR_BUILD_RESERVE_BYTES", 30 * 1024 ** 3),
                              ("CODEXBAR_BUILD_PEAK_BYTES", 10 * 1024 ** 3)]:
            for raw in ["", "-1", "0", "1.2", "NaN", " 40000000000", str(minimum - 1)]:
                with self.subTest(name=name, raw=raw), self.assertRaises(jobs.AdmissionError):
                    jobs.storage_budget({name: raw})
            actual = jobs.storage_budget({name: str(minimum + 1)})
            self.assertIn(minimum + 1, actual)

    def test_storage_unavailable_or_invalid_starts_no_child(self):
        import ci_swift_test_by_suite as runner
        for evidence in [OSError("unavailable"), SimpleNamespace(f_bavail=-1, f_frsize=1),
                         SimpleNamespace(f_bavail=100, f_frsize=0),
                         SimpleNamespace(f_bavail=40 * 1024 ** 3, f_frsize=1.0)]:
            with self.subTest(evidence=evidence), patch.object(runner, "_run_command") as execute:
                self.disk.side_effect = evidence if isinstance(evidence, Exception) else None
                self.disk.return_value = evidence
                with self.assertRaisesRegex(jobs.AdmissionError, "storage evidence unavailable"):
                    jobs.run(["swift", "build"], "swift")
                execute.assert_not_called()
                self.assertEqual((self.directory / "lock/compiler.lock").read_bytes(), b"")

    def test_storage_measurement_follows_wait_and_cpu_window(self):
        events = []
        def acquire(*_):
            events.append("lock")
            if len(events) == 1:
                raise BlockingIOError()
        def cpu(_):
            events.append("cpu")
            return Fraction(0), Fraction(0), 30
        def disk(_):
            events.append("disk")
            self.assertEqual((self.directory / "lock/compiler.lock").read_bytes(), b"")
            raise OSError("changed while waiting")
        with patch.object(jobs.fcntl, "flock", side_effect=acquire), \
                patch.object(jobs, "sample_window", side_effect=cpu):
            self.disk.side_effect = disk
            with self.assertRaises(jobs.AdmissionError):
                with jobs.admission(["swift", "build"]):
                    self.fail("launched")
        self.assertEqual(events, ["lock", "lock", "cpu", "disk"])

    def test_storage_measurement_cannot_extend_admission_deadline(self):
        def disk(_):
            self.clock.now = 300
            return SimpleNamespace(f_bavail=40 * 1024 ** 3, f_frsize=1)
        self.disk.side_effect = disk
        with self.assertRaisesRegex(jobs.AdmissionError, "deadline expired"):
            with jobs.admission(["swift", "build"]):
                self.fail("launched")
        self.assertEqual((self.directory / "lock/compiler.lock").read_bytes(), b"")

    def test_storage_swift_destinations_and_nonexistent_ancestor(self):
        package = self.directory / "package"
        package.mkdir()
        external = self.directory / "volume"
        external.mkdir()
        alias = self.directory / "alias"
        alias.symlink_to(external, target_is_directory=True)
        scratch = alias / "new/build"
        with patch.object(jobs.Path, "cwd", return_value=self.directory):
            for args in [["--package-path", "package", "--scratch-path", str(scratch)],
                         ["--package-path=package", "--scratch-path=" + str(scratch)]]:
                destinations = jobs.output_destinations(["build", *args], "swift", {})
                self.assertIn(package, destinations)
                self.assertIn(scratch, destinations)
                self.assertEqual(jobs.existing_output_ancestor(scratch), external.resolve())
                self.assertFalse((external / "new").exists())
            self.assertIn(self.directory / ".build", jobs.output_destinations(["build"], "swift", {}))
            self.assertIn(package / ".build", jobs.output_destinations(
                ["build", "--package-path", "package"], "swift", {}))
            for option in ["--cache-path", "--config-path", "--security-path", "--xunit-output"]:
                self.assertIn(external, jobs.output_destinations(["test", option + "=" + str(external)], "swift", {}))

    def test_storage_finds_package_from_nested_working_directory(self):
        package = self.directory / "package"
        nested = package / "Sources/Nested"
        nested.mkdir(parents=True)
        (package / "Package.swift").touch()
        with patch.object(jobs.Path, "cwd", return_value=nested):
            paths = jobs.output_destinations(["build"], "swift", {})
            self.assertIn(package / ".build", paths)
            self.assertNotIn(nested / ".build", paths)
        with patch.object(jobs.Path, "cwd", return_value=self.directory):
            paths = jobs.output_destinations(["build", "--package-path=package/Sources"], "swift", {})
            self.assertIn(package / ".build", paths)

    def test_storage_checks_each_destination_filesystem(self):
        first = self.directory / "volume-a"
        second = self.directory / "volume-b"
        first.mkdir()
        second.mkdir()
        seen = []
        def evidence(path):
            seen.append(path)
            return SimpleNamespace(f_bavail=40 * 1024 ** 3 - (path == second.resolve()), f_frsize=1)
        self.disk.side_effect = evidence
        with self.assertRaisesRegex(jobs.AdmissionError, "insufficient storage"):
            with jobs.admission(["xcodebuild", "build", "-derivedDataPath", str(first / "derived"),
                                 "-archivePath=" + str(second / "archive")], "xcode"):
                self.fail("launched")
        self.assertIn(first.resolve(), seen)
        self.assertIn(second.resolve(), seen)
        self.assertFalse((first / "derived").exists())
        self.assertFalse((second / "archive").exists())

    def test_storage_xcode_extra_destinations_and_safe_settings(self):
        for option in ["-resultBundlePath", "-resultStreamPath", "-clonedSourcePackagesDirPath", "-packageCachePath"]:
            for args in [[option, "output"], [option + "=output"]]:
                paths = jobs.output_destinations(["build", *args, "ARCHS=arm64", "CODE_SIGNING_ALLOWED=NO"], "xcode", {})
                self.assertIn(Path.cwd() / "output", paths)

    def test_storage_rejects_unknown_output_overrides(self):
        for kind, args in [("swift", ["--scratch-path="]), ("swift", ["--scratch-path", "$(ROOT)/build"]),
                           ("swift", ["--scratch-path", "~/build"]), ("swift", ["--new-output-path", "elsewhere"]),
                           ("swift", ["-Xswiftc", "-module-cache-path"]), ("swift", ["-Xcc=-fmodules-cache-path=x"]),
                           ("swift", ["--scratch-path=a", "--scratch-path=b"]),
                           ("swift", ["-C", "elsewhere"]), ("swift", ["--toolset=opaque.json"]),
                           ("swift", ["--multiroot-data-file", "workspace.json"]),
                           ("xcode", ["SYMROOT=elsewhere"]), ("xcode", ["OBJROOT[sdk=macosx*]=elsewhere"]),
                           ("xcode", ["-exportPath", "elsewhere"])]:
            with self.subTest(args=args), self.assertRaises(jobs.AdmissionError):
                jobs.output_destinations(args, kind, {})
        for name in ["SWIFTPM_BUILD_DIR", "SWIFTPM_MODULECACHE_OVERRIDE", "LLVM_PROFILE_FILE", "XCODE_XCCONFIG_FILE"]:
            with self.subTest(name=name), self.assertRaises(jobs.AdmissionError):
                jobs.output_destinations(["build"], "swift", {name: "elsewhere"})

    def test_capacity_examples_and_exact_boundary(self):
        for percentage, expected in [(20, 6), (50, 3), (70, 1), (75, 0), (80, 0), (100, 0)]:
            with self.subTest(percentage=percentage):
                self.assertEqual(jobs.capacity_jobs(12, Fraction(percentage, 100), Fraction(percentage, 100)), expected)
        self.assertEqual(jobs.capacity_jobs(10, Fraction(1, 2), Fraction(1, 2)), 3)

    def test_spike_guard(self):
        self.assertEqual(jobs.capacity_jobs(12, Fraction(1, 5), Fraction(3, 4)), 0)

    def test_invalid_cores(self):
        for cores in [None, 0, -1, True, 1.5]:
            with self.assertRaises(jobs.AdmissionError):
                jobs.capacity_jobs(cores, Fraction(0), Fraction(0))

    def test_all_job_forms_and_duplicate_minimum(self):
        for args in [["--jobs", "12"], ["--jobs=12"], ["-j", "12"], ["-j12"],
                     ["-j12", "--jobs=3", "-j", "4"]]:
            rest, limit = jobs.normalize(["test", *args, "--filter", "SomeTests"], "swift", {})
            self.assertEqual(rest, ["test", "--filter", "SomeTests"])
            self.assertEqual(limit, 3 if len(args) > 2 else 6)

    def test_filter_value_is_not_a_job_flag(self):
        self.assertEqual(jobs.normalize(["test", "--filter", "-j12", "-j2"], "swift", {}),
                         (["test", "--filter", "-j12"], 2))

    def test_environment_can_only_lower(self):
        for raw, expected in [("1", 1), ("5", 5), ("12", 6)]:
            self.assertEqual(jobs.normalize([], "swift", {"CODEXBAR_BUILD_JOBS": raw})[1], expected)
        for raw in ["", "0", "-1", "1.5", "+2", " 2"]:
            with self.assertRaises(jobs.AdmissionError):
                jobs.normalize([], "swift", {"CODEXBAR_BUILD_JOBS": raw})

    def test_invalid_jobs_and_opaque_compiler_overrides(self):
        for args in [["--"], ["-j"], ["-j0"], ["--jobs=-1"], ["@flags"], ["-Xswiftc", "@flags"],
                     ["-Xswiftc=-j12"], ["-Xswiftc", "-j", "-Xswiftc", "12"],
                     ["-Xswiftc", "-num-threads=12"], ["-Xswiftc=-num-threads"],
                     ["-Xswiftc", "-driver-batch-count", "-Xswiftc", "12"]]:
            with self.subTest(args=args), self.assertRaises(jobs.AdmissionError):
                jobs.normalize(args, "swift", {})
        self.assertEqual(jobs.normalize(["-Xswiftc", "-warnings-as-errors"], "swift", {})[0],
                         ["-Xswiftc", "-warnings-as-errors"])

    def test_xcode_flags(self):
        self.assertEqual(jobs.normalize(["-json", "build"], "xcode", {})[0], ["-json", "build"])
        self.assertEqual(jobs.normalize(["build", "-jobs", "12", "-jobs=2", "-jobs8"], "xcode", {}), (["build"], 2))
        for arg in ["OTHER_SWIFT_FLAGS=-j12", "SWIFT_NUM_THREADS=12", "SWIFT_NUM_THREADS[arch=arm64]=12", "-parallelizeTargets", "-xcconfig"]:
            with self.assertRaises(jobs.AdmissionError):
                jobs.normalize([arg], "xcode", {})

    def test_swift_trusted_tail_limits_each_compiler_to_one_thread(self):
        with jobs.admission(["swift", "build", "-c", "release", "-j12"]) as command:
            self.assertEqual(command, ["swift", "build", "-c", "release", "--jobs", "6",
                                       "-Xswiftc", "-num-threads", "-Xswiftc", "1"])

    def test_xcode_trusted_tail_disables_parallel_whole_module_optimization(self):
        with jobs.admission(["xcodebuild", "build", "-configuration", "Release"], "xcode") as command:
            self.assertEqual(command, ["xcodebuild", "build", "-configuration", "Release", "-jobs", "6",
                                       "SWIFT_USE_PARALLEL_WHOLE_MODULE_OPTIMIZATION=NO",
                                       "OTHER_SWIFT_FLAGS=$(inherited) -num-threads 1"])

    def test_reject_caller_parallel_whole_module_optimization_override(self):
        for setting in ["SWIFT_USE_PARALLEL_WHOLE_MODULE_OPTIMIZATION=YES",
                        "SWIFT_USE_PARALLEL_WHOLE_MODULE_OPTIMIZATION=NO",
                        "SWIFT_USE_PARALLEL_WHOLE_MODULE_OPTIMIZATION[arch=arm64]=YES"]:
            with self.subTest(setting=setting), self.assertRaises(jobs.AdmissionError):
                jobs.normalize(["build", setting], "xcode", {})

    def test_full_window_and_ci_cap(self):
        with patch.dict(os.environ, {"CI": "true"}), jobs.admission(["swift", "test", "-j12", "--parallel"]) as command:
            self.assertEqual(command, ["swift", "test", "--parallel", "--jobs", "6",
                                       "-Xswiftc", "-num-threads", "-Xswiftc", "1"])
            self.assertEqual(self.clock.now, 30)
            self.assertEqual(self.cpu.call_count, 7)

    def test_linux_is_unchanged(self):
        command = ["swift", "test", "-j12", "--parallel"]
        with patch.object(jobs, "PLATFORM", "linux"), patch.dict(os.environ, {"CODEXBAR_BUILD_JOBS": "bad"}):
            with jobs.admission(command) as actual:
                self.assertEqual(actual, command)
        self.cpu.assert_not_called()
        self.disk.assert_not_called()
        self.assertFalse((self.directory / "lock").exists())

    def test_github_hosted_runner_preserves_commands_without_local_admission(self):
        commands = [
            ("swift", ["swift", "build", "-c", "release", "-j12", "-Xswiftc", "-num-threads=12"]),
            ("swift", ["swift", "test", "--parallel"]),
            ("swift", ["swift", "test", "--skip-build", "--filter", "ExampleTests"]),
            ("swift", ["swift", "build", "--show-bin-path"]),
            ("xcode", ["xcodebuild", "build", "-jobs", "12", "SWIFT_USE_PARALLEL_WHOLE_MODULE_OPTIMIZATION=YES"]),
        ]
        with patch.dict(os.environ, {"GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "github-hosted",
                                     "CODEXBAR_BUILD_JOBS": "bad"}), \
                patch.object(jobs, "open_lock", side_effect=AssertionError("hosted runner opened local lock")):
            for kind, command in commands:
                with self.subTest(kind=kind, command=command), jobs.admission(command, kind) as actual:
                    self.assertEqual(actual, command)
        self.cpu.assert_not_called()
        self.assertEqual(self.clock.now, 0)
        self.assertFalse((self.directory / "lock").exists())

    def test_incomplete_or_self_hosted_identity_keeps_local_limits(self):
        environments = [
            {}, {"CI": "true"}, {"GITHUB_ACTIONS": "true"},
            {"RUNNER_ENVIRONMENT": "github-hosted"},
            {"GITHUB_ACTIONS": "false", "RUNNER_ENVIRONMENT": "github-hosted"},
            {"GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "self-hosted"},
        ]
        for environment in environments:
            with self.subTest(environment=environment), patch.dict(os.environ, environment, clear=True):
                start = self.clock.now
                with jobs.admission(["swift", "test", "-j12"]) as command:
                    self.assertEqual(command, ["swift", "test", "--jobs", "6",
                                               "-Xswiftc", "-num-threads", "-Xswiftc", "1"])
                self.assertEqual(self.clock.now - start, 30)

    def test_github_hosted_runner_keeps_shared_execution_and_exit_status(self):
        import ci_swift_test_by_suite as runner
        command = ["swift", "test", "--parallel", "-j12"]
        with patch.dict(os.environ, {"GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "github-hosted"}), \
                patch.object(runner, "_scratch_cleanup_safe", True), \
                patch.object(runner, "_run_command", return_value=37) as execute:
            self.assertEqual(jobs.run(command, "swift"), 37)
            self.assertEqual(runner.run_command(command), 37)
            self.assertEqual(execute.call_args_list[0].args[0], command)
            self.assertEqual(execute.call_args_list[1].args[0], command)
        self.cpu.assert_not_called()
        self.assertFalse((self.directory / "lock").exists())

    def test_github_hosted_runner_preserves_commands_without_local_admission(self):
        commands = [
            ("swift", ["swift", "build", "-c", "release", "-j12", "-Xswiftc", "-num-threads=12"]),
            ("swift", ["swift", "test", "--parallel"]),
            ("swift", ["swift", "test", "--skip-build", "--filter", "ExampleTests"]),
            ("swift", ["swift", "build", "--show-bin-path"]),
            ("xcode", ["xcodebuild", "build", "-jobs", "12", "SWIFT_USE_PARALLEL_WHOLE_MODULE_OPTIMIZATION=YES"]),
        ]
        with patch.dict(os.environ, {"GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "github-hosted",
                                     "CODEXBAR_BUILD_JOBS": "bad"}), \
                patch.object(jobs, "open_lock", side_effect=AssertionError("hosted runner opened local lock")):
            for kind, command in commands:
                with self.subTest(kind=kind, command=command), jobs.admission(command, kind) as actual:
                    self.assertEqual(actual, command)
        self.cpu.assert_not_called()
        self.assertEqual(self.clock.now, 0)
        self.assertFalse((self.directory / "lock").exists())

    def test_incomplete_or_self_hosted_identity_keeps_local_limits(self):
        environments = [
            {}, {"CI": "true"}, {"GITHUB_ACTIONS": "true"},
            {"RUNNER_ENVIRONMENT": "github-hosted"},
            {"GITHUB_ACTIONS": "false", "RUNNER_ENVIRONMENT": "github-hosted"},
            {"GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "self-hosted"},
        ]
        for environment in environments:
            with self.subTest(environment=environment), patch.dict(os.environ, environment, clear=True):
                start = self.clock.now
                with jobs.admission(["swift", "test", "-j12"]) as command:
                    self.assertEqual(command, ["swift", "test", "--jobs", "6",
                                               "-Xswiftc", "-num-threads", "-Xswiftc", "1"])
                self.assertEqual(self.clock.now - start, 30)

    def test_github_hosted_runner_keeps_shared_execution_and_exit_status(self):
        import ci_swift_test_by_suite as runner
        command = ["swift", "test", "--parallel", "-j12"]
        with patch.dict(os.environ, {"GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "github-hosted"}), \
                patch.object(runner, "_scratch_cleanup_safe", True), \
                patch.object(runner, "_run_command", return_value=37) as execute:
            self.assertEqual(jobs.run(command, "swift"), 37)
            self.assertEqual(runner.run_command(command), 37)
            self.assertEqual(execute.call_args_list[0].args[0], command)
            self.assertEqual(execute.call_args_list[1].args[0], command)
        self.cpu.assert_not_called()
        self.assertFalse((self.directory / "lock").exists())

    def test_skip_build_serializes_without_sampling(self):
        with jobs.admission(["swift", "test", "--skip-build"]) as command:
            self.assertEqual(command[-6:], ["--jobs", "6", "-Xswiftc", "-num-threads", "-Xswiftc", "1"])
            fd = jobs.open_lock()
            try:
                with self.assertRaises(BlockingIOError):
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            finally:
                os.close(fd)
        self.cpu.assert_not_called()

    def test_busy_then_recovery(self):
        with patch.object(jobs, "sample_window", side_effect=[(Fraction(3, 4), Fraction(3, 4), 30),
                                                             (Fraction(1, 2), Fraction(1, 2), 30)]):
            with jobs.admission(["swift", "build"]) as command:
                self.assertEqual(command[-6:], ["--jobs", "3", "-Xswiftc", "-num-threads", "-Xswiftc", "1"])

    def test_lock_wait_is_in_deadline_and_sample_follows_lock(self):
        events = []
        def acquire(*_):
            events.append("lock")
            if len(events) < 4:
                raise BlockingIOError()
        with patch.object(jobs.fcntl, "flock", side_effect=acquire), jobs.admission(["swift", "build"]):
            self.assertEqual(events, ["lock"] * 4)
            self.assertEqual(self.clock.now, 33)
        self.assertEqual(self.cpu.call_count, 7)

    def test_lock_deadline_never_samples_or_launches(self):
        with patch.object(jobs.fcntl, "flock", side_effect=BlockingIOError()), self.assertRaises(jobs.AdmissionError):
            with jobs.admission(["swift", "build"]):
                self.fail("launched")
        self.assertEqual(self.clock.now, 300)
        self.cpu.assert_not_called()

    def test_insufficient_window_after_lock(self):
        def acquire(*_):
            self.clock.now = 275
        with patch.object(jobs.fcntl, "flock", side_effect=acquire), self.assertRaises(jobs.AdmissionError):
            with jobs.admission(["swift", "build"]):
                self.fail("launched")
        self.cpu.assert_not_called()

    def test_bad_counters(self):
        for first, last in [((0, 0, 0, 0), (0, 0, 0, 0)), ((1, 0, 0, 0), (0, 0, 1, 0)),
                            ((0, 0, 0), (1, 0, 0)), ((0, 0, 0, 0), (1, -1, 2, 0))]:
            with self.assertRaises(jobs.AdmissionError):
                jobs.busy_fraction(first, last)

    def test_suspend_restarts_whole_window(self):
        waits = [11]
        def sleep(seconds):
            self.clock.now += waits.pop() if waits else seconds
        with patch.object(jobs.time, "sleep", side_effect=sleep):
            average, recent, duration = jobs.sample_window(300)
        self.assertEqual(duration, 30)
        self.assertEqual(self.clock.now, 41)
        self.assertEqual(self.cpu.call_count, 8)

    def test_repeated_suspend_exhausts_original_deadline(self):
        with patch.object(jobs.time, "sleep", side_effect=lambda _: setattr(self.clock, "now", self.clock.now + 100)):
            with self.assertRaises(jobs.AdmissionError):
                jobs.sample_window(300)

    def test_missing_data_cancels_without_launch_and_unlocks(self):
        for error in [jobs.AdmissionError("missing"), KeyboardInterrupt()]:
            with patch.object(jobs, "cpu_ticks", side_effect=error):
                with self.assertRaises(type(error)):
                    with jobs.admission(["swift", "build"]):
                        self.fail("launched")
            fd = jobs.open_lock()
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            os.close(fd)

    def test_lock_symlink_rejected(self):
        (self.directory / "lock").symlink_to(self.directory)
        with self.assertRaises(jobs.AdmissionError):
            jobs.open_lock()

    def test_unknown_cleanup_and_cancel_keep_fence(self):
        for cancelled in (False, True):
            with self.subTest(cancelled=cancelled):
                lock = self.directory / ("cancel-lock" if cancelled else "normal-lock")
                with patch.object(jobs, "lock_directory", return_value=lock):
                    try:
                        with jobs.admission(["swift", "test", "--skip-build"], cleanup_proved=lambda: False):
                            if cancelled:
                                raise SystemExit(143)
                    except SystemExit:
                        pass
                    self.assertIn('"state": "in-progress"', (lock / "compiler.lock").read_text())
                    with self.assertRaises(jobs.AdmissionError):
                        with jobs.admission(["swift", "build"]):
                            self.fail("launched after unknown cleanup")

    def test_proved_drain_clears_fence_even_on_cancel(self):
        with self.assertRaises(SystemExit):
            with jobs.admission(["swift", "test", "--skip-build"], cleanup_proved=lambda: True):
                raise SystemExit(143)
        self.assertEqual((self.directory / "lock/compiler.lock").read_bytes(), b"")

    def test_malformed_and_abandoned_records_block(self):
        fd = jobs.open_lock()
        os.close(fd)
        target = self.directory / "lock/compiler.lock"
        for record in [b"bad record", b'{"state":"in-progress","owner_pid":999999999}', b"\n"]:
            target.write_bytes(record)
            with self.assertRaises(jobs.AdmissionError):
                with jobs.admission(["swift", "build"]):
                    self.fail("launched")
            self.assertEqual(target.read_bytes(), record)
        self.cpu.assert_not_called()

    def test_runner_gates_discovery_metadata_and_retries(self):
        import ci_swift_test_by_suite as runner
        with patch.object(runner, "_scratch_cleanup_safe", True), patch.object(runner, "_run_command", return_value=0) as execute:
            for command in [["swift", "test", "list"], ["swift", "build", "--show-bin-path"],
                            ["swift", "test", "--skip-build", "--no-parallel", "--filter", "RetryTests"]]:
                self.assertEqual(runner.run_command(command), 0)
                self.assertEqual(execute.call_args.args[0], command + ["--jobs", "6",
                                                                       "-Xswiftc", "-num-threads", "-Xswiftc", "1"])
            self.assertEqual(self.cpu.call_count, 14)

    def test_cli_observes_runner_unknown_flag_on_return_and_cancel(self):
        import ci_swift_test_by_suite as runner
        for cancelled in (False, True):
            lock = self.directory / ("runner-cancel" if cancelled else "runner-return")
            def unknown(_command):
                runner._scratch_cleanup_safe = False
                if cancelled:
                    raise SystemExit(143)
                return 37
            with patch.object(jobs, "lock_directory", return_value=lock), \
                    patch.object(runner, "_scratch_cleanup_safe", True), \
                    patch.object(runner, "_run_command", side_effect=unknown) as execute:
                if cancelled:
                    with self.assertRaises(SystemExit):
                        jobs.run(["swift", "test", "--skip-build"], "swift")
                else:
                    self.assertEqual(jobs.run(["swift", "test", "--skip-build"], "swift"), 37)
                self.assertTrue((lock / "compiler.lock").read_bytes())
                with self.assertRaises(jobs.AdmissionError):
                    jobs.run(["swift", "build"], "swift")
                self.assertEqual(execute.call_count, 1)

    def test_child_exit_and_signal_status(self):
        self.stack.close()
        with patch.object(jobs, "PLATFORM", "linux"):
            self.assertEqual(jobs.run([sys.executable, "-c", "raise SystemExit(37)"], "swift"), 37)
            self.assertEqual(jobs.run([sys.executable, "-c", "import os,signal; os.kill(os.getpid(),signal.SIGTERM)"], "swift"), 143)


class StorageAdmissionTests(unittest.TestCase):
    def test_one_byte_short_never_starts_child_or_marks_lock(self):
        import ci_swift_test_by_suite as runner
        with tempfile.TemporaryDirectory() as raw, ExitStack() as stack:
            lock = Path(raw) / "lock"
            stack.enter_context(patch.object(jobs, "PLATFORM", "darwin"))
            stack.enter_context(patch.object(jobs, "lock_directory", return_value=lock))
            stack.enter_context(patch.object(jobs, "sample_window", return_value=(Fraction(0), Fraction(0), 30)))
            stack.enter_context(patch.object(jobs.os, "cpu_count", return_value=12))
            stack.enter_context(patch.dict(os.environ, {}, clear=True))
            stack.enter_context(patch.object(jobs.os, "statvfs", return_value=SimpleNamespace(
                f_bavail=40 * 1024 ** 3 - 1, f_frsize=1)))
            execute = stack.enter_context(patch.object(runner, "_run_command", return_value=0))
            with self.assertRaisesRegex(jobs.AdmissionError, "insufficient storage"):
                jobs.run(["swift", "build"], "swift")
            execute.assert_not_called()
            self.assertEqual((lock / "compiler.lock").read_bytes(), b"")


class RealLockTests(unittest.TestCase):
    def setUp(self):
        # These subprocess fixtures exercise local admission even on hosted CI.
        environment = patch.dict(os.environ, {"GITHUB_ACTIONS": "", "RUNNER_ENVIRONMENT": ""})
        environment.start()
        self.addCleanup(environment.stop)

    def test_cancel_drains_owned_descendant_before_unlock(self):
        import ci_swift_test_by_suite as runner
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            ready = root / "descendant"
            grandchild = "import time; time.sleep(30)"
            compiler = ("import subprocess,sys,time; from pathlib import Path; "
                        "child=subprocess.Popen([sys.executable,'-c'," + repr(grandchild) + "]); "
                        "Path(" + repr(str(ready)) + ").write_text(str(child.pid)); time.sleep(30)")
            bootstrap = ("import sys; sys.path.insert(0,sys.argv[1]); import build_jobs as b; "
                         "from pathlib import Path; from fractions import Fraction; b.PLATFORM='darwin'; "
                         "b.lock_directory=lambda:Path(sys.argv[2]); "
                         "b.sample_window=lambda deadline:(Fraction(0),Fraction(0),30); "
                         "from types import SimpleNamespace; "
                         "b.os.statvfs=lambda path:SimpleNamespace(f_bavail=40*1024**3,f_frsize=1); "
                         "sys.exit(b.run([sys.executable,'-c',sys.argv[3]],'swift'))")
            child = subprocess.Popen([sys.executable, "-B", "-c", bootstrap, str(Path(__file__).parent),
                                      str(root / "lock"), compiler], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                deadline = time.monotonic() + 5
                while not ready.exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(ready.exists())
                descendant = runner.test_process(int(ready.read_text()))
                self.assertIsNotNone(descendant)
                child.terminate()
                _, errors = child.communicate(timeout=10)
                self.assertEqual(child.returncode, 143, errors.decode())
                remaining = runner.test_process(descendant.pid)
                self.assertTrue(remaining is None or remaining.birth != descendant.birth or remaining.zombie)
                self.assertEqual((root / "lock/compiler.lock").read_bytes(), b"")
                with patch.object(jobs, "lock_directory", return_value=root / "lock"):
                    fd = jobs.open_lock()
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    os.close(fd)
            finally:
                if child.poll() is None:
                    child.terminate()
                    child.communicate(timeout=10)

    def test_cancel_sampling_never_launches(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            ready = root / "sampling"
            launched = root / "launched"
            bootstrap = (
                "import sys,time; sys.path.insert(0,sys.argv[1]); import build_jobs as b; "
                "from pathlib import Path; b.PLATFORM='darwin'; "
                "b.lock_directory=lambda:Path(sys.argv[2]); "
                "b.sample_window=lambda deadline:(Path(sys.argv[3]).touch(),time.sleep(20)); "
                "b.run([sys.executable,'-c',sys.argv[4]],'swift')")
            child = subprocess.Popen([sys.executable, "-B", "-c", bootstrap, str(Path(__file__).parent),
                                      str(root / "lock"), str(ready),
                                      "from pathlib import Path; Path(" + repr(str(launched)) + ").touch()"],
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                deadline = time.monotonic() + 5
                while not ready.exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(ready.exists())
                child.terminate()
                child.communicate(timeout=5)
                self.assertEqual(child.returncode, 143)
                self.assertFalse(launched.exists())
                with patch.object(jobs, "lock_directory", return_value=root / "lock"):
                    fd = jobs.open_lock()
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    os.close(fd)
            finally:
                if child.poll() is None:
                    child.terminate()
                    child.communicate(timeout=5)

    def test_fake_processes_across_worktrees_share_lock(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            lock = root / "lock"
            ready = root / "ready"
            first = root / "worktree-a"
            second = root / "worktree-b"
            first.mkdir()
            second.mkdir()
            script = ("import sys,os,time; sys.path.insert(0,sys.argv[1]); import build_jobs as b; "
                      "from pathlib import Path; b.lock_directory=lambda:Path(sys.argv[2]); "
                      "fd=b.open_lock(); b.fcntl.flock(fd,b.fcntl.LOCK_EX); "
                      "Path(sys.argv[3]).touch(); time.sleep(10)")
            child = subprocess.Popen([sys.executable, "-B", "-c", script, str(Path(__file__).parent), str(lock), str(ready)], cwd=first)
            try:
                deadline = time.monotonic() + 5
                while not ready.exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(ready.exists())
                probe = ("import sys; sys.path.insert(0,sys.argv[1]); import build_jobs as b; "
                         "from pathlib import Path; b.lock_directory=lambda:Path(sys.argv[2]); "
                         "fd=b.open_lock(); b.fcntl.flock(fd,b.fcntl.LOCK_EX|b.fcntl.LOCK_NB)")
                result = subprocess.run([sys.executable, "-B", "-c", probe, str(Path(__file__).parent), str(lock)],
                                        cwd=second, capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(b"BlockingIOError", result.stderr)
            finally:
                child.terminate()
                child.wait(timeout=5)
            with patch.object(jobs, "lock_directory", return_value=lock):
                fd = jobs.open_lock()
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                os.close(fd)


if __name__ == "__main__":
    unittest.main()
