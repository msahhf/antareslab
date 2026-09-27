# -*- coding: utf-8 -*-
"""
ANTARES KAPSÜL 3D STUDIO (AntaresStudio) - Stabil & Hız Odaklı Sürüm
Arduino + ESP32-CAM tabanlı 360° tarama -> indirme -> (opsiyonel) arkaplan temizleme -> 3D çıktı (PLY/OBJ/STL)

Bu sürümde:
- UI donmasını önlemek için QThread yerine QRunnable + QThreadPool kullanılır.
- ESP32 /360_list ve /360_<session>_<i>.jpg endpointleriyle uyumludur.
- Session ID (ESP32 millis) tarih gibi gösterilmez; "Session ID" olarak gösterilir.
- Arkaplan temizlemede varsayılan "GrabCut (Hızlı)" + opsiyonel "rembg".
- Feature extractor dinamik: SIFT (varsa) / AKAZE / ORB.
- Feature extraction joblib ile çok çekirdekli (varsa) çalışır; yoksa tek çekirdek.
- Bellek temizliği (gc) ve büyük dizilerde kontrollü serbest bırakma.

Not: Photogrammetry / SfM burada “hafif” bir pipeline’dır. En yüksek kalite için COLMAP entegrasyonu gerekir.
"""

from __future__ import annotations

import gc
import os
import sys
import json
import math
import time
import shutil
import platform
import traceback
import subprocess
from dataclasses import dataclass
from typing import Callable, Dict, List, Optional, Tuple

from pathlib import Path

import numpy as np
import requests
import cv2

from PyQt6.QtCore import Qt, QObject, pyqtSignal, QRunnable, QThreadPool
from PyQt6.QtGui import QFont
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget,
    QVBoxLayout, QHBoxLayout, QGridLayout,
    QLabel, QPushButton, QTabWidget, QLineEdit, QMessageBox,
    QListWidget, QProgressBar, QTextEdit, QGroupBox,
    QComboBox, QCheckBox, QSpinBox, QFileDialog
)

# ========================= THEME (fallback safe) =========================
try:
    from ui.styles import apply_dark_industrial_theme  # repo içinde varsa kullan
except Exception:
    def apply_dark_industrial_theme(app: QApplication) -> None:
        qss = """
        QWidget { background:#0b1220; color:#e5e7eb; font-family:Segoe UI; font-size:13px; }
        QGroupBox { border:1px solid #223047; border-radius:10px; margin-top:12px; padding:10px; }
        QGroupBox::title { subcontrol-origin: margin; left: 12px; padding:0 6px; color:#93c5fd; }
        QLineEdit, QTextEdit, QListWidget, QComboBox, QSpinBox {
            background:#0f172a; border:1px solid #223047; border-radius:10px; padding:8px;
            selection-background-color:#2563eb;
        }
        QPushButton {
            background:#111827; border:1px solid #223047; border-radius:12px; padding:10px 12px;
        }
        QPushButton:hover { background:#0b1a33; border-color:#2b3f5f; }
        QPushButton:disabled { background:#0f172a; color:#64748b; }
        QProgressBar { border:1px solid #223047; border-radius:10px; text-align:center; background:#0f172a; }
        QProgressBar::chunk { background:#38bdf8; border-radius:10px; }
        QTabBar::tab { background:#0f172a; border:1px solid #223047; border-bottom:none; padding:10px 12px; border-top-left-radius:10px; border-top-right-radius:10px; }
        QTabBar::tab:selected { background:#111827; color:#93c5fd; }
        """
        app.setStyleSheet(qss)


# ========================= Utilities =========================
class UserFacingError(RuntimeError):
    """Kullanıcıya anlamlı mesaj + çözüm ipucu göstermek için."""
    def __init__(self, title: str, message: str, hint: str = "", details: str = ""):
        super().__init__(message)
        self.title = title
        self.message = message
        self.hint = hint
        self.details = details


def ensure_dir(path: str) -> str:
    os.makedirs(path, exist_ok=True)
    return path

def get_data_root() -> str:
    """
    EXE Program Files altında çalışsa bile yazılabilir güvenli klasör döndürür.
    Windows: C:\\Users\\<user>\\AppData\\Local\\AntaresStudio
    """
    base = os.getenv("LOCALAPPDATA") or os.path.expanduser("~")
    root = Path(base) / "AntaresStudio"
    root.mkdir(parents=True, exist_ok=True)
    return str(root)


def open_in_file_manager(path: str) -> None:
    try:
        if sys.platform.startswith("win"):
            os.startfile(path)  # type: ignore[attr-defined]
        elif sys.platform == "darwin":
            subprocess.run(["open", path], check=False)
        else:
            subprocess.run(["xdg-open", path], check=False)
    except Exception:
        pass


def safe_float32(des: np.ndarray) -> np.ndarray:
    if des is None:
        return des
    if des.dtype != np.float32:
        return des.astype(np.float32, copy=False)
    return des


