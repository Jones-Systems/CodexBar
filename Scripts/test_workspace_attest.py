#!/usr/bin/env python3
"""Portable producer, protection and finalization proofs; no real builds or accounts."""

import hashlib
import json
import os
from pathlib import Path
import signal
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from contextlib import closing, nullcontext
from unittest.mock import patch

import workspace_attest as attest
import ci_swift_test_by_suite as runner


# Exact DV-01–05 from the pinned corpus; full qualification is A2/J2.
VECTORS = [{'id': 'DV-01',
  'entries': [],
  'listing_preimage_hex': '',
  'listing_sha256': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
  'manifest_preimage_hex': '',
  'manifest_sha256': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'},
 {'id': 'DV-02',
  'entries': [{'relpath': 'a',
               'type': 'file',
               'size': 3,
               'mtime_ns': 123,
               'mode': 420,
               'sha256': 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'}],
  'listing_preimage_hex': '610066696c65003300313233003432300a',
  'listing_sha256': 'ac7f870bd55ab3ec311c5883b973093f7f223064e87db151707ad66b758b047b',
  'manifest_preimage_hex': '7b226d6f6465223a3432302c2272656c70617468223a2261222c22736861323536223a2262613738313662663866303163666561343134313430646535646165323232336230303336316133393631373761396362343130666636316632303031356164222c2273697a65223a332c2274797065223a2266696c65227d0a',
  'manifest_sha256': '4ff8c56bdf17a023eea5fb2b5e86e45357342ca45c25fa6e7ea92e82ee5b6079'},
 {'id': 'DV-03',
  'entries': [{'relpath': 'z link',
               'type': 'symlink',
               'size': 4,
               'mtime_ns': 9,
               'mode': 511,
               'target': '../a'}],
  'listing_preimage_hex': '7a206c696e6b0073796d6c696e6b0034003900353131002e2e2f610a',
  'listing_sha256': '5f1c0fe1d07f578ccb02bae5a6a0a7791707beeed81459f70743e50c41e9f671',
  'manifest_preimage_hex': '7b226d6f6465223a3531312c2272656c70617468223a227a206c696e6b222c2273697a65223a342c22746172676574223a222e2e2f61222c2274797065223a2273796d6c696e6b227d0a',
  'manifest_sha256': '501a50222f895b40212da702cabbd7d5dede07077b48c8bb8b26e7d892c4b695'},
 {'id': 'DV-04',
  'entries': [{'relpath': 'sub', 'type': 'directory', 'size': 0, 'mtime_ns': 1, 'mode': 493},
              {'relpath': 'sub/a',
               'type': 'file',
               'size': 0,
               'mtime_ns': 2,
               'mode': 384,
               'sha256': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'}],
  'listing_preimage_hex': '737562006469726563746f727900300031003439330a7375622f610066696c6500300032003338340a',
  'listing_sha256': '61705e76e10b7dd5c3b0608fc754369241de1dfed3ceaae6afc59786751420db',
  'manifest_preimage_hex': '7b226d6f6465223a3439332c2272656c70617468223a22737562222c2273697a65223a302c2274797065223a226469726563746f7279227d0a7b226d6f6465223a3338342c2272656c70617468223a227375622f61222c22736861323536223a2265336230633434323938666331633134396166626634633839393666623932343237616534316534363439623933346361343935393931623738353262383535222c2273697a65223a302c2274797065223a2266696c65227d0a',
  'manifest_sha256': '4fa205034f316deae43e3602688d7fa16642c4d6a192b44d1ba5b4d0d3be4b0b'},
 {'id': 'DV-05',
  'entries': [{'relpath': 'é\nname',
               'type': 'file',
               'size': 0,
               'mtime_ns': 7,
               'mode': 420,
               'sha256': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'}],
  'listing_preimage_hex': 'c3a90a6e616d650066696c6500300037003432300a',
  'listing_sha256': '81ea3825f707155e13d0561a775b27b01f93305528756ae6551432e1f77b18fd',
  'manifest_preimage_hex': '7b226d6f6465223a3432302c2272656c70617468223a225c75303065395c6e6e616d65222c22736861323536223a2265336230633434323938666331633134396166626634633839393666623932343237616534316534363439623933346361343935393931623738353262383535222c2273697a65223a302c2274797065223a2266696c65227d0a',
  'manifest_sha256': '2e000c1344c59a9f99671aa909ec24c0677de55122f7af576eaacd5fc6494874'}]


class AttestationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='codexbar-attest-')
        self.addCleanup(self.temporary.cleanup)
        self.parent = Path(self.temporary.name).resolve()
        self.root = self.parent / 'repo'
        self.root.mkdir()
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        self.output = self.root / '.build'
        self.output.mkdir()
        self.file = self.output / 'object'
        self.file.write_bytes(b'abc')
        self.bound = attest.binding(self.root)
        self.enterContext(patch.object(runner, '_scratch_cleanup_safe', True))

    def test_pinned_wire_vectors(self):
        for vector in VECTORS:
            with self.subTest(vector=vector['id']):
                self.assertEqual(attest.listing_digest(vector['entries']), vector['listing_sha256'])
                entries = [{key: value for key, value in entry.items() if key != 'mtime_ns'}
                           for entry in vector['entries']]
                payload = attest.manifest_bytes(entries)
                self.assertEqual(payload.hex(), vector['manifest_preimage_hex'])
                self.assertEqual(hashlib.sha256(payload).hexdigest(), vector['manifest_sha256'])

    def observe(self, **kwargs):
        return attest.content_manifest(self.output, **kwargs)

    def records(self):
        return [json.loads(path.read_text()) for path in
                (Path(self.bound['git_dir']) / 'workspace-outputs').glob('*.json')]

    def test_full_content_baseline_detects_same_size_restored_mtime_additions_and_symlinks(self):
        first, payload = self.observe()
        self.assertEqual(first['verification'], 'content')
        self.assertEqual(first['content_manifest_sha256'], hashlib.sha256(payload).hexdigest())
        before = self.file.stat()
        self.file.write_bytes(b'xyz')
        os.utime(self.file, ns=(before.st_atime_ns, before.st_mtime_ns))
        changed, changed_payload = self.observe()
        self.assertEqual(first['listing_digest'], changed['listing_digest'])
        self.assertNotEqual(payload, changed_payload)
        outside = self.parent / 'outside'
        outside.write_text('never opened')
        (self.output / 'link').symlink_to(outside)
        _, added = self.observe()
        entries = list(map(json.loads, added.splitlines()))
        self.assertEqual(entries[0]['target'], str(outside))
        self.assertNotEqual(added, changed_payload)

    def test_whole_protection_scan_precedes_all_content_reads(self):
        for name, reason in [('.env', 'sensitive_ignored'), ('.git', 'nested_repository'),
                             ('server.KEY', 'sensitive_ignored')]:
            with self.subTest(name=name):
                protected = self.output / name
                protected.write_text('not read')
                protected.chmod(0)
                original = attest._open_relative
                def no_files(root_fd, relpath, flags):
                    if relpath in ('object', name):
                        self.fail('content opened before protection scan completed')
                    return original(root_fd, relpath, flags)
                with patch.object(attest, '_open_relative', side_effect=no_files):
                    result, payload = self.observe()
                self.assertEqual(result['verification'], 'unverifiable')
                self.assertIn(reason, result['reasons'])
                self.assertEqual(payload, b'')
                protected.chmod(0o600)
                protected.unlink()

    def test_bounds_and_changed_identity_are_unverifiable(self):
        (self.output / 'second').write_text('x')
        for bounds in [dict(max_entries=1), dict(max_bytes=2), dict(max_seconds=1e-12)]:
            with self.subTest(bounds=bounds):
                result, payload = self.observe(**bounds)
                self.assertEqual(result['verification'], 'unverifiable')
                self.assertIn('bound_exceeded', result['reasons'])
                self.assertEqual(payload, b'')
        with self.assertRaises(attest.Failure):
            self.observe(max_seconds=301)
        original = attest._metadata
        def changed(*args):
            result = original(*args)
            self.file.write_text('changed')
            return result
        with patch.object(attest, '_metadata', side_effect=changed):
            self.assertEqual(self.observe()[0]['verification'], 'unverifiable')

    def test_atomic_publication_preserves_baseline_on_interruption(self):
        first = attest.attest(self.output, 'fixture', self.bound, 'succeeded', attest.now(), capture_content=True)
        path = Path(first['sidecar'])
        baseline = path.read_bytes()
        manifest = path.parent / first['manifest']
        old_manifest = manifest.read_bytes()
        original = attest._publish
        def interrupted(path, payload):
            if path.suffix == '.json':
                raise OSError('interrupted after manifest')
            return original(path, payload)
        with patch.object(attest, '_publish', side_effect=interrupted), self.assertRaises(OSError):
            attest.attest(self.output, 'fixture', self.bound, 'failed', attest.now(), capture_content=True)
        self.assertEqual(path.read_bytes(), baseline)
        self.assertEqual(manifest.read_bytes(), old_manifest)
        self.assertEqual(len(list(path.parent.glob('*.manifest.jsonl'))), 2)
        self.assertEqual(len(list(path.parent.glob('*.json'))), 1)

    def test_optional_capture_never_changes_success_failure_or_cancel(self):
        producer = attest.Producer(self.root, 'fixture', [self.output])
        for result in (0, 23, 143):
            with self.subTest(result=result), patch.object(producer, 'finish', side_effect=OSError('disk')):
                self.assertEqual(attest.finalize(producer, result, True), result)
        self.assertTrue(producer.obligation.is_file())
        with patch.object(attest, 'binding', side_effect=attest.Failure('no_metadata')):
            self.assertIsNone(attest.begin(self.root, 'fixture', [self.output]))
        self.assertEqual(attest.finalize(None, 0, True), 0)

    def test_default_finalization_never_enumerates_outputs_and_names_external_owner(self):
        external = self.parent / 'external-build'
        external.mkdir()
        producer = attest.Producer(self.root, 'fixture', [self.output, external])
        with patch.object(attest.os, 'scandir', side_effect=AssertionError('routine traversal')):
            resolution = json.loads(producer.finish('succeeded', True).read_text())
        self.assertEqual({root['path'] for root in resolution['roots']}, {str(self.output), str(external)})
        for root in resolution['roots']:
            self.assertEqual(root['disposition'], 'retained')
            self.assertEqual(root['owner'], 'fixture')
            sidecar = json.loads(Path(root['sidecar']).read_text())
            self.assertEqual(sidecar['roots'][0]['verification'], 'unverifiable')
            self.assertEqual(sidecar['roots'][0]['reasons'], ['content_capture_deferred'])
            self.assertIsNone(sidecar['manifest'])

    def test_optional_discovery_failure_does_not_block_swift_command(self):
        with patch.object(runner.build_jobs, 'admission', return_value=nullcontext(['swift', 'test'])), \
                patch.object(attest, 'command_roots', side_effect=OSError('metadata missing')), \
                patch.object(runner, '_run_command', return_value=23) as command:
            self.assertEqual(runner.run_command(['swift', 'test']), 23)
        command.assert_called_once()

    def test_external_command_destinations_and_disposed_roots(self):
        external = self.parent / 'external-build'
        worktree, roots = attest.command_roots([
            'swift', 'test', '--package-path', str(self.root), '--scratch-path=' + str(external)])
        self.assertEqual(worktree, self.root)
        self.assertEqual(roots, [external])
        producer = attest.Producer(worktree, 'fixture', roots)
        resolution = json.loads(producer.finish('failed', True).read_text())
        self.assertEqual(resolution['roots'], [dict(path=str(external), disposition='disposed', reason='output_absent')])
        with patch.object(attest, 'binding', return_value={**self.bound, 'ino': -1}):
            with self.assertRaisesRegex(attest.Failure, 'identity_mismatch'):
                producer.finish('failed', True)

    def test_package_without_waitid_preserves_command_and_unresolved_obligation(self):
        waitid = os.waitid
        try:
            del os.waitid
            with patch.object(attest.os, 'execvp', side_effect=RuntimeError('exec boundary')) as execute:
                with self.assertRaisesRegex(RuntimeError, 'exec boundary'):
                    attest.run_package(self.root, ['bash', 'fixture'])
            execute.assert_called_once_with('bash', ['bash', 'fixture'])
        finally:
            os.waitid = waitid
        self.assertTrue(any(record['schema'] == 'codexbar-output-obligation/v1' for record in self.records()))
        self.assertFalse(any(record['schema'] == 'codexbar-output-finalization/v1' for record in self.records()))

    def test_terminal_outcomes_after_actual_drain_keep_build_path_and_defer_hash(self):
        for status in (0, 23, -signal.SIGTERM):
            with self.subTest(status=status):
                code = ('import os,signal; os.kill(os.getpid(),signal.SIGTERM)' if status < 0
                        else f'raise SystemExit({status})')
                with patch.object(attest, 'content_manifest', side_effect=AssertionError('routine hash')):
                    self.assertEqual(attest.run_package(self.root, [sys.executable, '-c', code]),
                                     143 if status < 0 else status)
                sidecars = [r for r in self.records() if r['schema'] == attest.SCHEMA]
                self.assertEqual(sidecars[-1]['roots'][0]['path'], str(self.output))
                # Directory enumeration has no ordering contract.
                self.assertTrue(any(r['status'] == attest.terminal_status(status) for r in sidecars))
                self.assertTrue(self.file.is_file())

    def test_unproved_drain_never_reads_outputs_and_retains_obligation(self):
        def uncertain(_command):
            runner._scratch_cleanup_safe = False
            return 23
        with patch.object(runner, '_run_command', side_effect=uncertain), \
                patch.object(attest, 'content_manifest', side_effect=AssertionError('uncertain content')):
            self.assertEqual(attest.run_package(self.root, ['fixture']), 23)
        records = self.records()
        sidecar = next(r for r in records if r['schema'] == attest.SCHEMA)
        self.assertEqual(sidecar['roots'][0]['reasons'], ['owned_child_drain_unproved'])
        resolution = next(r for r in records if r['schema'] == 'codexbar-output-finalization/v1')
        self.assertFalse(resolution['drain_proved'])
        self.assertTrue(all(root['disposition'] == 'unresolved' for root in resolution['roots']))
        self.assertTrue(self.file.exists())

    def test_reservation_refuses_capture_and_incarnation_binds_provenance(self):
        producer = attest.Producer(self.root, 'fixture', [self.output])
        path = Path(self.bound['git_common_dir']) / 'workspace-lifecycle/reservations.sqlite3'
        with closing(sqlite3.connect(path)) as connection, connection:
            connection.execute('INSERT INTO reservations VALUES (?,?,?)', (self.bound['admin_id'], 'held', '{}'))
        with self.assertRaisesRegex(attest.Failure, 'retiring'):
            producer.finish('cancelled', True)
        self.assertTrue(producer.obligation.exists())
        provenance = Path(self.bound['git_dir']) / 'workspace-provenance.json'
        self.assertIsNone(self.bound['breadcrumb_id'])
        provenance.write_text('{"breadcrumb_id":"birth"}')
        fresh = attest.binding(self.root)
        self.assertEqual(fresh['breadcrumb_id'], 'birth')
        self.assertNotEqual(attest.incarnation(fresh), attest.incarnation(self.bound))
        provenance.unlink()
        provenance.symlink_to(self.parent / 'outside')
        with self.assertRaises(OSError):
            attest.binding(self.root)


if __name__ == '__main__':
    unittest.main()
