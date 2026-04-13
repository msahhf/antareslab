import os
import cv2
import numpy as np
import traceback
from typing import List, Tuple, Dict, Any
from dataclasses import dataclass

def safe_float32(des: np.ndarray) -> np.ndarray:
    if des is None:
        return des
    if des.dtype != np.float32:
        return des.astype(np.float32, copy=False)
    return des

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
    def create(self, nfeatures: int): return cv2.SIFT_create(nfeatures=nfeatures)

class AKAZEExtractor(FeatureExtractorStrategy):
    name = "AKAZE"
    norm = cv2.NORM_HAMMING
    def create(self, nfeatures: int): return cv2.AKAZE_create()

class ORBExtractor(FeatureExtractorStrategy):
    name = "ORB"
    norm = cv2.NORM_HAMMING
    def create(self, nfeatures: int): return cv2.ORB_create(nfeatures=nfeatures)

class KorniaSuperPointExtractor(FeatureExtractorStrategy):
    name = "SuperPoint"
    norm = cv2.NORM_L2

    def detect(self, img_bgr: np.ndarray, nfeatures: int) -> Tuple[np.ndarray, np.ndarray]:
        try:
            import torch
            import kornia
        except ImportError:
            raise RuntimeError("kornia or torch not installed. Cannot use SuperPoint.")
        
        device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        # Kornia SuperPoint returns a tuple of (keypoints, scores, descriptors)
        # where keypoints is (B, N, 2), descriptors is (B, 256, N)
        model = kornia.feature.SuperPoint(True).eval().to(device)
        
        img_rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
        tensor = kornia.utils.image_to_tensor(img_rgb, keepdim=False).float() / 255.0
        gray = kornia.color.rgb_to_grayscale(tensor).to(device)
        
        with torch.no_grad():
            from kornia.feature.laf import extract_patches_from_pyramid
            # For simplicity, we can use kornia's ScaleSpaceDetector with SuperPoint if needed
            # Or just use the model directly
            out = model(gray)
            
        if isinstance(out, tuple) and len(out) >= 3:
            kps, _, descs = out[0], out[1], out[2] 
            # kps: (1, N, 2)
            # descs: (1, 256, N)
            xy = kps.squeeze(0).cpu().numpy()
            des = descs.squeeze(0).transpose(0, 1).cpu().numpy() # [N, 256]
            # Limit features
            if xy.shape[0] > nfeatures:
                xy = xy[:nfeatures]
                des = des[:nfeatures]
            return xy.astype(np.float32), des.astype(np.float32)
        else:
            return np.empty((0, 2), np.float32), np.empty((0, 1), np.float32)

def choose_feature_strategy(mode: str) -> FeatureExtractorStrategy:
    mode = mode.lower().strip()
    if mode == "ultra":
        try:
            return KorniaSuperPointExtractor()
        except:
            return SIFTExtractor()
    if mode == "speed": return ORBExtractor()
    if mode == "quality":
        try:
            cv2.SIFT_create()
            return SIFTExtractor()
        except:
            return AKAZEExtractor()
    try:
        cv2.SIFT_create()
        return SIFTExtractor()
    except:
        return AKAZEExtractor()

