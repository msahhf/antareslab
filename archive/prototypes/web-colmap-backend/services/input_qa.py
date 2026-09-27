import cv2
import numpy as np

class InputQAError(Exception):
    pass

def check_image_quality(img_path: str, blur_threshold: float = 100.0, contrast_threshold: float = 20.0) -> dict:
    """
    Checks if the image at img_path is blurry or lacks contrast.
    Returns a dict with 'passed' (bool), and metrics.
    """
    img = cv2.imread(img_path, cv2.IMREAD_GRAYSCALE)
    if img is None:
        raise InputQAError(f"Could not read image: {img_path}")
        
    # Blur check using variance of Laplacian
    laplacian_var = cv2.Laplacian(img, cv2.CV_64F).var()
    is_blurry = laplacian_var < blur_threshold
    
    # Contrast check using standard deviation of pixel intensities
    std_dev = img.std()
    is_low_contrast = std_dev < contrast_threshold
    
    return {
        "passed": not is_blurry and not is_low_contrast,
        "is_blurry": bool(is_blurry),
        "blur_score": float(laplacian_var),
        "is_low_contrast": bool(is_low_contrast),
        "contrast_score": float(std_dev)
    }

def batch_qa_check(image_paths: list[str], blur_threshold: float = 100.0, contrast_threshold: float = 20.0) -> dict:
    """
    Runs QA checks on a batch of images and separates them into passed and failed lists.
    """
    results = {
        "passed_images": [],
        "failed_images": [],
        "details": {}
    }
    
    for path in image_paths:
        try:
            qa_res = check_image_quality(path, blur_threshold, contrast_threshold)
            results["details"][path] = qa_res
            if qa_res["passed"]:
                results["passed_images"].append(path)
            else:
                results["failed_images"].append(path)
        except Exception as e:
            results["details"][path] = {"passed": False, "error": str(e)}
            results["failed_images"].append(path)
            
    return results