# ========================= ESP32 Client =========================
class Esp32Client:
    def __init__(self, ip: str, timeout_s: float = 6.0):
        self.ip = ip.strip()
        self.base = f"http://{self.ip}"
        self.timeout_s = timeout_s
        self.session = requests.Session()

        # Basit retry
        adapter = requests.adapters.HTTPAdapter(max_retries=2, pool_connections=8, pool_maxsize=8)
        self.session.mount("http://", adapter)

    def ping(self) -> None:
        try:
            r = self.session.get(f"{self.base}/", timeout=self.timeout_s)
            if r.status_code != 200:
                raise UserFacingError(
                    "ESP32 Bağlantı Hatası",
                    f"ESP32 ana sayfası 200 dönmedi (HTTP {r.status_code}).",
                    hint="ESP32 WiFi ağına bağlı olduğundan ve IP'nin doğru olduğundan emin ol.",
                )
        except requests.exceptions.RequestException as e:
            raise UserFacingError(
                "ESP32 Bağlantı Hatası",
                "ESP32'ye erişemiyorum (timeout / bağlantı hatası).",
                hint="Bilgisayarın ESP32-CAM WiFi ağına bağlı mı? IP genelde 192.168.4.1 olur.",
                details=str(e),
            )

    def get_scan_list(self) -> Dict[str, int]:
        try:
            r = self.session.get(f"{self.base}/360_list", timeout=self.timeout_s)
            if r.status_code != 200:
                raise UserFacingError(
                    "Tarama Listesi Alınamadı",
                    f"/360_list HTTP {r.status_code}",
                    hint="ESP32 arayüzü açık mı ve SD kart takılı mı? /360_list endpointi aktif olmalı.",
                )
            data = r.json()
            if not isinstance(data, dict):
                raise ValueError("JSON dict değil")
            # değerleri int'e zorla
            out: Dict[str, int] = {}
            for k, v in data.items():
                try:
                    out[str(k)] = int(v)
                except Exception:
                    continue
            return out
        except UserFacingError:
            raise
        except Exception as e:
            raise UserFacingError(
                "Tarama Listesi Parse Hatası",
                "ESP32 /360_list JSON yanıtı okunamadı.",
                hint="ESP32 seri monitörde 'Gönderilen JSON' satırını kontrol et; format bozuk olabilir.",
                details=str(e),
            )

    def download_scan(
        self,
        session_id: str,
        count: int,
        out_dir: str,
        progress: Callable[[int], None],
        log: Callable[[str], None],
        stop_flag: Callable[[], bool] = lambda: False,
        concurrency: int = 3,
    ) -> List[str]:
        """
        ESP32 dosya sunucusu aynı anda çok istek kaldırmayabilir.
        Bu yüzden concurrency düşük tutulur (varsayılan 3).
        """
        ensure_dir(out_dir)
        session_id = session_id.strip()
        files: List[str] = []

        # Basit paralel indirme: thread pool (requests IO bound)
        from concurrent.futures import ThreadPoolExecutor, as_completed

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

        log(f"📥 İndirme başlıyor | Session: {session_id} | Adet: {total}")
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
                    log(f"✓ [{i+1}/{total}] Kaydedildi: {os.path.basename(fp)}")
                else:
                    log(f"✗ [{i+1}/{total}] İndirilemedi: {err}")

        files.sort()
        if len(files) < total:
            log(f"⚠️ İndirilen: {len(files)}/{total} (eksik)")
        else:
            log(f"✅ İndirilen: {len(files)}/{total}")
        return files


# ========================= Worker base =========================
class WorkerSignals(QObject):
    progress = pyqtSignal(int)
    log = pyqtSignal(str)
    result = pyqtSignal(object)
    error = pyqtSignal(str, str, str)  # title, message, details
    finished = pyqtSignal()


class BaseWorker(QRunnable):
    def __init__(self):
        super().__init__()
        self.signals = WorkerSignals()
        self._cancel = False

    def cancel(self) -> None:
        self._cancel = True

    def is_cancelled(self) -> bool:
        return self._cancel


# ========================= Background Removal Strategies =========================
class BackgroundRemovalStrategy:
    name: str = "base"
    def process(self, img_path: str, out_path: str) -> None:
        raise NotImplementedError


class GrabCutFast(BackgroundRemovalStrategy):
    name = "GrabCut (Hızlı)"

    def process(self, img_path: str, out_path: str) -> None:
        img = cv2.imread(img_path)
        if img is None:
            raise RuntimeError("Görüntü okunamadı")
        h, w = img.shape[:2]
        rect = (int(w * 0.08), int(h * 0.08), int(w * 0.84), int(h * 0.84))
        mask = np.zeros((h, w), np.uint8)
        bgdModel = np.zeros((1, 65), np.float64)
        fgdModel = np.zeros((1, 65), np.float64)
        cv2.grabCut(img, mask, rect, bgdModel, fgdModel, 3, cv2.GC_INIT_WITH_RECT)
        mask2 = np.where((mask == 2) | (mask == 0), 0, 1).astype("uint8")
        white = np.full_like(img, 255)
        result = np.where(mask2[:, :, None] == 1, img, white)
        cv2.imwrite(out_path, result)
        del img, mask, bgdModel, fgdModel, mask2, white, result
        gc.collect()


class RembgRemove(BackgroundRemovalStrategy):
    name = "rembg (AI)"

    def __init__(self):
        try:
            from rembg import remove  # noqa
            from PIL import Image  # noqa
        except Exception as e:
            raise UserFacingError(
                "rembg Yüklü Değil",
                "AI arkaplan temizleme için 'rembg' bulunamadı.",
                hint="Kurulum: pip install rembg",
                details=str(e),
            )
        self._remove = remove
        self._Image = Image

    def process(self, img_path: str, out_path: str) -> None:
        inp = self._Image.open(img_path)
        out = self._remove(inp)
        out.save(out_path)
        inp.close()
        try:
            out.close()
        except Exception:
            pass
        gc.collect()


class BackgroundRemoveWorker(BaseWorker):
    def __init__(self, image_paths: List[str], out_dir: str, strategy: BackgroundRemovalStrategy):
        super().__init__()
        self.image_paths = image_paths
        self.out_dir = ensure_dir(out_dir)
        self.strategy = strategy

    def run(self) -> None:
        try:
            total = len(self.image_paths)
            processed: List[str] = []
            self.signals.log.emit(f"🧼 Arkaplan temizleme: {self.strategy.name}")
            for i, p in enumerate(self.image_paths):
                if self.is_cancelled():
                    break
                base = os.path.splitext(os.path.basename(p))[0]
                out_path = os.path.join(self.out_dir, f"{base}_clean.png")
                self.signals.log.emit(f"[{i+1}/{total}] {os.path.basename(p)}")
                self.strategy.process(p, out_path)
                processed.append(out_path)
                self.signals.progress.emit(int((i + 1) * 100 / total))
            self.signals.result.emit(processed)
        except UserFacingError as e:
            self.signals.error.emit(e.title, e.message, e.details or e.hint)
        except Exception as e:
            self.signals.error.emit("Arkaplan Temizleme Hatası", str(e), traceback.format_exc())
        finally:
            self.signals.finished.emit()


# ========================= Feature Extraction Strategies =========================
@dataclass
class FeaturePack:
    path: str
    xy: np.ndarray          # (N,2) float32
    des: np.ndarray         # (N,D) float32 or uint8
    norm: int               # cv2.NORM_*
    algo: str               # "SIFT"/"AKAZE"/"ORB"


class FeatureExtractorStrategy:
    name: str = "base"
    norm: int = cv2.NORM_L2

    def create(self, nfeatures: int):
        raise NotImplementedError

    def detect(self, img_bgr: np.ndarray, nfeatures: int) -> Tuple[np.ndarray, np.ndarray]:
        detector = self.create(nfeatures)
        gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
        kps, des = detector.detectAndCompute(gray, None)
        if des is None or kps is None or len(kps) == 0:
            return np.empty((0, 2), np.float32), np.empty((0, 1), np.float32)
        xy = np.array([kp.pt for kp in kps], dtype=np.float32)
        return xy, des


