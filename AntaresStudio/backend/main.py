from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
from api.esp32_routes import router as esp32_router
from api.pipeline_routes import router as pipeline_router
from api.sse_routes import router as sse_router

app = FastAPI(title="AntaresStudio Web API", version="1.0.0")

# CORS config to allow React/Vite development server
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://localhost:3000"], 
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(esp32_router)
app.include_router(pipeline_router)
app.include_router(sse_router)

@app.get("/")
def root():
    return {"message": "AntaresStudio API is running."}

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
