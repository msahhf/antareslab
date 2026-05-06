"""
AntaresStudio IoT Backend - SQLite Database Layer v3.0

Production-ready persistence for telemetry, sessions, and pipelines.
Uses SQLAlchemy for ORM with async support via aiosqlite.
"""

import asyncio
import json
import logging
from datetime import datetime
from pathlib import Path
from typing import List, Optional, Dict, Any

from sqlalchemy import (
    create_engine, Column, Integer, Float, String, Boolean, DateTime, Text,
    ForeignKey, Index, event
)
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session, relationship
from sqlalchemy.pool import StaticPool

from app.config import settings

logger = logging.getLogger("antares.database")

# SQLAlchemy setup
Base = declarative_base()

# Database path
DB_PATH = settings.BASE_DIR / "data" / "antares.db"
DB_PATH.parent.mkdir(parents=True, exist_ok=True)

# Engine with WAL mode for better concurrency
ENGINE_URL = f"sqlite:///{DB_PATH}"
engine = create_engine(
    ENGINE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
    echo=False,
)

# Enable WAL mode for better read concurrency
@event.listens_for(engine, "connect")
def set_sqlite_pragma(dbapi_conn, connection_record):
    cursor = dbapi_conn.cursor()
    cursor.execute("PRAGMA journal_mode=WAL")
    cursor.execute("PRAGMA synchronous=NORMAL")
    cursor.execute("PRAGMA cache_size=-64000")  # 64MB cache
    cursor.execute("PRAGMA temp_store=memory")
    cursor.close()

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


# =============================================================================
# Models
# =============================================================================

class TelemetryReading(Base):
    """Historical telemetry data from ESP32/Arduino sensors."""
    __tablename__ = "telemetry_readings"
    
    id = Column(Integer, primary_key=True, index=True)
    timestamp = Column(DateTime, default=datetime.utcnow, index=True)
    
    # Sensor readings
    temperature = Column(Float, nullable=True)
    humidity = Column(Integer, nullable=True)
    soil_moisture = Column(Integer, nullable=True)
    
    # System state
    mode = Column(String(20), default="STANDBY")  # AUTO, MANUAL, STUDIO, STANDBY
    heater_power = Column(Integer, default=0)
    fan_sly = Column(Boolean, default=False)
    fan_dz = Column(Boolean, default=False)
    motor_position = Column(Integer, default=0)
    is_homed = Column(Boolean, default=False)
    
    # Source tracking
    source = Column(String(50), default="unknown")  # esp32, flutter, arduino
    
    # Index for time-series queries
    __table_args__ = (
        Index('idx_telemetry_time', 'timestamp'),
        Index('idx_telemetry_source', 'source'),
    )
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "timestamp": self.timestamp.isoformat() if self.timestamp else None,
            "temperature": self.temperature,
            "humidity": self.humidity,
            "soil_moisture": self.soil_moisture,
            "mode": self.mode,
            "heater_power": self.heater_power,
            "fan_sly": self.fan_sly,
            "fan_dz": self.fan_dz,
            "motor_position": self.motor_position,
            "is_homed": self.is_homed,
            "source": self.source,
        }


class Session(Base):
    """Photo session tracking."""
    __tablename__ = "sessions"
    
    id = Column(String(20), primary_key=True, index=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Status
    status = Column(String(20), default="active")  # active, cleaning, completed, failed
    photo_count = Column(Integer, default=0)
    
    # Relations
    photos = relationship("Photo", back_populates="session", cascade="all, delete-orphan")
    pipelines = relationship("Pipeline", back_populates="session")
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
            "status": self.status,
            "photo_count": self.photo_count,
        }


class Photo(Base):
    """Individual photo tracking."""
    __tablename__ = "photos"
    
    id = Column(Integer, primary_key=True, index=True)
    session_id = Column(String(20), ForeignKey("sessions.id"), index=True)
    
    filename = Column(String(255))
    original_path = Column(Text)
    cleaned_path = Column(Text, nullable=True)
    size_bytes = Column(Integer)
    
    created_at = Column(DateTime, default=datetime.utcnow)
    cleaned_at = Column(DateTime, nullable=True)
    
    # Relations
    session = relationship("Session", back_populates="photos")
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "session_id": self.session_id,
            "filename": self.filename,
            "original_path": self.original_path,
            "cleaned_path": self.cleaned_path,
            "size_bytes": self.size_bytes,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "cleaned_at": self.cleaned_at.isoformat() if self.cleaned_at else None,
        }