class SIFTExtractor(FeatureExtractorStrategy):
    name = "SIFT"
    norm = cv2.NORM_L2

    def create(self, nfeatures: int):
        return cv2.SIFT_create(nfeatures=nfeatures)


class AKAZEExtractor(FeatureExtractorStrategy):
    name = "AKAZE"
    norm = cv2.NORM_HAMMING

    def create(self, nfeatures: int):
        # AKAZE'de nfeatures paramı yok; default OK.
        return cv2.AKAZE_create()


class ORBExtractor(FeatureExtractorStrategy):
    name = "ORB"
    norm = cv2.NORM_HAMMING

    def create(self, nfeatures: int):
        return cv2.ORB_create(nfeatures=nfeatures)


def choose_feature_strategy(mode: str) -> FeatureExtractorStrategy:
    """
    mode: 'speed' | 'balanced' | 'quality'
    """
    mode = mode.lower().strip()
    if mode == "speed":
        return ORBExtractor()
    if mode == "quality":
        # SIFT varsa kullan, yoksa AKAZE
        try:
            _ = cv2.SIFT_create()
            return SIFTExtractor()
        except Exception:
            return AKAZEExtractor()
    # balanced
    try:
        _ = cv2.SIFT_create()
        return SIFTExtractor()
    except Exception:
        return AKAZEExtractor()


