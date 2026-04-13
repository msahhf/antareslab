import asyncio
from typing import Dict, Any

class ProgressManager:
    """Manages Server-Sent Events (SSE) progress tracking for long-running jobs."""
    def __init__(self):
        self.jobs: Dict[str, Dict[str, Any]] = {}
        # Allows awaiting on new updates
        self._queues: Dict[str, asyncio.Queue] = {}

    def get_or_create_queue(self, job_id: str) -> asyncio.Queue:
        if job_id not in self._queues:
            self._queues[job_id] = asyncio.Queue()
        return self._queues[job_id]

    async def update_job(self, job_id: str, progress: int, status: str, details: str = ""):
        update_data = {"progress": progress, "status": status, "details": details}
        self.jobs[job_id] = update_data
        
        # In a real async environment we put the payload in the queue
        if job_id in self._queues:
            await self._queues[job_id].put(update_data)

    def get_job_state(self, job_id: str) -> Dict[str, Any]:
        return self.jobs.get(job_id, {"progress": 0, "status": "unknown"})

progress_manager = ProgressManager()