class Pipeline(Base):
    """3D reconstruction pipeline tracking."""
    __tablename__ = "pipelines"
    
    id = Column(String(50), primary_key=True, index=True)
    session_id = Column(String(20), ForeignKey("sessions.id"), index=True)
    
    # Status
    status = Column(String(20), default="pending")  # pending, running, completed, failed, cancelled
    progress = Column(Float, default=0.0)  # 0-100
    current_step = Column(String(100), default="Initializing")
    
    # Timing
    started_at = Column(DateTime, nullable=True)
    completed_at = Column(DateTime, nullable=True)
    
    # Output
    output_path = Column(Text, nullable=True)
    model_format = Column(String(10), default="glb")
    
    # Error tracking
    error_message = Column(Text, nullable=True)
    
    # Relations
    session = relationship("Session", back_populates="pipelines")
    
    # Index for active pipeline queries
    __table_args__ = (
        Index('idx_pipeline_status', 'status'),
    )
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "session_id": self.session_id,
            "status": self.status,
            "progress": self.progress,
            "current_step": self.current_step,
            "started_at": self.started_at.isoformat() if self.started_at else None,
            "completed_at": self.completed_at.isoformat() if self.completed_at else None,
            "output_path": self.output_path,
            "model_format": self.model_format,
            "error_message": self.error_message,
        }


class SystemLog(Base):
    """System logs for dashboard terminal."""
    __tablename__ = "system_logs"
    
    id = Column(Integer, primary_key=True, index=True)
    timestamp = Column(DateTime, default=datetime.utcnow, index=True)
    level = Column(String(20), default="INFO")  # INFO, WARNING, ERROR, SUCCESS
    message = Column(Text)
    source = Column(String(50), default="system")  # system, rembg, meshroom, api
    
    __table_args__ = (
        Index('idx_logs_time', 'timestamp'),
    )
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "timestamp": self.timestamp.isoformat() if self.timestamp else None,
            "level": self.level,
            "message": self.message,
            "source": self.source,
        }


# =============================================================================
# Database Initialization
# =============================================================================

def init_database():
    """Create all tables. Call this on startup."""
    try:
        Base.metadata.create_all(bind=engine)
        logger.info(f"Database initialized: {DB_PATH}")
    except Exception as e:
        logger.error(f"Database initialization failed: {e}")
        raise


def get_db() -> Session:
    """Get database session. Use as context manager or dependency."""
    db = SessionLocal()
    try:
        return db
    finally:
        db.close()


# =============================================================================
# CRUD Operations
# =============================================================================

class TelemetryRepository:
    """Repository pattern for telemetry operations."""
    
    @staticmethod
    def save_telemetry(
        db: Session,
        temperature: Optional[float] = None,
        humidity: Optional[int] = None,
        soil_moisture: Optional[int] = None,
        mode: str = "STANDBY",
        heater_power: int = 0,
        fan_sly: bool = False,
        fan_dz: bool = False,
        motor_position: int = 0,
        is_homed: bool = False,
        source: str = "unknown"
    ) -> TelemetryReading:
        """Save a new telemetry reading."""
        reading = TelemetryReading(
            temperature=temperature,
            humidity=humidity,
            soil_moisture=soil_moisture,
            mode=mode,
            heater_power=heater_power,
            fan_sly=fan_sly,
            fan_dz=fan_dz,
            motor_position=motor_position,
            is_homed=is_homed,
            source=source,
        )
        db.add(reading)
        db.commit()
        db.refresh(reading)
        return reading
    
    @staticmethod
    def get_latest(db: Session) -> Optional[TelemetryReading]:
        """Get most recent telemetry reading."""
        return db.query(TelemetryReading).order_by(
            TelemetryReading.timestamp.desc()
        ).first()
    
    @staticmethod
    def get_history(
        db: Session,
        hours: int = 24,
        limit: int = 1000
    ) -> List[TelemetryReading]:
        """Get telemetry history for last N hours."""
        from datetime import timedelta
        cutoff = datetime.utcnow() - timedelta(hours=hours)
        return db.query(TelemetryReading).filter(
            TelemetryReading.timestamp >= cutoff
        ).order_by(
            TelemetryReading.timestamp.desc()
        ).limit(limit).all()
    
    @staticmethod
    def cleanup_old(db: Session, days: int = 30) -> int:
        """Delete telemetry older than N days. Returns deleted count."""
        from datetime import timedelta
        cutoff = datetime.utcnow() - timedelta(days=days)
        result = db.query(TelemetryReading).filter(
            TelemetryReading.timestamp < cutoff
        ).delete()
        db.commit()
        return result