# ========================= Reconstruction Worker =========================
class ReconstructionWorker(BaseWorker):
    def __init__(
        self,
        image_paths: List[str],
        out_dir: str,
        mode: str,
        nfeatures: int,
        min_matches: int,
        wrap_match: bool = True,
        use_joblib: bool = True,
    ):
        super().__init__()
        self.image_paths = image_paths
        self.out_dir = ensure_dir(out_dir)
        self.mode = mode
        self.nfeatures = int(nfeatures)
        self.min_matches = int(min_matches)
        self.wrap_match = bool(wrap_match)
        self.use_joblib = bool(use_joblib)

    def run(self) -> None:
        try:
            self.signals.log.emit("=" * 72)
            self.signals.log.emit("🏗️ 3D Pipeline başlıyor (Hafif SfM)")
            self.signals.log.emit("=" * 72)
            self.signals.progress.emit(3)

            if len(self.image_paths) < 8:
                raise UserFacingError(
                    "Yetersiz Görüntü",
                    f"En az 8 görüntü gerekiyor. Şu an: {len(self.image_paths)}",
                    hint="ESP32’den indirme sırasında eksik fotoğraf geliyorsa /360_list ve SD kartı kontrol et.",
                )

            # 1) Load images (light validation)
            imgs = []
            for p in self.image_paths:
                img = cv2.imread(p)
                if img is None:
                    continue
                imgs.append((p, img))
            if len(imgs) < 8:
                raise UserFacingError(
                    "Görüntü Okuma Hatası",
                    "Bazı görüntüler okunamadı (cv2.imread None döndü).",
                    hint="Dosyaların bozulmadığını ve path’lerin doğru olduğunu kontrol et.",
                )
            self.signals.log.emit(f"📸 Okunan görüntü: {len(imgs)}/{len(self.image_paths)}")
            self.signals.progress.emit(10)

            # 2) Feature extraction
            strat = choose_feature_strategy(self.mode)
            self.signals.log.emit(f"🔍 Feature: {strat.name} | mod={self.mode} | nfeatures≈{self.nfeatures}")
            feats = self._extract_features(imgs, strat)
            if sum(fp.xy.shape[0] for fp in feats) == 0:
                raise UserFacingError(
                    "Feature Bulunamadı",
                    "Görüntülerde yeterli ayırt edici özellik bulunamadı.",
                    hint="Işıklandırmayı artır, bulanıklığı azalt, nesne kontrastını yükselt.",
                )
            self.signals.progress.emit(35)

            # 3) Adjacent matching
            matches = self._match_adjacent(feats)
            if len(matches) < 2:
                raise UserFacingError(
                    "Eşleştirme Başarısız",
                    "Yeterli eşleşen görüntü çifti yok.",
                    hint="Fotoğraflar arasında overlap olmalı. Döndürme adımını küçült (ör. 20°) veya foto sayısını artır.",
                )
            self.signals.progress.emit(55)

            # 4) Pose chain (relative)
            poses, K = self._estimate_pose_chain(imgs, feats, matches)
            if len(poses) < 2:
                raise UserFacingError(
                    "Pose Hesabı Başarısız",
                    "Kamera pozları çıkarılamadı.",
                    hint="Görüntü kalitesini artır; arkaplan sadeleştir; min_matches’i düşürmeyi dene.",
                )
            self.signals.progress.emit(70)

            # 5) Triangulate sparse points
            pts, cols = self._triangulate_sparse(imgs, feats, matches, poses, K)
            if pts.shape[0] < 200:
                raise UserFacingError(
                    "Nokta Bulutu Zayıf",
                    f"Çok az 3D nokta oluştu: {pts.shape[0]}",
                    hint="Daha çok foto çek, blur’u azalt, min_matches’i biraz düşür (ör. 60-80).",
                )
            self.signals.log.emit(f"🌐 Sparse points: {pts.shape[0]}")
            self.signals.progress.emit(82)

            # 6) Save point cloud + mesh (Open3D varsa)
            output_main = self._export_outputs(pts, cols, self.out_dir)
            self.signals.progress.emit(100)
            self.signals.result.emit(output_main)

        except UserFacingError as e:
            self.signals.error.emit(e.title, e.message, e.details or e.hint)
        except Exception as e:
            self.signals.error.emit("3D Pipeline Hatası", str(e), traceback.format_exc())
        finally:
            # Cleanup
            gc.collect()
            self.signals.finished.emit()

    # ---------------- internal steps ----------------
    def _extract_features(self, imgs: List[Tuple[str, np.ndarray]], strat: FeatureExtractorStrategy) -> List[FeaturePack]:
        paths = [p for p, _ in imgs]
        self.signals.log.emit(f"🧠 Feature çıkarımı (joblib={'ON' if self.use_joblib else 'OFF'})")

        def _one(path: str) -> FeaturePack:
            img = cv2.imread(path)
            if img is None:
                return FeaturePack(path, np.empty((0, 2), np.float32), np.empty((0, 1), np.float32), strat.norm, strat.name)
            xy, des = strat.detect(img, self.nfeatures)
            # SIFT des float32, ORB/AKAZE uint8
            if strat.norm == cv2.NORM_L2:
                des = safe_float32(des)
            del img
            return FeaturePack(path, xy, des, strat.norm, strat.name)

        feats: List[FeaturePack] = []
        if self.use_joblib:
            try:
                from joblib import Parallel, delayed
                # Lokalde çok core açmak ESP32 download değil CPU step; iyi.
                feats = Parallel(n_jobs=-1, prefer="threads")(delayed(_one)(p) for p in paths)
            except Exception:
                feats = [_one(p) for p in paths]
        else:
            feats = [_one(p) for p in paths]

        # log özet
        for i, fp in enumerate(feats):
            self.signals.log.emit(f"  ✓ [{i+1}/{len(feats)}] {os.path.basename(fp.path)} -> {fp.xy.shape[0]} feat")
            if self.is_cancelled():
                break
        return feats

    def _make_matcher(self, norm: int, algo: str):
        # SIFT -> FLANN (KDTree) , ORB/AKAZE -> BF Hamming
        if norm == cv2.NORM_L2:
            index_params = dict(algorithm=1, trees=5)
            search_params = dict(checks=50)
            return cv2.FlannBasedMatcher(index_params, search_params), True
        return cv2.BFMatcher(norm, crossCheck=False), False

    def _match_pair(self, a: FeaturePack, b: FeaturePack) -> List[cv2.DMatch]:
        if a.des is None or b.des is None or len(a.des) == 0 or len(b.des) == 0:
            return []
        matcher, _ = self._make_matcher(a.norm, a.algo)
        # FLANN requires float32
        des1, des2 = a.des, b.des
        if a.norm == cv2.NORM_L2:
            des1 = safe_float32(des1)
            des2 = safe_float32(des2)
        knn = matcher.knnMatch(des1, des2, k=2)
        good: List[cv2.DMatch] = []
        for pair in knn:
            if len(pair) < 2:
                continue
            m, n = pair[0], pair[1]
            if m.distance < 0.75 * n.distance:
                good.append(m)
        return good

    def _match_adjacent(self, feats: List[FeaturePack]) -> List[Tuple[int, int, List[cv2.DMatch]]]:
        self.signals.log.emit(f"🔗 Eşleştirme: komşu çiftler | min_matches={self.min_matches} | wrap={self.wrap_match}")
        matches: List[Tuple[int, int, List[cv2.DMatch]]] = []
        n = len(feats)
        pairs = [(i, i + 1) for i in range(n - 1)]
        if self.wrap_match and n >= 3:
            pairs.append((n - 1, 0))

        for idx, (i, j) in enumerate(pairs):
            if self.is_cancelled():
                break
            good = self._match_pair(feats[i], feats[j])
            if len(good) >= self.min_matches:
                matches.append((i, j, good))
                self.signals.log.emit(f"  ✓ [{i}]—[{j}] : {len(good)} match")
            else:
                self.signals.log.emit(f"  ✗ [{i}]—[{j}] : {len(good)} (yetersiz)")
        self.signals.log.emit(f"✅ Eşleşen çift: {len(matches)}/{len(pairs)}")
        return matches

    def _estimate_pose_chain(
        self,
        imgs: List[Tuple[str, np.ndarray]],
        feats: List[FeaturePack],
        matches: List[Tuple[int, int, List[cv2.DMatch]]],
    ) -> Tuple[Dict[int, Tuple[np.ndarray, np.ndarray]], np.ndarray]:
        # K: basit pinhole
        first_img = imgs[0][1]
        h, w = first_img.shape[:2]
        f = max(w, h) * 1.2
        K = np.array([[f, 0, w / 2], [0, f, h / 2], [0, 0, 1]], dtype=np.float64)

        self.signals.log.emit(f"📷 K (yaklaşık): f={f:.0f}, cx={w/2:.0f}, cy={h/2:.0f}")

        # Pose dictionary: index -> (R, t) in world (relative scale)
        poses: Dict[int, Tuple[np.ndarray, np.ndarray]] = {0: (np.eye(3), np.zeros((3, 1), np.float64))}

        # create quick lookup for adjacent matches
        match_map: Dict[Tuple[int, int], List[cv2.DMatch]] = {(i, j): ms for i, j, ms in matches}

        # forward chain 0->1->2...
        for j in range(1, len(feats)):
            i = j - 1
            key = (i, j)
            if key not in match_map:
                continue
            ms = match_map[key]
            pts1 = np.float32([feats[i].xy[m.queryIdx] for m in ms])
            pts2 = np.float32([feats[j].xy[m.trainIdx] for m in ms])

            E, mask = cv2.findEssentialMat(pts1, pts2, K, method=cv2.RANSAC, prob=0.999, threshold=2.0)
            if E is None:
                continue
            _, R_rel, t_rel, _ = cv2.recoverPose(E, pts1, pts2, K)

            if i in poses:
                R_i, t_i = poses[i]
                # compose: [Rj|tj] = [R_rel|t_rel] ∘ [Ri|ti]
                R_j = R_rel @ R_i
                t_j = R_rel @ t_i + t_rel
                poses[j] = (R_j, t_j)
                self.signals.log.emit(f"  ✓ Pose[{j}] ok (ref {i})")

        self.signals.log.emit(f"✅ Pose sayısı: {len(poses)}")
        return poses, K

    def _triangulate_sparse(
        self,
        imgs: List[Tuple[str, np.ndarray]],
        feats: List[FeaturePack],
        matches: List[Tuple[int, int, List[cv2.DMatch]]],
        poses: Dict[int, Tuple[np.ndarray, np.ndarray]],
        K: np.ndarray,
    ) -> Tuple[np.ndarray, np.ndarray]:
        pts_all = []
        col_all = []

        for (i, j, ms) in matches:
            if i not in poses or j not in poses:
                continue
            R_i, t_i = poses[i]
            R_j, t_j = poses[j]
            P1 = K @ np.hstack([R_i, t_i])
            P2 = K @ np.hstack([R_j, t_j])

            pts1 = np.float32([feats[i].xy[m.queryIdx] for m in ms])
            pts2 = np.float32([feats[j].xy[m.trainIdx] for m in ms])

            X4 = cv2.triangulatePoints(P1, P2, pts1.T, pts2.T)  # 4xN
            X = (X4[:3] / (X4[3] + 1e-9)).T  # Nx3

            # color sample from i image
            img_i = imgs[i][1]
            for k, uv in enumerate(pts1):
                x, y = int(uv[0]), int(uv[1])
                if 0 <= x < img_i.shape[1] and 0 <= y < img_i.shape[0]:
                    bgr = img_i[y, x].astype(np.float32) / 255.0
                    rgb = bgr[::-1]
                else:
                    rgb = np.array([0.8, 0.8, 0.8], np.float32)
                pts_all.append(X[k])
                col_all.append(rgb)

        pts = np.asarray(pts_all, dtype=np.float64)
        cols = np.asarray(col_all, dtype=np.float64)

        # Basit filtre: NaN/inf temizle
        m = np.isfinite(pts).all(axis=1)
        pts = pts[m]
        cols = cols[m]

        # Aşırı uçları kıs
        if pts.shape[0] > 0:
            center = np.median(pts, axis=0)
            dist = np.linalg.norm(pts - center, axis=1)
            keep = dist < np.quantile(dist, 0.98)
            pts = pts[keep]
            cols = cols[keep]

        return pts, cols

    def _export_outputs(self, pts: np.ndarray, cols: np.ndarray, out_dir: str) -> str:
        # 1) Save PLY point cloud
        ply_pc = os.path.join(out_dir, "point_cloud.ply")
        self._write_ply_points(ply_pc, pts, cols)
        self.signals.log.emit(f"💾 PointCloud: {ply_pc}")

        # 2) Mesh via Open3D (optional)
        try:
            import open3d as o3d  # noqa

            pcd = o3d.geometry.PointCloud()
            pcd.points = o3d.utility.Vector3dVector(pts)
            if cols is not None and cols.shape[0] == pts.shape[0]:
                pcd.colors = o3d.utility.Vector3dVector(cols)

            # downsample + denoise
            pcd = pcd.voxel_down_sample(voxel_size=0.003)
            pcd, _ = pcd.remove_statistical_outlier(nb_neighbors=20, std_ratio=2.0)

            # normals
            pcd.estimate_normals(search_param=o3d.geometry.KDTreeSearchParamHybrid(radius=0.03, max_nn=30))
            pcd.orient_normals_consistent_tangent_plane(50)

            # poisson
            self.signals.log.emit("🎨 Mesh: Poisson reconstruction…")
            mesh, dens = o3d.geometry.TriangleMesh.create_from_point_cloud_poisson(pcd, depth=8)
            dens = np.asarray(dens)
            mask = dens < np.quantile(dens, 0.02)
            mesh.remove_vertices_by_mask(mask)
            mesh.remove_degenerate_triangles()
            mesh.remove_duplicated_triangles()
            mesh.remove_duplicated_vertices()
            mesh.remove_non_manifold_edges()
            mesh.compute_vertex_normals()

            mesh_ply = os.path.join(out_dir, "mesh.ply")
            o3d.io.write_triangle_mesh(mesh_ply, mesh)
            self.signals.log.emit(f"💾 Mesh PLY: {mesh_ply}")

            # OBJ + STL
            mesh_obj = os.path.join(out_dir, "mesh.obj")
            mesh_stl = os.path.join(out_dir, "mesh.stl")
            o3d.io.write_triangle_mesh(mesh_obj, mesh)
            o3d.io.write_triangle_mesh(mesh_stl, mesh)
            self.signals.log.emit(f"💾 OBJ: {mesh_obj}")
            self.signals.log.emit(f"💾 STL: {mesh_stl}")

            return mesh_ply
        except Exception as e:
            self.signals.log.emit(f"⚠️ Open3D mesh üretilemedi (opsiyonel): {e}")
            return ply_pc

    def _write_ply_points(self, filepath: str, pts: np.ndarray, cols: np.ndarray) -> None:
        with open(filepath, "w", encoding="utf-8") as f:
            f.write("ply\nformat ascii 1.0\n")
            f.write(f"element vertex {pts.shape[0]}\n")
            f.write("property float x\nproperty float y\nproperty float z\n")
            has_color = cols is not None and cols.shape[0] == pts.shape[0]
            if has_color:
                f.write("property uchar red\nproperty uchar green\nproperty uchar blue\n")
            f.write("end_header\n")
            if has_color:
                c255 = np.clip(cols * 255.0, 0, 255).astype(np.uint8)
                for p, c in zip(pts, c255):
                    f.write(f"{p[0]} {p[1]} {p[2]} {int(c[0])} {int(c[1])} {int(c[2])}\n")
            else:
                for p in pts:
                    f.write(f"{p[0]} {p[1]} {p[2]}\n")


