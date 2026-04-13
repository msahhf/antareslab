import os
from fastapi import APIRouter, HTTPException, BackgroundTasks
from pydantic import BaseModel
from typing import List

from services.input_qa import batch_qa_check
from services.image_processing import remove_backgrounds, GrabCutFast, RembgRemove
from services.reconstruction import ReconstructionPipeline
from services.colmap_runner import ColmapRunner

router = APIRouter(prefix="/api/pipeline", tags=["Pipeline"])

class QARequest(BaseModel):
    image_paths: List[str]
    blur_threshold: float = 100.0
    contrast_threshold: float = 20.0

class BgRemovalRequest(BaseModel):
    image_paths: List[str]
    out_dir: str
    method: str = "grabcut" # or "rembg"

class ReconstructionRequest(BaseModel):
    image_paths: List[str]
    out_dir: str
    mode: str = "balanced" # speed, quality, balanced, ultra, dense
    nfeatures: int = 2000
    min_matches: int = 50

@router.post("/qa")
async def check_quality(req: QARequest):
    """Checks blur and contrast for a batch of images."""
    try:
        results = batch_qa_check(req.image_paths, req.blur_threshold, req.contrast_threshold)
        return {"status": "success", "data": results}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

def _bg_removal_task(image_paths: List[str], out_dir: str, method: str):
    try:
        strategy = RembgRemove() if method.lower() == "rembg" else GrabCutFast()
        print(f"Starting background removal using {strategy.name} on {len(image_paths)} images")
        remove_backgrounds(image_paths, out_dir, strategy)
        print("Background removal completed.")
    except Exception as e:
        print(f"Background removal failed: {e}")

@router.post("/remove-bg")
async def start_bg_removal(req: BgRemovalRequest, background_tasks: BackgroundTasks):
    """Removes background from images (runs in background)."""
    background_tasks.add_task(_bg_removal_task, req.image_paths, req.out_dir, req.method)
    return {"status": "accepted", "message": f"Background removal started with {req.method}."}

def _reconstruction_task(req: ReconstructionRequest):
    try:
        print(f"Starting 3D Reconstruction out_dir={req.out_dir} mode={req.mode}")
        if req.mode.lower() == "dense":
            runner = ColmapRunner(
                image_dir=os.path.dirname(req.image_paths[0]) if req.image_paths else "",
                workspace_dir=req.out_dir
            )
            res = runner.run_pipeline()
            print(f"COLMAP Dense Reconstruction finished. Model at: {res.get('mesh')}")
        else:
            pipeline = ReconstructionPipeline(
                image_paths=req.image_paths,
                out_dir=req.out_dir,
                mode=req.mode,
                nfeatures=req.nfeatures,
                min_matches=req.min_matches
            )
            res = pipeline.run()
            print(f"3D Reconstruction finished. Model at: {res.get('model_path')}")
    except Exception as e:
        print(f"3D Reconstruction failed: {e}")

@router.post("/reconstruct")
async def start_reconstruction(req: ReconstructionRequest, background_tasks: BackgroundTasks):
    """Starts the 3D SfM reconstruction process."""
    background_tasks.add_task(_reconstruction_task, req)
    return {"status": "accepted", "message": "3D reconstruction started in the background."}
