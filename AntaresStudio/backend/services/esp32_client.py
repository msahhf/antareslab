import os
from typing import Dict, List, Callable, Tuple, Optional
import requests
from concurrent.futures import ThreadPoolExecutor, as_completed

class Esp32Error(Exception):
    def __init__(self, message: str, details: str = ""):
        super().__init__(message)
        self.message = message
        self.details = details

def ensure_dir(path: str) -> str:
    os.makedirs(path, exist_ok=True)
    return path

class Esp32Client:
    def __init__(self, ip: str, timeout_s: float = 6.0):
        self.ip = ip.strip()
        self.base = f"http://{self.ip}"
        self.timeout_s = timeout_s
        self.session = requests.Session()

        # Simple retry strategy
        adapter = requests.adapters.HTTPAdapter(max_retries=2, pool_connections=8, pool_maxsize=8)
        self.session.mount("http://", adapter)

    def ping(self) -> None:
        try:
            r = self.session.get(f"{self.base}/", timeout=self.timeout_s)
            if r.status_code != 200:
                raise Esp32Error(f"ESP32 index page did not return 200 (HTTP {r.status_code}).")
        except requests.exceptions.RequestException as e:
            raise Esp32Error("Cannot access ESP32 (timeout/connection error).", details=str(e))

    def get_scan_list(self) -> Dict[str, int]:
        try:
            r = self.session.get(f"{self.base}/360_list", timeout=self.timeout_s)
            if r.status_code != 200:
                raise Esp32Error(f"Failed to fetch scan list. /360_list returned HTTP {r.status_code}")
            data = r.json()
            if not isinstance(data, dict):
                raise ValueError("Response is not a JSON dict")
            
            out: Dict[str, int] = {}
            for k, v in data.items():
                try:
                    out[str(k)] = int(v)
                except Exception:
                    continue
            return out
        except Esp32Error:
            raise
        except Exception as e:
            raise Esp32Error("Failed to parse /360_list JSON response.", details=str(e))

    def download_scan(
        self,
        session_id: str,
        count: int,
        out_dir: str,
        progress: Callable[[int], None] = lambda p: None,
        log: Callable[[str], None] = lambda l: None,
        stop_flag: Callable[[], bool] = lambda: False,
        concurrency: int = 3,
    ) -> List[str]:
        """
        ESP32 file server may not handle many concurrent requests well.
        Concurrency is kept low (default 3).
        """
        ensure_dir(out_dir)
        session_id = session_id.strip()
        files: List[str] = []

        def _download_one(i: int) -> Tuple[int, Optional[str], Optional[str]]:
            if stop_flag():
                return i, None, "cancelled"
            url = f"{self.base}/360_{session_id}_{i}.jpg"
            try:
                r = self.session.get(url, timeout=self.timeout_s, stream=True)
                if r.status_code != 200:
                    return i, None, f"HTTP {r.status_code}"
                fp = os.path.join(out_dir, f"img_{i:04d}.jpg")
                with open(fp, "wb") as f:
                    for chunk in r.iter_content(chunk_size=64 * 1024):
                        if stop_flag():
                            return i, None, "cancelled"
                        if chunk:
                            f.write(chunk)
                return i, fp, None
            except Exception as e:
                return i, None, str(e)

        total = max(count, 0)
        if total <= 0:
            return []

        log(f"Starting download | Session: {session_id} | Count: {total}")
        done = 0

        with ThreadPoolExecutor(max_workers=max(1, int(concurrency))) as ex:
            futs = [ex.submit(_download_one, i) for i in range(total)]
            for fut in as_completed(futs):
                i, fp, err = fut.result()
                done += 1
                pct = int(done * 100 / total)
                progress(pct)
                if fp:
                    files.append(fp)
                    log(f"Saved: {os.path.basename(fp)}")
                else:
                    log(f"Failed to download image {i}: {err}")

        files.sort()
        if len(files) < total:
            log(f"Warning: Downloaded {len(files)}/{total} (incomplete)")
        else:
            log(f"Success: Downloaded {len(files)}/{total}")
        
        return files