# ========================= Download Worker =========================
class DownloadWorker(BaseWorker):
    def __init__(self, ip: str, session_id: str, count: int, out_dir: str, concurrency: int = 3):
        super().__init__()
        self.ip = ip
        self.session_id = session_id
        self.count = int(count)
        self.out_dir = out_dir
        self.concurrency = int(concurrency)

    def run(self) -> None:
        try:
            client = Esp32Client(self.ip)
            client.ping()
            files = client.download_scan(
                session_id=self.session_id,
                count=self.count,
                out_dir=self.out_dir,
                progress=lambda p: self.signals.progress.emit(p),
                log=lambda s: self.signals.log.emit(s),
                stop_flag=self.is_cancelled,
                concurrency=self.concurrency
            )
            self.signals.result.emit(files)
        except UserFacingError as e:
            self.signals.error.emit(e.title, e.message, e.details or e.hint)
        except Exception as e:
            self.signals.error.emit("İndirme Hatası", str(e), traceback.format_exc())
        finally:
            self.signals.finished.emit()


# ========================= Viewer helper (separate process) =========================
def run_viewer(model_path: str) -> int:
    """
    Open3D viewer'ı UI'dan bağımsız çalıştır.
    UI thread'i kilitlememesi için ayrı process olarak çağırılır.
    """
    try:
        import open3d as o3d  # noqa
        geom = None
        if model_path.lower().endswith(".ply"):
            # ply mesh veya point cloud olabilir
            mesh = o3d.io.read_triangle_mesh(model_path)
            if len(mesh.vertices) > 0 and len(mesh.triangles) > 0:
                geom = mesh
            else:
                pcd = o3d.io.read_point_cloud(model_path)
                geom = pcd
        elif model_path.lower().endswith(".obj") or model_path.lower().endswith(".stl"):
            mesh = o3d.io.read_triangle_mesh(model_path)
            geom = mesh
        else:
            return 2

        if geom is None:
            return 3
        o3d.visualization.draw_geometries([geom], window_name="AntaresStudio - Open3D Viewer")
        return 0
    except Exception:
        return 1


