from fastapi import APIRouter, Request
from sse_starlette.sse import EventSourceResponse
from services.progress import progress_manager
import asyncio
import json

router = APIRouter(prefix="/api/events", tags=["SSE Events"])

@router.get("/{job_id}/progress")
async def progress_stream(job_id: str, request: Request):
    """
    Server-Sent Events endpoint to track job progress.
    """
    async def event_generator():
        queue = progress_manager.get_or_create_queue(job_id)
        
        # Send initial state
        initial_state = progress_manager.get_job_state(job_id)
        yield {
            "event": "message",
            "id": job_id,
            "data": json.dumps(initial_state)
        }

        while True:
            # If client closes connection, stop sending events
            if await request.is_disconnected():
                break

            try:
                # Wait for a new update for this job
                data = await asyncio.wait_for(queue.get(), timeout=2.0)
                yield {
                    "event": "message",
                    "id": job_id,
                    "data": json.dumps(data)
                }
                
                # Close stream if job is done or failed
                if data.get("progress") == 100 or "error" in data.get("status", "").lower():
                    break
            except asyncio.TimeoutError:
                # Send a keep-alive ping
                yield {
                    "event": "ping",
                    "data": "keep-alive"
                }

    return EventSourceResponse(event_generator())
