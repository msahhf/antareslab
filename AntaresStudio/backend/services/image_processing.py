import cv2
import numpy as np
import os
import gc

class BackgroundRemovalStrategy:
    name: str = "base"
    def process(self, img_path: str, out_path: str) -> None:
        raise NotImplementedError

class GrabCutFast(BackgroundRemovalStrategy):
    name = "GrabCut (Hızlı)"

    def process(self, img_path: str, out_path: str) -> None:
        img = cv2.imread(img_path)
        if img is None:
            raise RuntimeError(f"Görüntü okunamadı: {img_path}")
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
            raise RuntimeError(f"rembg yüklenemedi: {e}")
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

def remove_backgrounds(image_paths: list[str], out_dir: str, strategy: BackgroundRemovalStrategy) -> list[str]:
    """
    Applies the specified background removal strategy to a list of images.
    Returns the list of processed file paths.
    """
    os.makedirs(out_dir, exist_ok=True)
    processed = []
    
    for p in image_paths:
        base = os.path.splitext(os.path.basename(p))[0]
        out_path = os.path.join(out_dir, f"{base}_clean.png")
        strategy.process(p, out_path)
        processed.append(out_path)
        
    return processed