# ========================= Main GUI =========================
class AntaresStudio(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("ANTARES - AntaresStudio (3D) | Stable")
        self.setGeometry(120, 80, 1400, 900)

        self.pool = QThreadPool.globalInstance()
        self.pool.setMaxThreadCount(max(4, os.cpu_count() or 4))

        self.downloaded_images: List[str] = []
        self.processed_images: List[str] = []
        self.output_model: Optional[str] = None
        self.current_out_dir: Optional[str] = None

        self._build_ui()

    # ---------------- UI ----------------
    def _build_ui(self):
        central = QWidget()
        self.setCentralWidget(central)
        main = QVBoxLayout(central)

        header = QLabel("🚀 ANTARES - AntaresStudio (3D)")
        header.setFont(QFont("Segoe UI", 20, QFont.Weight.Bold))
        header.setAlignment(Qt.AlignmentFlag.AlignCenter)
        header.setStyleSheet("color:#38bdf8; padding:14px;")
        main.addWidget(header)

        self.tabs = QTabWidget()
        main.addWidget(self.tabs)

        self.tabs.addTab(self._tab_download(), "📥 ESP32 Download")
        self.tabs.addTab(self._tab_recon(), "🏗️ 3D Pipeline")
        self.tabs.addTab(self._tab_viewer(), "👁️ Viewer")
        self.tabs.addTab(self._tab_help(), "ℹ️ Yardım")

    def _tab_download(self) -> QWidget:
        w = QWidget()
        lay = QVBoxLayout(w)

        g = QGroupBox("ESP32 Bağlantı")
        gl = QGridLayout()
        gl.addWidget(QLabel("ESP32 IP:"), 0, 0)
        self.txt_ip = QLineEdit("192.168.4.1")
        gl.addWidget(self.txt_ip, 0, 1)
        self.btn_ping = QPushButton("🔌 Test")
        self.btn_ping.clicked.connect(self.on_ping)
        gl.addWidget(self.btn_ping, 0, 2)

        self.btn_refresh = QPushButton("🔄 /360_list Yenile")
        self.btn_refresh.clicked.connect(self.on_refresh_scans)
        gl.addWidget(self.btn_refresh, 1, 0, 1, 3)
        g.setLayout(gl)
        lay.addWidget(g)

        g2 = QGroupBox("360° Tarama Listesi")
        l2 = QVBoxLayout()
        self.list_scans = QListWidget()
        l2.addWidget(self.list_scans)

        row = QHBoxLayout()
        self.btn_download = QPushButton("📥 Seçili Taramayı İndir")
        self.btn_download.clicked.connect(self.on_download)
        row.addWidget(self.btn_download)

        self.spn_conc = QSpinBox()
        self.spn_conc.setRange(1, 6)
        self.spn_conc.setValue(3)
        self.spn_conc.setToolTip("Aynı anda indirme sayısı (ESP32 zorlanmasın diye düşük tut)")
        row.addWidget(QLabel("İndirme paralel:"))
        row.addWidget(self.spn_conc)
        l2.addLayout(row)

        g2.setLayout(l2)
        lay.addWidget(g2)

        g3 = QGroupBox("İndirme Durumu")
        l3 = QVBoxLayout()
        self.lbl_dl = QLabel("Durum: Beklemede")
        self.pb_dl = QProgressBar()
        l3.addWidget(self.lbl_dl)
        l3.addWidget(self.pb_dl)
        g3.setLayout(l3)
        lay.addWidget(g3)

        g4 = QGroupBox("Log")
        l4 = QVBoxLayout()
        self.log_dl = QTextEdit()
        self.log_dl.setReadOnly(True)
        self.log_dl.setMaximumHeight(240)
        l4.addWidget(self.log_dl)
        g4.setLayout(l4)
        lay.addWidget(g4)

        return w

    def _tab_recon(self) -> QWidget:
        w = QWidget()
        lay = QVBoxLayout(w)

        g = QGroupBox("Pipeline Ayarları")
        l = QGridLayout()

        l.addWidget(QLabel("Mod:"), 0, 0)
        self.cmb_mode = QComboBox()
        self.cmb_mode.addItems(["speed", "balanced", "quality"])
        self.cmb_mode.setCurrentText("balanced")
        l.addWidget(self.cmb_mode, 0, 1)

        l.addWidget(QLabel("nfeatures:"), 1, 0)
        self.spn_feat = QSpinBox()
        self.spn_feat.setRange(500, 8000)
        self.spn_feat.setValue(2000)
        self.spn_feat.setSingleStep(250)
        l.addWidget(self.spn_feat, 1, 1)

        l.addWidget(QLabel("min_matches:"), 2, 0)
        self.spn_matches = QSpinBox()
        self.spn_matches.setRange(20, 400)
        self.spn_matches.setValue(80)
        self.spn_matches.setSingleStep(10)
        l.addWidget(self.spn_matches, 2, 1)

        self.chk_wrap = QCheckBox("Son görüntü -> ilk görüntü eşleştir (wrap)")
        self.chk_wrap.setChecked(True)
        l.addWidget(self.chk_wrap, 3, 0, 1, 2)

        self.chk_joblib = QCheckBox("Feature extraction çok çekirdek (joblib varsa)")
        self.chk_joblib.setChecked(True)
        l.addWidget(self.chk_joblib, 4, 0, 1, 2)

        # BG remove
        self.chk_bg = QCheckBox("Arkaplan temizleme kullan")
        self.chk_bg.setChecked(True)
        l.addWidget(self.chk_bg, 5, 0, 1, 2)

        l.addWidget(QLabel("Yöntem:"), 6, 0)
        self.cmb_bg = QComboBox()
        self.cmb_bg.addItems([GrabCutFast.name, RembgRemove.name])
        self.cmb_bg.setCurrentText(GrabCutFast.name)
        l.addWidget(self.cmb_bg, 6, 1)

        g.setLayout(l)
        lay.addWidget(g)

        self.btn_start = QPushButton("🚀 3D Pipeline Başlat")
        self.btn_start.setMinimumHeight(48)
        self.btn_start.setEnabled(False)
        self.btn_start.clicked.connect(self.on_start_pipeline)
        lay.addWidget(self.btn_start)

        g2 = QGroupBox("İşlem Durumu")
        l2 = QVBoxLayout()
        self.pb_3d = QProgressBar()
        l2.addWidget(self.pb_3d)
        g2.setLayout(l2)
        lay.addWidget(g2)

        g3 = QGroupBox("Log")
        l3 = QVBoxLayout()
        self.log_3d = QTextEdit()
        self.log_3d.setReadOnly(True)
        l3.addWidget(self.log_3d)
        g3.setLayout(l3)
        lay.addWidget(g3)

        # manual load
        row = QHBoxLayout()
        self.btn_pick = QPushButton("📁 Görüntü Klasörü Seç (manuel)")
        self.btn_pick.clicked.connect(self.on_pick_folder)
        row.addWidget(self.btn_pick)
        lay.addLayout(row)

        return w

    def _tab_viewer(self) -> QWidget:
        w = QWidget()
        lay = QVBoxLayout(w)

        info = QLabel(
            "Model üretildikten sonra buradan görüntüleyebilir veya çıktı klasörünü açabilirsin.\n"
            "Open3D varsa ayrı bir viewer penceresi açılır (UI kilitlenmez)."
        )
        info.setAlignment(Qt.AlignmentFlag.AlignCenter)
        info.setStyleSheet("padding:18px;")
        lay.addWidget(info)

        self.btn_view = QPushButton("👁️ Open3D Viewer Aç")
        self.btn_view.setEnabled(False)
        self.btn_view.clicked.connect(self.on_view_model)
        lay.addWidget(self.btn_view)

        self.btn_out = QPushButton("📂 Çıktı Klasörü Aç")
        self.btn_out.setEnabled(False)
        self.btn_out.clicked.connect(self.on_open_out)
        lay.addWidget(self.btn_out)

        self.txt_info = QTextEdit()
        self.txt_info.setReadOnly(True)
        self.txt_info.setPlaceholderText("Model bilgisi burada…")
        lay.addWidget(self.txt_info)

        return w

    def _tab_help(self) -> QWidget:
        w = QWidget()
        lay = QVBoxLayout(w)
        txt = QTextEdit()
        txt.setReadOnly(True)
        txt.setHtml("""
        <h2 style="color:#38bdf8;">AntaresStudio - Notlar</h2>
        <ul>
          <li><b>ESP32 endpointleri:</b> /360_list ve /360_SESSION_INDEX.jpg</li>
          <li><b>Session ID</b> ESP32 tarafında <i>millis()</i> olduğundan tarih gibi gösterilmez.</li>
          <li><b>Arkaplan temizleme:</b> Varsayılan GrabCut hızlıdır. rembg opsiyoneldir.</li>
          <li><b>Kalite:</b> quality -> SIFT varsa; speed -> ORB; balanced -> SIFT yoksa AKAZE.</li>
          <li><b>Gerçek fotogrametri kalitesi</b> için COLMAP önerilir. Bu pipeline hafif SfM’dır.</li>
        </ul>
        """)
        lay.addWidget(txt)
        return w

    # ---------------- UI helpers ----------------
    def ui_log(self, box: QTextEdit, msg: str) -> None:
        box.append(msg)
        box.ensureCursorVisible()

    def show_error(self, title: str, message: str, details: str = "") -> None:
        if details:
            message = f"{message}\n\nDetay:\n{details}"
        QMessageBox.warning(self, title, message)

    # ---------------- Actions ----------------
    def on_ping(self):
        ip = self.txt_ip.text().strip()
        self.ui_log(self.log_dl, f"🔌 Ping: {ip}")
        try:
            Esp32Client(ip).ping()
            QMessageBox.information(self, "OK", f"ESP32 erişilebilir: {ip}")
        except UserFacingError as e:
            self.show_error(e.title, e.message, e.details or e.hint)

    def on_refresh_scans(self):
        ip = self.txt_ip.text().strip()
        self.list_scans.clear()
        self.ui_log(self.log_dl, f"🔄 Liste alınıyor: {ip}/360_list")
        try:
            data = Esp32Client(ip).get_scan_list()
            if not data:
                self.ui_log(self.log_dl, "⚠️ Tarama yok (veya SD boş).")
                return
            # NOT: session_id millis -> tarih üretme yok
            for sid, cnt in data.items():
                self.list_scans.addItem(f"Session: {sid} | 📸 {cnt}")
            self.ui_log(self.log_dl, f"✅ {len(data)} session bulundu")
        except UserFacingError as e:
            self.show_error(e.title, e.message, e.details or e.hint)

    def on_download(self):
        item = self.list_scans.currentItem()
        if not item:
            QMessageBox.information(self, "Seçim Yok", "Lütfen listeden bir session seç.")
            return
        ip = self.txt_ip.text().strip()

        # parse: "Session: <sid> | 📸 <cnt>"
        text = item.text()
        try:
            sid = text.split("Session:")[1].split("|")[0].strip()
            cnt = int(text.split("📸")[1].strip())
        except Exception:
            self.show_error("Parse Hatası", f"Liste satırı çözümlenemedi:\n{text}")
            return

        out_dir = os.path.join(get_data_root(), "antares_3d_data", f"scan_{sid}")
        ensure_dir(out_dir)
        self.current_out_dir = out_dir

        self.pb_dl.setValue(0)
        self.lbl_dl.setText("Durum: İndiriliyor…")
        self.btn_download.setEnabled(False)
        self.btn_refresh.setEnabled(False)

        self.log_dl.clear()
        self.ui_log(self.log_dl, f"📁 Hedef: {out_dir}")

        worker = DownloadWorker(ip, sid, cnt, out_dir, concurrency=self.spn_conc.value())
        worker.signals.progress.connect(self.pb_dl.setValue)
        worker.signals.log.connect(lambda s: self.ui_log(self.log_dl, s))
        worker.signals.error.connect(lambda t, m, d: self._on_worker_error("Download", t, m, d))
        worker.signals.result.connect(self._on_download_done)
        worker.signals.finished.connect(lambda: self._unlock_download())

        self.pool.start(worker)

    def _unlock_download(self):
        self.btn_download.setEnabled(True)
        self.btn_refresh.setEnabled(True)

    def _on_download_done(self, files_obj):
        files = list(files_obj or [])
        self.downloaded_images = files
        if len(files) >= 8:
            self.lbl_dl.setText(f"Durum: ✅ {len(files)} indirildi")
            self.btn_start.setEnabled(True)
            QMessageBox.information(self, "İndirme OK", f"{len(files)} foto indirildi.\nPipeline’a geçebilirsin.")
            self.tabs.setCurrentIndex(1)
        else:
            self.lbl_dl.setText(f"Durum: ❌ Yetersiz ({len(files)}/8)")
            QMessageBox.warning(self, "Eksik Foto", f"En az 8 foto gerekli. İndirilen: {len(files)}")

    def on_pick_folder(self):
        folder = QFileDialog.getExistingDirectory(self, "Görüntü Klasörü Seç")
        if not folder:
            return
        # jpg/png topla
        exts = (".jpg", ".jpeg", ".png")
        imgs = [os.path.join(folder, f) for f in sorted(os.listdir(folder)) if f.lower().endswith(exts)]
        self.downloaded_images = imgs
        self.current_out_dir = os.path.join(folder, "3d_output")
        self.ui_log(self.log_3d, f"📁 Manuel klasör seçildi: {folder}")
        self.ui_log(self.log_3d, f"📸 Bulunan görüntü: {len(imgs)}")
        self.btn_start.setEnabled(len(imgs) >= 8)

    def on_start_pipeline(self):
        if len(self.downloaded_images) < 8:
            QMessageBox.warning(self, "Yetersiz", "Pipeline için en az 8 görüntü gerekli.")
            return
        self.btn_start.setEnabled(False)
        self.pb_3d.setValue(0)
        self.log_3d.clear()
        self.ui_log(self.log_3d, "🚀 Pipeline başlıyor…")

        base_dir = os.path.dirname(self.downloaded_images[0])
        out_dir = os.path.join(base_dir, "3d_output")
        self.current_out_dir = out_dir

        images_to_use = self.downloaded_images

        # 1) BG remove (optional)
        if self.chk_bg.isChecked():
            clean_dir = os.path.join(base_dir, "cleaned")
            try:
                strat: BackgroundRemovalStrategy
                if self.cmb_bg.currentText() == RembgRemove.name:
                    strat = RembgRemove()
                else:
                    strat = GrabCutFast()
            except UserFacingError as e:
                # fallback to GrabCut
                self.ui_log(self.log_3d, f"⚠️ rembg yok -> GrabCut’a düşüyorum. ({e.hint})")
                strat = GrabCutFast()

            w = BackgroundRemoveWorker(images_to_use, clean_dir, strat)
            w.signals.progress.connect(self.pb_3d.setValue)
            w.signals.log.connect(lambda s: self.ui_log(self.log_3d, s))
            w.signals.error.connect(lambda t, m, d: self._on_worker_error("BG", t, m, d))
            w.signals.result.connect(self._on_bg_done)
            w.signals.finished.connect(lambda: None)
            self.pool.start(w)
        else:
            # directly 3D
            self._start_reconstruction(images_to_use)

    def _on_bg_done(self, processed_obj):
        processed = list(processed_obj or [])
        if len(processed) >= 8:
            self.processed_images = processed
            self.ui_log(self.log_3d, f"✅ Arkaplan temizleme tamam: {len(processed)}")
            self._start_reconstruction(processed)
        else:
            self.ui_log(self.log_3d, "⚠️ Arkaplan temizleme eksik, orijinal görüntülerle devam.")
            self._start_reconstruction(self.downloaded_images)

    def _start_reconstruction(self, images: List[str]):
        mode = self.cmb_mode.currentText()
        nfeat = self.spn_feat.value()
        minm = self.spn_matches.value()
        wrap = self.chk_wrap.isChecked()
        joblib_on = self.chk_joblib.isChecked()

        w = ReconstructionWorker(
            image_paths=images,
            out_dir=self.current_out_dir or os.path.join(os.getcwd(), "antares_3d_data", "3d_output"),
            mode=mode,
            nfeatures=nfeat,
            min_matches=minm,
            wrap_match=wrap,
            use_joblib=joblib_on
        )
        w.signals.progress.connect(self.pb_3d.setValue)
        w.signals.log.connect(lambda s: self.ui_log(self.log_3d, s))
        w.signals.error.connect(lambda t, m, d: self._on_worker_error("3D", t, m, d))
        w.signals.result.connect(self._on_3d_done)
        w.signals.finished.connect(lambda: self.btn_start.setEnabled(True))

        self.pool.start(w)

    def _on_3d_done(self, out_obj):
        out_path = str(out_obj or "")
        self.output_model = out_path if out_path and os.path.exists(out_path) else None

        if self.output_model:
            self.btn_view.setEnabled(True)
            self.btn_out.setEnabled(True)
            size_mb = os.path.getsize(self.output_model) / (1024 * 1024)
            self.txt_info.setText(
                f"✅ Çıktı: {self.output_model}\n"
                f"📦 Boyut: {size_mb:.2f} MB\n"
                f"📁 Klasör: {os.path.dirname(self.output_model)}\n"
            )
            QMessageBox.information(self, "Başarılı", "3D çıktı üretildi. Viewer sekmesine geçebilirsin.")
            self.tabs.setCurrentIndex(2)
        else:
            QMessageBox.warning(self, "Başarısız", "3D çıktı üretilemedi. Logları kontrol et.")

    def _on_worker_error(self, stage: str, title: str, message: str, details: str):
        self.ui_log(self.log_3d if stage != "Download" else self.log_dl, f"❌ {title}: {message}")
        self.show_error(title, message, details)
        self.btn_start.setEnabled(True)

    def on_view_model(self):
        if not self.output_model or not os.path.exists(self.output_model):
            return

        # Open3D viewer'ı ayrı process olarak aç
        try:
            p = subprocess.Popen([sys.executable, __file__, "--viewer", self.output_model])
            self.ui_log(self.log_3d, f"👁️ Viewer process başlatıldı (pid={p.pid})")
        except Exception:
            # fallback: default OS open
            try:
                if sys.platform.startswith("win"):
                    os.startfile(self.output_model)  # type: ignore[attr-defined]
                else:
                    subprocess.run(["xdg-open", self.output_model], check=False)
            except Exception as e:
                self.show_error("Viewer Hatası", "Model açılamadı.", str(e))

    def on_open_out(self):
        if not self.output_model:
            return
        open_in_file_manager(os.path.dirname(self.output_model))


# ========================= Entry =========================
def main():
    # viewer mode
    if "--viewer" in sys.argv:
        try:
            idx = sys.argv.index("--viewer")
            model = sys.argv[idx + 1]
        except Exception:
            return 2
        return run_viewer(model)

    app = QApplication(sys.argv)
    apply_dark_industrial_theme(app)
    win = AntaresStudio()
    win.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