class ReconstructionPipeline:
    def __init__(
        self,
        image_paths: List[str],
        out_dir: str,
        mode: str = "balanced",
        nfeatures: int = 2000,
        min_matches: int = 50,
        wrap_match: bool = True,
        use_joblib: bool = True,
    ):
        self.image_paths = image_paths
        self.out_dir = out_dir
        self.mode = mode
        self.nfeatures = int(nfeatures)
        self.min_matches = int(min_matches)
        self.wrap_match = bool(wrap_match)
        self.use_joblib = bool(use_joblib)
        os.makedirs(self.out_dir, exist_ok=True)

    def log(self, msg: str):
        print(f"[3D Pipeline] {msg}")

    def run(self) -> Dict[str, Any]:
        """Runs the pipeline and returns the paths to the generated files."""
        if len(self.image_paths) < 8:
            raise ValueError(f"En az 8 görüntü gerekiyor. Şu an: {len(self.image_paths)}")

        imgs = []
        for p in self.image_paths:
            img = cv2.imread(p)
            if img is not None: imgs.append((p, img))
                
        if len(imgs) < 8:
            raise ValueError("Görüntüler okunurken eksikler oldu, yeterli resim yok.")

        strat = choose_feature_strategy(self.mode)
        self.log(f"Feature: {strat.name} | nfeatures={self.nfeatures}")
        feats = self._extract_features(imgs, strat)
        
        if sum(fp.xy.shape[0] for fp in feats) == 0:
            raise ValueError("Özellik (feature) bulunamadı.")

        matches = self._match_adjacent(feats)
        if len(matches) < 2:
            raise ValueError("Yeterli eşleşen görüntü çifti yok.")

        poses, K = self._estimate_pose_chain(imgs, feats, matches)
        if len(poses) < 2:
            raise ValueError("Kamera pozları çıkarılamadı.")

        pts, cols = self._triangulate_sparse(imgs, feats, matches, poses, K)
        if pts.shape[0] < 100:
            raise ValueError(f"Çok az 3D nokta oluştu: {pts.shape[0]}")

        self.log(f"Sparse points: {pts.shape[0]}")
        mesh_path = self._export_outputs(pts, cols, self.out_dir)
        
        return {"status": "success", "model_path": mesh_path, "points": pts.shape[0]}

    def _extract_features(self, imgs: List[Tuple[str, np.ndarray]], strat: FeatureExtractorStrategy) -> List[FeaturePack]:
        paths = [p for p, _ in imgs]
        def _one(path: str) -> FeaturePack:
            img = cv2.imread(path)
            if img is None:
                return FeaturePack(path, np.empty((0, 2), np.float32), np.empty((0, 1), np.float32), strat.norm, strat.name)
            xy, des = strat.detect(img, self.nfeatures)
            if strat.norm == cv2.NORM_L2:
                des = safe_float32(des)
            return FeaturePack(path, xy, des, strat.norm, strat.name)

        feats: List[FeaturePack] = []
        if self.use_joblib:
            try:
                from joblib import Parallel, delayed
                feats = Parallel(n_jobs=-1, prefer="threads")(delayed(_one)(p) for p in paths)
            except:
                feats = [_one(p) for p in paths]
        else:
            feats = [_one(p) for p in paths]
        return feats

    def _make_matcher(self, norm: int, algo: str):
        if norm == cv2.NORM_L2:
            return cv2.FlannBasedMatcher(dict(algorithm=1, trees=5), dict(checks=50)), True
        return cv2.BFMatcher(norm, crossCheck=False), False

    def _match_pair(self, a: FeaturePack, b: FeaturePack) -> List[cv2.DMatch]:
        if a.des is None or b.des is None or len(a.des) == 0 or len(b.des) == 0:
            return []
            
        if a.algo == "SuperPoint":
            # Use LightGlue via Kornia if available
            try:
                import torch
                from kornia.feature import LightGlueMatcher
                device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
                lg = LightGlueMatcher("superpoint").eval().to(device)
                
                # Descriptors are (N, 256) -> need to be (1, N, 256)
                des1 = torch.from_numpy(a.des).unsqueeze(0).to(device)
                des2 = torch.from_numpy(b.des).unsqueeze(0).to(device)
                # Feature points are (N, 2)
                lafs1 = torch.from_numpy(a.xy).unsqueeze(0).to(device)
                lafs2 = torch.from_numpy(b.xy).unsqueeze(0).to(device)
                
                # LightGlue requires specific input dict format depending on kornia version, 
                # or just use it raw. For safety and cross-version, simple fallback to NN match if LG fails
                with torch.no_grad():
                    # Kornia Lightglue matcher input varies, usually:
                    # lg(desc1, desc2, lafs1, lafs2)
                    dists, idxs = lg(des1, des2, lafs1, lafs2) 
                    
                idxs_cpu = idxs.cpu().numpy()
                good = []
                for k in range(idxs_cpu.shape[0] if len(idxs_cpu.shape)==2 else 0):
                    m = cv2.DMatch()
                    m.queryIdx = int(idxs_cpu[k, 0])
                    m.trainIdx = int(idxs_cpu[k, 1])
                    m.distance = 0.0 # LightGlue returns matches direct
                    good.append(m)
                if len(good) > 0:
                    return good
            except Exception as e:
                self.log(f"LightGlue error: {e}, falling back to FLANN")
                pass

        matcher, _ = self._make_matcher(a.norm, a.algo)
        des1, des2 = a.des, b.des
        if a.norm == cv2.NORM_L2:
            des1, des2 = safe_float32(des1), safe_float32(des2)
        try:
            knn = matcher.knnMatch(des1, des2, k=2)
            good = [m for pair in knn if len(pair) >= 2 for m, n in [pair] if m.distance < 0.75 * n.distance]
            return good
        except:
            return []

    def _match_adjacent(self, feats: List[FeaturePack]) -> List[Tuple[int, int, List[cv2.DMatch]]]:
        matches = []
        n = len(feats)
        pairs = [(i, i + 1) for i in range(n - 1)]
        if self.wrap_match and n >= 3: pairs.append((n - 1, 0))

        for i, j in pairs:
            good = self._match_pair(feats[i], feats[j])
            if len(good) >= self.min_matches:
                matches.append((i, j, good))
        return matches

    def _estimate_pose_chain(self, imgs, feats, matches):
        first_img = imgs[0][1]
        h, w = first_img.shape[:2]
        f = max(w, h) * 1.2
        K = np.array([[f, 0, w / 2], [0, f, h / 2], [0, 0, 1]], dtype=np.float64)
        poses = {0: (np.eye(3), np.zeros((3, 1), np.float64))}
        match_map = {(i, j): ms for i, j, ms in matches}

        for j in range(1, len(feats)):
            i = j - 1
            if (i, j) not in match_map: continue
            ms = match_map[(i, j)]
            pts1 = np.float32([feats[i].xy[m.queryIdx] for m in ms])
            pts2 = np.float32([feats[j].xy[m.trainIdx] for m in ms])

            E, mask = cv2.findEssentialMat(pts1, pts2, K, method=cv2.RANSAC, prob=0.999, threshold=2.0)
            if E is None: continue
            _, R_rel, t_rel, _ = cv2.recoverPose(E, pts1, pts2, K)

            if i in poses:
                R_i, t_i = poses[i]
                poses[j] = (R_rel @ R_i, R_rel @ t_i + t_rel)

        return poses, K

    def _triangulate_sparse(self, imgs, feats, matches, poses, K):
        pts_all, col_all = [], []
        for (i, j, ms) in matches:
            if i not in poses or j not in poses: continue
            R_i, t_i = poses[i]
            R_j, t_j = poses[j]
            P1 = K @ np.hstack([R_i, t_i])
            P2 = K @ np.hstack([R_j, t_j])

            pts1 = np.float32([feats[i].xy[m.queryIdx] for m in ms])
            pts2 = np.float32([feats[j].xy[m.trainIdx] for m in ms])

            X4 = cv2.triangulatePoints(P1, P2, pts1.T, pts2.T)
            X = (X4[:3] / (X4[3] + 1e-9)).T

            img_i = imgs[i][1]
            for k, uv in enumerate(pts1):
                x, y = int(uv[0]), int(uv[1])
                if 0 <= x < img_i.shape[1] and 0 <= y < img_i.shape[0]:
                    rgb = (img_i[y, x].astype(np.float32) / 255.0)[::-1]
                else:
                    rgb = np.array([0.8, 0.8, 0.8], np.float32)
                pts_all.append(X[k])
                col_all.append(rgb)

        pts, cols = np.asarray(pts_all, dtype=np.float64), np.asarray(col_all, dtype=np.float64)
        m = np.isfinite(pts).all(axis=1)
        pts, cols = pts[m], cols[m]
        if pts.shape[0] > 0:
            center = np.median(pts, axis=0)
            dist = np.linalg.norm(pts - center, axis=1)
            keep = dist < np.quantile(dist, 0.98)
            pts, cols = pts[keep], cols[keep]
        return pts, cols

    def _export_outputs(self, pts: np.ndarray, cols: np.ndarray, out_dir: str) -> str:
        ply_pc = os.path.join(out_dir, "point_cloud.ply")
        with open(ply_pc, "w", encoding="utf-8") as f:
            f.write(f"ply\nformat ascii 1.0\nelement vertex {pts.shape[0]}\n")
            f.write("property float x\nproperty float y\nproperty float z\n")
            f.write("property uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n")
            c255 = np.clip(cols * 255.0, 0, 255).astype(np.uint8)
            for p, c in zip(pts, c255):
                f.write(f"{p[0]} {p[1]} {p[2]} {int(c[0])} {int(c[1])} {int(c[2])}\n")

        try:
            import open3d as o3d
            pcd = o3d.geometry.PointCloud()
            pcd.points = o3d.utility.Vector3dVector(pts)
            pcd.colors = o3d.utility.Vector3dVector(cols)
            pcd = pcd.voxel_down_sample(voxel_size=0.003)
            pcd, _ = pcd.remove_statistical_outlier(nb_neighbors=20, std_ratio=2.0)
            pcd.estimate_normals(search_param=o3d.geometry.KDTreeSearchParamHybrid(radius=0.03, max_nn=30))
            pcd.orient_normals_consistent_tangent_plane(50)

            mesh, dens = o3d.geometry.TriangleMesh.create_from_point_cloud_poisson(pcd, depth=8)
            dens = np.asarray(dens)
            mesh.remove_vertices_by_mask(dens < np.quantile(dens, 0.02))
            mesh.remove_degenerate_triangles()
            mesh.remove_duplicated_triangles()
            mesh.remove_duplicated_vertices()
            mesh.remove_non_manifold_edges()
            mesh.compute_vertex_normals()

            mesh_ply = os.path.join(out_dir, "mesh.ply")
            o3d.io.write_triangle_mesh(mesh_ply, mesh)
            o3d.io.write_triangle_mesh(os.path.join(out_dir, "mesh.obj"), mesh)
            o3d.io.write_triangle_mesh(os.path.join(out_dir, "mesh.stl"), mesh)
            return mesh_ply
        except Exception as e:
            self.log(f"Open3D failed: {e}")
            return ply_pc
