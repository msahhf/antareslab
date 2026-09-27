import sys
import platform
import importlib
from pathlib import Path

PKGS = [
    ("PyQt6", "PyQt6"),
    ("numpy", "numpy"),
    ("requests", "requests"),
    ("opencv (cv2)", "cv2"),
    ("joblib", "joblib"),
    ("open3d (optional)", "open3d"),
    ("rembg (optional)", "rembg"),
    ("onnxruntime (optional)", "onnxruntime"),
]

def try_import(modname: str):
    try:
        m = importlib.import_module(modname)
        ver = getattr(m, "__version__", "unknown")
        return True, ver, None
    except Exception as e:
        return False, None, str(e)

def main():
    print("=================================================")
    print(" ANTARES - System Diagnostic")
    print("=================================================")

    print(f"Python: {sys.version}")
    print(f"Executable: {sys.executable}")
    print(f"Platform: {platform.platform()} / {platform.machine()}")
    print(f"Working dir: {Path.cwd()}")
    print(f"Venv active: {'antares_env' in sys.executable.lower()}")
    print("-------------------------------------------------")

    all_ok = True
    for label, mod in PKGS:
        ok, ver, err = try_import(mod)
        if ok:
            print(f"[OK]   {label}: {ver}")
        else:
            print(f"[MISS] {label}: {err}")
            # open3d/rembg/onnxruntime optional
            if "optional" not in label:
                all_ok = False

    print("-------------------------------------------------")

    # Extra: cv2 build info (if exists)
    try:
        import cv2
        print("[INFO] OpenCV build summary (first lines):")
        info = cv2.getBuildInformation().splitlines()
        for line in info[:12]:
            print("       " + line)
    except Exception:
        pass

    print("-------------------------------------------------")
    if all_ok:
        print("RESULT: ✅ Base runtime hazır.")
    else:
        print("RESULT: ❌ Base runtime eksik. (Yukarıda MISS olanları düzelt)")
    print("=================================================")

if __name__ == "__main__":
    main()
