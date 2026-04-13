import os
import subprocess
import shutil

class ColmapRunner:
    def __init__(self, image_dir: str, workspace_dir: str):
        self.image_dir = image_dir
        self.workspace_dir = workspace_dir
        self.db_path = os.path.join(self.workspace_dir, "database.db")
        self.sparse_dir = os.path.join(self.workspace_dir, "sparse")
        self.dense_dir = os.path.join(self.workspace_dir, "dense")

        os.makedirs(self.workspace_dir, exist_ok=True)
        os.makedirs(self.sparse_dir, exist_ok=True)
        os.makedirs(self.dense_dir, exist_ok=True)

    def _run_cmd(self, cmd: list[str], task_name: str):
        print(f"[COLMAP] Starting: {task_name}")
        try:
            subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
            print(f"[COLMAP] Finished: {task_name}")
        except subprocess.CalledProcessError as e:
            print(f"[COLMAP ERROR] {task_name} failed:")
            print(e.stderr)
            raise RuntimeError(f"COLMAP task {task_name} failed. Check logs.")

    def run_pipeline(self):
        """Runs the standard SfM and MVS COLMAP pipeline for dense reconstruction."""
        # 1. Feature extraction
        self._run_cmd([
            "colmap", "feature_extractor",
            "--database_path", self.db_path,
            "--image_path", self.image_dir
        ], "Feature Extractor")

        # 2. Exhaustive matcher
        self._run_cmd([
            "colmap", "exhaustive_matcher",
            "--database_path", self.db_path
        ], "Exhaustive Matcher")

        # 3. Mapper (Sparse Reconstruction)
        self._run_cmd([
            "colmap", "mapper",
            "--database_path", self.db_path,
            "--image_path", self.image_dir,
            "--output_path", self.sparse_dir
        ], "Mapper (Sparse)")

        # Mapper might output sub-models (0, 1, ...). Check if '0' exists
        model_0_path = os.path.join(self.sparse_dir, "0")
        if not os.path.exists(model_0_path):
            raise RuntimeError("COLMAP failed to create a valid sparse model.")

        # 4. Image undistorter (Pre-MVS)
        self._run_cmd([
            "colmap", "image_undistorter",
            "--image_path", self.image_dir,
            "--input_path", model_0_path,
            "--output_path", self.dense_dir,
            "--output_type", "COLMAP"
        ], "Image Undistorter")

        # 5. Patch Match Stereo (Dense Reconstruction)
        self._run_cmd([
            "colmap", "patch_match_stereo",
            "--workspace_path", self.dense_dir,
            "--workspace_format", "COLMAP",
            "--PatchMatchStereo.geom_consistency", "true",
            "--PatchMatchStereo.max_image_size", "1200" # Reduce for speed
        ], "Patch Match Stereo")

        # 6. Stereo Fusion
        fused_ply = os.path.join(self.dense_dir, "fused.ply")
        self._run_cmd([
            "colmap", "stereo_fusion",
            "--workspace_path", self.dense_dir,
            "--workspace_format", "COLMAP",
            "--input_type", "geometric",
            "--output_path", fused_ply
        ], "Stereo Fusion")

        # 7. Poisson Mesher
        mesh_ply = os.path.join(self.dense_dir, "meshed-poisson.ply")
        self._run_cmd([
            "colmap", "poisson_mesher",
            "--input_path", fused_ply,
            "--output_path", mesh_ply
        ], "Poisson Mesher")

        return {
            "status": "success",
            "point_cloud": fused_ply,
            "mesh": mesh_ply
        }
