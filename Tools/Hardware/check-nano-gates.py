"""Compile and execute the production Nano host admission policy; no compiler assets, sockets or device APIs."""
from pathlib import Path
import argparse
import subprocess


def main():
    """Use the maintained Apple toolchain and local module cache, then run finite policy checks."""
    argparse.ArgumentParser(description=__doc__).parse_args()
    root = Path(__file__).resolve().parents[2]; output = root / '.build/nano-gate-checks'; output.mkdir(parents=True, exist_ok=True)
    executable = output / 'CheckNanoGate'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '6', '-warnings-as-errors',
                    '-module-cache-path', str(output / 'cache'), str(root / 'Validation/NanoHost/NanoGate.swift'),
                    str(root / 'Tools/Hardware/CheckNanoGate.swift'), '-o', str(executable)], check=True, timeout=90)
    subprocess.run([str(executable)], check=True, timeout=10)


if __name__ == '__main__': main()
