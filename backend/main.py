from fastapi import FastAPI, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session
from sqlalchemy import create_engine
from typing import List, Dict, Any

from backend.db.models import init_db, Base, Character, WorldRule
from backend.db.vector_db import vector_db
from backend.memory.context_builder import ContextBuilder
from backend.memory.state_updater import StateUpdater
from backend.llm.local_llm import LocalLLMClient
from backend.llm.groq_client import GroqClient
from backend.orchestrator.pipeline import StoryOrchestrator

app = FastAPI(title="LoreWeaver API", description="Research-Grade AI Storytelling Engine")

# SQLite Database Setup
SQLALCHEMY_DATABASE_URL = "sqlite:///./loreweaver.db"
engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False})
init_db(engine)

# Dependency to get DB session
def get_db():
    from sqlalchemy.orm import sessionmaker
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# Initialize Core Services
local_llm = LocalLLMClient()
groq_client = GroqClient()

class GenerateSceneRequest(BaseModel):
    user_prompt: str
    active_characters: List[str]
    location: str
    seq_index: int

class CharacterCreate(BaseModel):
    id: str
    name: str
    core_psychology: str
    current_state: dict

@app.post("/character/create")
def create_character(char: CharacterCreate, db: Session = Depends(get_db)):
    db_char = Character(**char.model_dump())
    db.add(db_char)
    db.commit()
    db.refresh(db_char)
    return {"status": "success", "character_id": db_char.id}

@app.post("/generate_scene")
def generate_scene(req: GenerateSceneRequest, db: Session = Depends(get_db)):
    context_builder = ContextBuilder(db, vector_db)
    state_updater = StateUpdater(db, vector_db)
    orchestrator = StoryOrchestrator(context_builder, state_updater, local_llm, groq_client)
    
    success, text, critic_report = orchestrator.generate_next_scene(
        user_prompt=req.user_prompt,
        active_characters=req.active_characters,
        location=req.location,
        seq_index=req.seq_index
    )
    
    if success:
        return {"status": "success", "scene_text": text, "critic_report": critic_report}
    else:
        raise HTTPException(status_code=500, detail={"message": "Failed generation", "report": critic_report})

# To run: uvicorn backend.main:app --reload
