#!/usr/bin/env python3
import os
import json
import logging
import sqlite3
from typing import List, Dict, Any, Optional
from sqlalchemy import create_engine, Column, Integer, String, Float, Boolean, DateTime, Text, ForeignKey, text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, relationship
from sqlalchemy.sql import func
from pathlib import Path

logger = logging.getLogger('flipedit_database')

Base = declarative_base()

# SQLAlchemy ORM models mapping to Drift tables
class Track(Base):
    __tablename__ = 'tracks'
    
    id = Column(Integer, primary_key=True)
    name = Column(String)
    type = Column(String, nullable=False)
    order = Column(Integer, nullable=False)
    
    clips = relationship("Clip", back_populates="track", lazy="dynamic")
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "type": self.type,
            "order": self.order
        }


class Clip(Base):
    __tablename__ = 'clips'
    
    id = Column(Integer, primary_key=True)
    track_id = Column(Integer, ForeignKey('tracks.id'), nullable=False)
    name = Column(String)
    type = Column(String, nullable=False)
    source_path = Column(String, nullable=False)
    source_duration_ms = Column(Integer, default=0)
    start_time_in_source_ms = Column(Integer, default=0)
    end_time_in_source_ms = Column(Integer)
    start_time_on_track_ms = Column(Integer, nullable=False)
    end_time_on_track_ms = Column(Integer, nullable=False)
    clip_metadata_str = Column('metadata', Text)
    
    preview_position_x = Column(Float, nullable=False, default=0.0)
    preview_position_y = Column(Float, nullable=False, default=0.0)
    preview_width = Column(Float, nullable=False, default=100.0)
    preview_height = Column(Float, nullable=False, default=100.0)
    
    track = relationship("Track", back_populates="clips")
    
    def to_dict(self) -> Dict[str, Any]:
        parsed_metadata = {}
        if self.clip_metadata_str:
            try:
                parsed_metadata = json.loads(self.clip_metadata_str)
            except json.JSONDecodeError:
                logger.warning(f"Failed to parse metadata JSON for clip {self.id}")
                
        # Basic snake_case fields
        result = {
            "id": self.id,
            "track_id": self.track_id,
            "name": self.name or "",
            "type": self.type,
            "source_path": self.source_path,
            "source_duration_ms": self.source_duration_ms,
            "start_time_in_source_ms": self.start_time_in_source_ms,
            "end_time_in_source_ms": self.end_time_in_source_ms,
            "start_time_on_track_ms": self.start_time_on_track_ms,
            "end_time_on_track_ms": self.end_time_on_track_ms,
            "metadata": parsed_metadata,
            
            "preview_position_x": self.preview_position_x,
            "preview_position_y": self.preview_position_y,
            "preview_width": self.preview_width,
            "preview_height": self.preview_height
        }
        
        result.update({
            "trackId": self.track_id,
            "sourcePath": self.source_path,
            "sourceDurationMs": self.source_duration_ms,
            "startTimeInSourceMs": self.start_time_in_source_ms,
            "endTimeInSourceMs": self.end_time_in_source_ms,
            "startTimeOnTrackMs": self.start_time_on_track_ms,
            "endTimeOnTrackMs": self.end_time_on_track_ms,
            "previewPositionX": self.preview_position_x,
            "previewPositionY": self.preview_position_y,
            "previewWidth": self.preview_width,
            "previewHeight": self.preview_height
        })
        
        return result


class ProjectAsset(Base):
    __tablename__ = 'project_assets'
    
    id = Column(Integer, primary_key=True)
    name = Column(String, nullable=False)
    source_path = Column(String, nullable=False)
    type = Column(String, nullable=False)
    mime_type = Column(String)
    duration_ms = Column(Integer)
    width = Column(Integer)
    height = Column(Integer)
    file_size = Column(Float)
    metadata_json = Column(Text)
    thumbnail_path = Column(String)
    created_at = Column(DateTime, nullable=False)
    
    def to_dict(self) -> Dict[str, Any]:
        metadata = {}
        if self.metadata_json:
            try:
                metadata = json.loads(self.metadata_json)
            except json.JSONDecodeError:
                logger.warning(f"Failed to parse metadata JSON for asset {self.id}")
                
        return {
            "id": self.id,
            "name": self.name,
            "source_path": self.source_path,
            "type": self.type,
            "mime_type": self.mime_type,
            "duration_ms": self.duration_ms,
            "width": self.width,
            "height": self.height,
            "file_size": self.file_size,
            "metadata": metadata,
            "thumbnail_path": self.thumbnail_path,
            "created_at": self.created_at.isoformat() if self.created_at else None
        }