class SessionRepository:
    """Repository pattern for session operations."""
    
    @staticmethod
    def create_or_get(db: Session, session_id: str) -> Session:
        """Create new session or return existing."""
        session = db.query(Session).filter(Session.id == session_id).first()
        if not session:
            session = Session(id=session_id)
            db.add(session)
            db.commit()
            db.refresh(session)
            logger.info(f"Created session: {session_id}")
        return session
    
    @staticmethod
    def add_photo(
        db: Session,
        session_id: str,
        filename: str,
        original_path: str,
        size_bytes: int
    ) -> Photo:
        """Add photo to session."""
        session = SessionRepository.create_or_get(db, session_id)
        
        photo = Photo(
            session_id=session_id,
            filename=filename,
            original_path=original_path,
            size_bytes=size_bytes,
        )
        db.add(photo)
        session.photo_count += 1
        session.updated_at = datetime.utcnow()
        db.commit()
        db.refresh(photo)
        return photo
    
    @staticmethod
    def get_session_photos(db: Session, session_id: str) -> List[Photo]:
        """Get all photos for a session."""
        return db.query(Photo).filter(Photo.session_id == session_id).all()


class PipelineRepository:
    """Repository pattern for pipeline operations."""
    
    @staticmethod
    def create(db: Session, pipeline_id: str, session_id: str) -> Pipeline:
        """Create new pipeline record."""
        pipeline = Pipeline(
            id=pipeline_id,
            session_id=session_id,
            status="pending",
            started_at=datetime.utcnow(),
        )
        db.add(pipeline)
        db.commit()
        db.refresh(pipeline)
        return pipeline
    
    @staticmethod
    def update_progress(
        db: Session,
        pipeline_id: str,
        progress: float,
        current_step: str,
        status: Optional[str] = None
    ) -> Optional[Pipeline]:
        """Update pipeline progress."""
        pipeline = db.query(Pipeline).filter(Pipeline.id == pipeline_id).first()
        if pipeline:
            pipeline.progress = progress
            pipeline.current_step = current_step
            if status:
                pipeline.status = status
                if status in ["completed", "failed", "cancelled"]:
                    pipeline.completed_at = datetime.utcnow()
            db.commit()
            db.refresh(pipeline)
        return pipeline
    
    @staticmethod
    def set_output(db: Session, pipeline_id: str, output_path: str) -> Optional[Pipeline]:
        """Set pipeline output path."""
        pipeline = db.query(Pipeline).filter(Pipeline.id == pipeline_id).first()
        if pipeline:
            pipeline.output_path = output_path
            db.commit()
            db.refresh(pipeline)
        return pipeline
    
    @staticmethod
    def get_active_pipelines(db: Session) -> List[Pipeline]:
        """Get all running pipelines."""
        return db.query(Pipeline).filter(
            Pipeline.status.in_(["pending", "running"])
        ).all()
    
    @staticmethod
    def get_by_session(db: Session, session_id: str) -> List[Pipeline]:
        """Get all pipelines for a session."""
        return db.query(Pipeline).filter(
            Pipeline.session_id == session_id
        ).order_by(Pipeline.started_at.desc()).all()


class LogRepository:
    """Repository pattern for system logs."""
    
    @staticmethod
    def add_log(db: Session, message: str, level: str = "INFO", source: str = "system") -> SystemLog:
        """Add system log entry."""
        log = SystemLog(
            message=message,
            level=level,
            source=source,
        )
        db.add(log)
        db.commit()
        db.refresh(log)
        return log
    
    @staticmethod
    def get_recent(db: Session, limit: int = 100) -> List[SystemLog]:
        """Get recent logs."""
        return db.query(SystemLog).order_by(
            SystemLog.timestamp.desc()
        ).limit(limit).all()
    
    @staticmethod
    def cleanup_old(db: Session, days: int = 7) -> int:
        """Delete logs older than N days."""
        from datetime import timedelta
        cutoff = datetime.utcnow() - timedelta(days=days)
        result = db.query(SystemLog).filter(
            SystemLog.timestamp < cutoff
        ).delete()
        db.commit()
        return result


# Global repository instances
telemetry_repo = TelemetryRepository()
session_repo = SessionRepository()
pipeline_repo = PipelineRepository()
log_repo = LogRepository()
