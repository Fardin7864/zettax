"""Regression tests for the store artifact gate; no Android SDK required."""
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('artifact_gate', Path(__file__).with_name('verify-play-artifact.py'))
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


def elf(identifier=b'A' * 16, is64=True, endian='<'):
    data = bytearray(256)
    data[:6] = b'\x7fELF' + bytes([2 if is64 else 1, 1 if endian == '<' else 2])
    struct.pack_into(endian + ('Q' if is64 else 'I'), data, 32 if is64 else 28, 64)
    struct.pack_into(endian + 'HH', data, 54 if is64 else 42, 56 if is64 else 32, 1)
    struct.pack_into(endian + 'I', data, 64, 4)
    note = struct.pack(endian + 'III', 4, len(identifier), 3) + b'GNU\0' + identifier
    struct.pack_into(endian + ('Q' if is64 else 'I'), data, 72 if is64 else 68, 128)
    struct.pack_into(endian + ('Q' if is64 else 'I'), data, 96 if is64 else 80, len(note))
    data[128:128 + len(note)] = note
    return bytes(data) + b'\n'.join(marker.encode() for marker in gate.REQUIRED_DART_MARKERS)


class ArtifactGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.native = self.root / 'jniLibs'
        (self.native / 'arm64-v8a').mkdir(parents=True)
        self.fresh = self.native / 'arm64-v8a/libapp.so'
        self.fresh.write_bytes(elf())
        self.bundle = self.root / 'test.aab'

    def package(self, payload=None):
        with zipfile.ZipFile(self.bundle, 'w') as archive:
            archive.writestr('base/manifest/AndroidManifest.xml', b'fixture')
            archive.writestr('base/dex/classes.dex', b'fixture')
            if payload is not None:
                archive.writestr('base/lib/arm64-v8a/libapp.so', payload)

    def test_build_id_survives_stripping_and_supports_all_elf_classes(self):
        for is64 in [False, True]:
            for endian in ['<', '>']:
                self.assertEqual(gate.elf_build_id(elf(is64=is64, endian=endian)), b'A' * 16)
        self.package(elf() + b'different debug footer')
        self.assertEqual(gate.inspect(self.bundle, self.native), [])

    def test_rejects_stale_native_library_even_with_current_disclosure_text(self):
        self.package(elf(b'B' * 16))
        self.assertTrue(any('build ID does not match' in error for error in gate.inspect(self.bundle, self.native)))

    def test_rejects_missing_native_outputs_or_omitted_abi(self):
        self.package(elf())
        self.assertTrue(any('No freshly compiled' in error for error in gate.inspect(self.bundle, self.root / 'missing')))
        self.package()
        errors = gate.inspect(self.bundle, self.native)
        self.assertTrue(any('missing its Dart AOT' in error for error in errors))
        self.assertTrue(any('missing the compiled' in error for error in errors))

    def test_rejects_missing_current_safety_markers(self):
        self.package(elf().replace(gate.REQUIRED_DART_MARKERS[0].encode(), b'outdated'))
        self.assertTrue(any('missing current safety marker' in error for error in gate.inspect(self.bundle)))

    def test_rejects_updater_code_in_utf16(self):
        self.package(elf() + gate.MARKERS[0].encode('utf-16le'))
        self.assertTrue(any('removed updater marker' in error for error in gate.inspect(self.bundle)))

    def test_rejects_malformed_or_missing_elf_build_ids(self):
        for data in [b'', b'not ELF', elf()[:100], b'\x7fELF' + b'\0' * 100]:
            self.assertIsNone(gate.elf_build_id(data))
        self.package(b'not ELF' + b'\n'.join(x.encode() for x in gate.REQUIRED_DART_MARKERS))
        self.assertTrue(any('unverifiable' in error for error in gate.inspect(self.bundle, self.native)))


if __name__ == '__main__':
    unittest.main()