class DatabaseManager:
    """Manager for accessing FlipEdit SQLite databases"""
    
    def __init__(self):
        self.metadata_db_path = None
        self.current_project_db_path = None
        self.metadata_engine = None
        self.project_engine = None
        self.metadata_session = None
        self.project_session = None
        self._find_metadata_db()
    
    def _find_metadata_db(self) -> None:
        """Find the metadata database in the user's Documents folder"""
        home_dir = os.path.expanduser("~")
        docs_dir = os.path.join(home_dir, "Documents")
        metadata_db_path = os.path.join(docs_dir, "flipedit_projects_metadata.sqlite")
        
        if os.path.exists(metadata_db_path):
            self.metadata_db_path = metadata_db_path
            logger.info(f"Found metadata database at: {metadata_db_path}")
            self.metadata_engine = create_engine(f"sqlite:///{metadata_db_path}")
            metadata_session_maker = sessionmaker(bind=self.metadata_engine)
            self.metadata_session = metadata_session_maker()
        else:
            logger.warning(f"Metadata database not found at {metadata_db_path}")
    
    def get_project_list(self) -> List[Dict[str, Any]]:
        """Get list of all projects from the metadata database"""
        if not self.metadata_session:
            logger.error("Metadata database not initialized")
            return []
        
        try:
            # Use text() to properly declare the SQL query
            sql_query = text("SELECT id, name, database_path, created_at, last_modified_at FROM project_metadata_table")
            result = self.metadata_session.execute(sql_query)
            
            projects = []
            for row in result:
                projects.append({
                    "id": row[0],
                    "name": row[1],
                    "database_path": row[2],
                    "created_at": row[3],
                    "last_modified_at": row[4]
                })
            
            return projects
        except Exception as e:
            logger.error(f"Error getting project list: {e}")
            return []
    
    def connect_to_project(self, project_id: Optional[int] = None, database_path: Optional[str] = None) -> bool:
        """Connect to a specific project database by ID or path"""
        logger.info(f"Connect to project called with project_id={project_id}, database_path={database_path}")
        
        if not project_id and not database_path:
            # Get the most recently modified project
            projects = self.get_project_list()
            if not projects:
                logger.error("No projects found")
                return False
            
            # Sort by last_modified_at or created_at if available
            projects.sort(key=lambda p: p.get("last_modified_at") or p.get("created_at") or "", reverse=True)
            project_id = projects[0]["id"]
            database_path = projects[0]["database_path"]
            logger.info(f"Using most recent project: {projects[0]['name']} (ID: {project_id})")
        
        if project_id and not database_path and self.metadata_session:
            try:
                # Use text() for this SQL query as well
                sql_query = text("SELECT database_path FROM project_metadata_table WHERE id = :project_id")
                result = self.metadata_session.execute(sql_query, {"project_id": project_id}).fetchone()
                
                if result:
                    database_path = result[0]
                    logger.info(f"Found database path for project ID {project_id}: {database_path}")
                else:
                    logger.error(f"Project with ID {project_id} not found")
                    return False
            except Exception as e:
                logger.error(f"Error getting project database path: {e}")
                return False
        
        if not database_path:
            logger.error("No database path provided or found")
            return False
        
        if not os.path.exists(database_path):
            logger.error(f"Project database file not found: {database_path}")
            return False
        
        try:
            # Close previous connection if exists
            if self.project_session:
                logger.info("Closing previous database connection")
                self.project_session.close()
            
            logger.info(f"Connecting to SQLite database at: {database_path}")
            self.current_project_db_path = database_path
            
            # Create engine with echo=True for debug logging
            self.project_engine = create_engine(f"sqlite:///{database_path}", echo=False)
            logger.info("Engine created, creating session")
            
            project_session_maker = sessionmaker(bind=self.project_engine)
            self.project_session = project_session_maker()
            
            # Test the connection with a simple query
            test_query = text("SELECT 1")
            result = self.project_session.execute(test_query).fetchone()
            logger.info(f"Connection test result: {result}")
            
            logger.info(f"Connected to project database: {database_path}")
            return True
        except Exception as e:
            logger.error(f"Error connecting to project database: {e}")
            logger.exception("Connection exception details:")
            return False
    
    def get_all_tracks(self) -> List[Dict[str, Any]]:
        """Get all tracks from the current project database"""
        if not self.project_session:
            logger.error("Project database not connected")
            return []
        
        try:
            tracks = self.project_session.query(Track).order_by(Track.order).all()
            return [track.to_dict() for track in tracks]
        except Exception as e:
            logger.error(f"Error getting tracks: {e}")
            return []
    
    def get_all_clips(self) -> List[Dict[str, Any]]:
        """Get all clips from the current project database"""
        if not self.project_session:
            logger.error("Project database not connected")
            return []
        
        try:
            clips = self.project_session.query(Clip).all()
            return [clip.to_dict() for clip in clips]
        except Exception as e:
            logger.error(f"Error getting clips: {e}")
            return []
    
    def get_clips_for_track(self, track_id: int) -> List[Dict[str, Any]]:
        """Get clips for a specific track"""
        if not self.project_session:
            logger.error("Project database not connected")
            return []
        
        try:
            clips = self.project_session.query(Clip).filter(Clip.track_id == track_id).all()
            return [clip.to_dict() for clip in clips]
        except Exception as e:
            logger.error(f"Error getting clips for track {track_id}: {e}")
            return []
    
    def get_project_assets(self) -> List[Dict[str, Any]]:
        """Get all project assets"""
        if not self.project_session:
            logger.error("Project database not connected")
            return []
        
        try:
            assets = self.project_session.query(ProjectAsset).all()
            return [asset.to_dict() for asset in assets]
        except Exception as e:
            logger.error(f"Error getting project assets: {e}")
            return []
    
    def close(self) -> None:
        """Close database connections"""
        if self.project_session:
            self.project_session.close()
            logger.info("Closed project database connection")
        
        if self.metadata_session:
            self.metadata_session.close()
            logger.info("Closed metadata database connection")


# Singleton instance
db_manager = DatabaseManager()

def get_manager() -> DatabaseManager:
    """Get the database manager singleton instance"""
    return db_manager

# Example usage:
if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    
    # Get the database manager
    manager = get_manager()
    
    # List all projects
    projects = manager.get_project_list()
    print(f"Found {len(projects)} projects:")
    for project in projects:
        print(f"  - {project['name']} (ID: {project['id']})")
    
    # Connect to the most recent project
    if manager.connect_to_project():
        # Get all tracks
        tracks = manager.get_all_tracks()
        print(f"Found {len(tracks)} tracks")
        
        # Get all clips
        clips = manager.get_all_clips()
        print(f"Found {len(clips)} clips")
        
        # Close connections
        manager.close() 