#!/usr/bin/env python3
"""Compile/run the demo's real coordination guards; no socket, device or compiler asset is used."""
from pathlib import Path
import subprocess


def main():
    """Use the SDK already built by the normal validation entry point and keep outputs under .build."""
    root = Path(__file__).resolve().parents[2]
    products = subprocess.run(['swift', 'build', '--show-bin-path'], cwd=root,
                              check=True, capture_output=True, text=True, timeout=30)
    path = Path(products.stdout.strip())
    output = root / '.build/workbench-device-coordination'
    output.mkdir(parents=True, exist_ok=True)
    sources = ['Tools/verify-demo-device-operations.swift', 'Demo/Shared/InstallationRecordStore.swift',
               'Demo/Shared/DemoOperationError.swift', 'Demo/Shared/WorkbenchBuildModel.swift',
               'Demo/Shared/WorkbenchModel.swift', 'Demo/Shared/CompilerRecordReader.swift']
    executable = output / 'verify'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-enable-upcoming-feature',
                    'ApproachableConcurrency', '-warnings-as-errors', '-parse-as-library',
                    '-target', 'arm64-apple-macos14.0', '-module-cache-path', str(output / 'cache'),
                    '-I', str(path), '-I', str(path / 'Modules'), *sources,
                    str(path / 'FirmingoKit.o'), '-o', str(executable)], cwd=root, check=True, timeout=90)
    subprocess.run([str(executable)], cwd=root, check=True, timeout=30)


if __name__ == '__main__':
    main()
