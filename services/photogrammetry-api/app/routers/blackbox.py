"""
AntaresStudio IoT - Black Box Router v3.2

Handles black box data upload from ESP32 and serves generated reports.
"""

import logging
from pathlib import Path
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, UploadFile, File, HTTPException, Query
from fastapi.responses import FileResponse, JSONResponse

from app.services.blackbox_service import blackbox_service
from app.websocket_manager import ws_manager

logger = logging.getLogger("antares.blackbox")

router = APIRouter(prefix="/blackbox", tags=["Black Box"])

# Reports directory
REPORTS_DIR = Path("data/reports")
REPORTS_DIR.mkdir(parents=True, exist_ok=True)


@router.post("/upload")
async def upload_blackbox(
    file: UploadFile = File(...),
    mission_name: Optional[str] = Query(default="Capsule Mission", description="Mission name for report")
):
    """
    Receive black box data from ESP32 and generate PDF report.
    
    The ESP32 streams the blackbox.txt file content here when recording stops.
    Backend parses the CSV, computes statistics, and generates Mission_Report.pdf.
    
    Expected file format (CSV):
        timestamp,datetime,temperature,humidity,soil_moisture,heater_power,fan_sly,fan_dz,mode
        12345678,T+00:00:15,25.5,60,512,0,OFF,OFF,AUTO
        ...
    
    Returns:
        {
            "success": true,
            "pdf_path": "data/reports/Mission_Report_20240115_143022.pdf",
            "pdf_url": "/api/v1/blackbox/reports/Mission_Report_20240115_143022.pdf",
            "statistics": {...},
            "message": "Report generated successfully"
        }
    """
    try:
        logger.info(f"Receiving black box upload: {file.filename} ({file.size} bytes)")
        
        # Read uploaded content
        content = await file.read()
        text_content = content.decode('utf-8', errors='ignore')
        
        # Save raw data for reference
        raw_path = blackbox_service.save_raw_data(text_content)
        logger.info(f"Raw data saved: {raw_path}")
        
        # Parse telemetry readings
        readings = blackbox_service.parse_blackbox_data(text_content)
        
        if not readings:
            logger.warning("No valid telemetry readings found in upload")
            return JSONResponse(
                status_code=400,
                content={
                    "success": False,
                    "message": "No valid telemetry data found in file",
                    "raw_saved": str(raw_path)
                }
            )
        
        logger.info(f"Parsed {len(readings)} telemetry readings")
        
        # Compute statistics
        stats = blackbox_service.compute_statistics(readings)
        
        # Generate PDF report
        pdf_path, pdf_filename = blackbox_service.generate_pdf_report(readings, mission_name)
        
        # Construct download URL
        pdf_url = f"/api/v1/blackbox/reports/{pdf_filename}"
        
        logger.info(f"✅ Black box report generated: {pdf_filename}")
        
        # Broadcast to WebSocket clients
        await ws_manager.broadcast_logs({
            "message": f"Mission report generated: {pdf_filename}",
            "level": "SUCCESS",
            "timestamp": datetime.now().isoformat(),
            "pdf_url": pdf_url,
            "readings_count": len(readings)
        })
        
        return {
            "success": True,
            "pdf_path": str(pdf_path),
            "pdf_url": pdf_url,
            "pdf_filename": pdf_filename,
            "raw_data_path": str(raw_path),
            "statistics": {
                "duration_seconds": stats.duration_seconds,
                "reading_count": stats.reading_count,
                "avg_temperature": round(stats.avg_temperature, 2),
                "min_temperature": round(stats.min_temperature, 2),
                "max_temperature": round(stats.max_temperature, 2),
                "avg_humidity": round(stats.avg_humidity, 2),
                "min_humidity": stats.min_humidity,
                "max_humidity": stats.max_humidity,
                "heater_on_percent": round(stats.heater_on_percent, 1),
                "fan_sly_on_percent": round(stats.fan_sly_on_percent, 1),
                "fan_dz_on_percent": round(stats.fan_dz_on_percent, 1),
            },
            "message": "Mission report generated successfully"
        }
    
    except Exception as e:
        logger.error(f"Black box upload error: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Failed to process black box: {str(e)}")


@router.get("/reports/list")
async def list_reports():
    """
    List all generated mission reports.
    
    Returns:
        List of report files with metadata
    """
    try:
        reports = []
        
        for pdf_file in sorted(REPORTS_DIR.glob("Mission_Report_*.pdf"), reverse=True):
            stat = pdf_file.stat()
            reports.append({
                "filename": pdf_file.name,
                "url": f"/api/v1/blackbox/reports/{pdf_file.name}",
                "size_bytes": stat.st_size,
                "created": datetime.fromtimestamp(stat.st_mtime).isoformat(),
            })
        
        return {
            "reports": reports,
            "count": len(reports),
            "reports_dir": str(REPORTS_DIR)
        }
    
    except Exception as e:
        logger.error(f"Error listing reports: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/reports/{filename}")
async def download_report(filename: str):
    """
    Download a generated mission report PDF.
    
    Args:
        filename: The PDF filename (e.g., Mission_Report_20240115_143022.pdf)
    
    Returns:
        PDF file as FileResponse
    """
    # Security: prevent directory traversal
    if ".." in filename or "/" in filename or "\\" in filename:
        raise HTTPException(status_code=400, detail="Invalid filename")
    
    pdf_path = REPORTS_DIR / filename
    
    if not pdf_path.exists():
        raise HTTPException(status_code=404, detail=f"Report not found: {filename}")
    
    return FileResponse(
        path=str(pdf_path),
        media_type="application/pdf",
        filename=filename
    )


@router.get("/reports/latest")
async def download_latest_report():
    """
    Download the most recent mission report.
    
    Useful for the Flutter app to get the latest report after recording stops.
    """
    try:
        pdfs = sorted(REPORTS_DIR.glob("Mission_Report_*.pdf"), reverse=True)
        
        if not pdfs:
            raise HTTPException(status_code=404, detail="No reports available")
        
        latest = pdfs[0]
        
        return FileResponse(
            path=str(latest),
            media_type="application/pdf",
            filename=latest.name
        )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting latest report: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/reports/{filename}")
async def delete_report(filename: str):
    """
    Delete a specific report.
    
    Args:
        filename: The PDF filename to delete
    
    Returns:
        Success confirmation
    """
    # Security check
    if ".." in filename or "/" in filename or "\\" in filename:
        raise HTTPException(status_code=400, detail="Invalid filename")
    
    pdf_path = REPORTS_DIR / filename
    
    if not pdf_path.exists():
        raise HTTPException(status_code=404, detail=f"Report not found: {filename}")
    
    try:
        pdf_path.unlink()
        logger.info(f"Deleted report: {filename}")
        return {"success": True, "message": f"Report {filename} deleted"}
    except Exception as e:
        logger.error(f"Error deleting report: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/stats")
async def get_blackbox_stats():
    """
    Get overall black box statistics.
    
    Returns:
        Total missions, total readings, etc.
    """
    try:
        reports = list(REPORTS_DIR.glob("Mission_Report_*.pdf"))
        raw_files = list(REPORTS_DIR.glob("blackbox_raw_*.txt"))
        
        return {
            "total_missions": len(reports),
            "total_raw_files": len(raw_files),
            "reports_dir": str(REPORTS_DIR),
            "disk_usage_mb": sum(f.stat().st_size for f in reports) / (1024 * 1024)
        }
    
    except Exception as e:
        logger.error(f"Error getting stats: {e}")
        raise HTTPException(status_code=500, detail=str(e))
