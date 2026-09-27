#!/usr/bin/env python3
"""
ANTARES - rembg GPU Checker (Windows-friendly)

Goal:
- Detect whether rembg can use ONNX Runtime GPU (CUDAExecutionProvider).
- Give clear next steps.

This script does NOT attempt to install PyTorch.
rembg's common acceleration path is onnxruntime-gpu.
"""

import sys
import subprocess

def run(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True)

def header(t):
    print("\n" + "="*72)
    print(t)
    print("="*72)

def main():
    header("rembg GPU CHECK")

    # Python
    print(f"Python: {sys.version.split()[0]}")
    print("Executable:", sys.executable)

    # nvidia-smi (optional)
    r = run("nvidia-smi")
    if r.returncode == 0:
        print("\n[OK] nvidia-smi detected")
        print(r.stdout.splitlines()[0] if r.stdout else "")
    else:
        print("\n[WARN] nvidia-smi not available. If you have an NVIDIA GPU, install drivers.")

    # onnxruntime providers
    try:
        import onnxruntime as ort
        providers = ort.get_available_providers()
        print("\nONNX Runtime providers:", providers)
        if "CUDAExecutionProvider" in providers:
            print("[OK] CUDAExecutionProvider is available -> GPU path is possible.")
        else:
            print("[WARN] CUDAExecutionProvider NOT found -> rembg will run on CPU.")
            print("Next steps:")
            print("  pip install --upgrade onnxruntime-gpu")
    except Exception as e:
        print("\n[ERROR] onnxruntime not importable:", e)
        print("Next steps:")
        print("  pip install onnxruntime-gpu")

    # rembg import test
    try:
        import rembg  # noqa
        print("\n[OK] rembg is installed.")
    except Exception as e:
        print("\n[WARN] rembg not importable:", e)
        print("Next steps:")
        print("  pip install rembg Pillow")

    print("\nDone.")

if __name__ == "__main__":
    main()
