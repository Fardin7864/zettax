#!/usr/bin/env python3
"""Check APK/AAB safety markers and optional current Dart ELF build IDs.

This regression gate is deliberately limited; it is not a malware scanner or a
substitute for Google Play's review. Supports Android release APK/AAB artifacts.
"""
import argparse
import hashlib
from pathlib import Path
import struct
import zipfile


MARKERS = (
    'android.permission.REQUEST_INSTALL_PACKAGES',
    'android.settings.MANAGE_UNKNOWN_APP_SOURCES',
    'application/vnd.android.package-archive',
    'canRequestPackageInstalls',
    'zettax.app/updates',
    '/updates/latest.json',
    'AppUpdateHost',
)

# A removed-updater scan alone can pass an old flavored Flutter bundle. These
# strings prove that the baseline credential/funding and community fixes exist
# in every packaged Dart library. Build-ID matching checks the actual build too.
REQUIRED_DART_MARKERS = (
    'Change Zettax password',
    'Update Zettax password',
    'Zettax setup code',
    'Zettax request form',
    'Community safety',
    'Accept and continue',
)


def elf_build_id(data: bytes) -> bytes | None:
    """Read GNU build IDs from 32/64-bit ELF PT_NOTE segments, before/after strip."""
    if len(data) < 64 or data[:4] != b'\x7fELF' or data[4] not in (1, 2) or data[5] not in (1, 2):
        return None
    endian = '<' if data[5] == 1 else '>'
    is64 = data[4] == 2
    width = 'Q' if is64 else 'I'
    try:
        phoff = struct.unpack_from(endian + width, data, 32 if is64 else 28)[0]
        entry_size, count = struct.unpack_from(endian + 'HH', data, 54 if is64 else 42)
        if entry_size < (56 if is64 else 32) or phoff + entry_size * count > len(data):
            return None
        for index in range(count):
            entry = phoff + index * entry_size
            if struct.unpack_from(endian + 'I', data, entry)[0] != 4:
                continue
            offset = struct.unpack_from(endian + width, data, entry + (8 if is64 else 4))[0]
            size = struct.unpack_from(endian + width, data, entry + (32 if is64 else 16))[0]
            end = offset + size
            if end > len(data):
                return None
            while offset + 12 <= end:
                name_size, desc_size, note_type = struct.unpack_from(endian + 'III', data, offset)
                offset += 12
                desc_offset = offset + (name_size + 3) // 4 * 4
                next_offset = desc_offset + (desc_size + 3) // 4 * 4
                if next_offset > end:
                    return None
                name = data[offset:offset + name_size].rstrip(b'\0')
                if name == b'GNU' and note_type == 3 and desc_size:
                    return data[desc_offset:desc_offset + desc_size]
                offset = next_offset
    except struct.error:
        return None
    return None


def inspect(path: Path, native_libs: Path | None = None) -> list[str]:
    errors = []
    manifests = 0
    executable_payloads = 0
    expected = {p.parent.name: p for p in native_libs.glob('*/libapp.so')} if native_libs else {}
    packaged_abis = set()
    if native_libs is not None and not expected:
        errors.append(f'No freshly compiled Dart libraries found in {native_libs}')
    with zipfile.ZipFile(path) as archive:
        for name in archive.namelist():
            if name.endswith('.apk') or name.endswith('.jar'):
                errors.append(f'Unexpected embedded executable: {name}')
            if name.endswith('AndroidManifest.xml'):
                manifests += 1
            elif not (name.endswith('.dex') or name.endswith('/libapp.so')):
                continue
            else:
                executable_payloads += 1
            data = archive.read(name)
            if name.endswith('/libapp.so'):
                abi = name.split('/')[-2]
                if abi in packaged_abis:
                    errors.append(f'Duplicate packaged Dart library for {abi}')
                packaged_abis.add(abi)
                for marker in REQUIRED_DART_MARKERS:
                    if marker.encode() not in data and marker.encode('utf-16le') not in data:
                        errors.append(f'{name}: missing current safety marker {marker!r}; artifact may be stale')
                if native_libs is not None:
                    fresh = expected.get(abi)
                    packaged_id = elf_build_id(data)
                    fresh_id = elf_build_id(fresh.read_bytes()) if fresh else None
                    if not packaged_id or not fresh_id or packaged_id != fresh_id:
                        errors.append(f'{name}: stale or unverifiable Dart library; build ID does not match current compiled {abi}')
            for marker in MARKERS:
                if marker.encode() in data or marker.encode('utf-16le') in data:
                    errors.append(f'{name}: removed updater marker {marker!r}')
    if not manifests or not executable_payloads:
        errors.append('Artifact is missing its manifest or executable payloads')
    if not packaged_abis:
        errors.append('Artifact is missing its Dart AOT libraries')
    if native_libs is not None:
        for abi in expected.keys() - packaged_abis:
            errors.append(f'Artifact is missing the compiled Dart library for {abi}')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifact', type=Path)
    parser.add_argument('--native-libs', type=Path, help='Current build intermediates/flutter/playRelease/jniLibs directory; reject stale packaged build IDs')
    args = parser.parse_args()
    errors = inspect(args.artifact, args.native_libs)
    if errors:
        raise SystemExit('\n'.join(errors))
    print(f'PASS: no removed updater markers and all current safety markers in {args.artifact.name}')
    if args.native_libs:
        print('PASS: packaged Dart build IDs match the current compilation for every ABI')
    print(f'SHA-256: {hashlib.sha256(args.artifact.read_bytes()).hexdigest()}')
    print('This check does not certify the artifact as malware-free or Play approved.')


if __name__ == '__main__':
    main()
