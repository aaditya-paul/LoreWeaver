from fastapi import FastAPI, Depends, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy import create_engine, func
from typing import List
from dotenv import load_dotenv
import os
import logging
import requests
import time
import sys
import uuid

# ──────────────────────────────────────────────────────────────────────────────
# Logging
# ──────────────────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s  [%(levelname)-8s]  %(name)s: %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("loreweaver")

# ──────────────────────────────────────────────────────────────────────────────
# .env
# ──────────────────────────────────────────────────────────────────────────────
load_dotenv()
log.info("Environment variables loaded from .env")

from db.models import init_db, Character, WorldRule, Scene, Project
from db.vector_db import VectorDBClient
from memory.context_builder import ContextBuilder
from memory.state_updater import StateUpdater
from llm.local_llm import LocalLLMClient
from llm.groq_client import GroqClient
from orchestrator.pipeline import StoryOrchestrator
from auth.router import router as auth_router
from auth.deps import get_current_user
from projects.router import router as projects_router


# ──────────────────────────────────────────────────────────────────────────────
# Startup checks
# ──────────────────────────────────────────────────────────────────────────────
def run_startup_checks():
    errors = []
    groq_key = os.environ.get("GROQ_API_KEY", "")
    google_key = os.environ.get("GOOGLE_API_KEY", "")
    local_ollama_url = os.environ.get("OLLAMA_URL", "http://localhost:11434")

    if not groq_key or len(groq_key) < 10:
        errors.append("❌  GROQ_API_KEY is missing or invalid.")
    else:
        log.info(f"✅  GROQ_API_KEY detected (starts with: {groq_key[:8]}…)")

    if not google_key or len(google_key) < 10:
        log.warning("⚠️   GOOGLE_API_KEY is missing. Gemini Synthesizer unavailable.")
    else:
        log.info(f"✅  GOOGLE_API_KEY detected (starts with: {google_key[:8]}…)")

    try:
        resp = requests.get(f"{local_ollama_url}/api/tags", timeout=3)
        if resp.status_code == 200:
            models = [m.get("name") for m in resp.json().get("models", [])]
            log.info(f"✅  Ollama reachable at {local_ollama_url}. Models: {models}")
        else:
            log.warning(f"⚠️   Ollama responded HTTP {resp.status_code}.")
    except requests.exceptions.ConnectionError:
        log.warning(f"⚠️   Ollama NOT reachable at {local_ollama_url}. Scene execution will fail.")

    if errors:
        for e in errors:
            log.critical(e)
        sys.exit(1)

    log.info("✅  All critical checks passed. Starting API server…\n")

run_startup_checks()


# ──────────────────────────────────────────────────────────────────────────────
# App
# ──────────────────────────────────────────────────────────────────────────────
app = FastAPI(title="LoreWeaver API", description="Research-Grade AI Storytelling Engine")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# SQLite
SQLALCHEMY_DATABASE_URL = "sqlite:///./loreweaver.db"
engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False})
init_db(engine)
log.info("✅  SQLite database initialized → loreweaver.db")

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# Vector DB
vector_db = VectorDBClient()
log.info("✅  ChromaDB vector store initialized")

# LLM clients
local_llm = LocalLLMClient()
groq_client = GroqClient()
log.info("✅  LLM clients initialized (LocalLLM + Groq)")


# ──────────────────────────────────────────────────────────────────────────────
# Wire dependency overrides so routers share our get_db
# ──────────────────────────────────────────────────────────────────────────────
from auth.router import get_db as auth_get_db
from projects.router import get_db as projects_get_db

app.dependency_overrides[auth_get_db] = get_db
app.dependency_overrides[projects_get_db] = get_db


# ──────────────────────────────────────────────────────────────────────────────
# Include routers
# ──────────────────────────────────────────────────────────────────────────────
app.include_router(auth_router)
app.include_router(projects_router)


# ──────────────────────────────────────────────────────────────────────────────
# Generate Scene endpoint
# ──────────────────────────────────────────────────────────────────────────────
class GenerateSceneRequest(BaseModel):
    project_id: str
    user_prompt: str
    active_characters: List[str] = []
    location: str = 'Unspecified'
    characters_freetext: str = ''  # plain-text character descriptions when no DB records exist


@app.post("/generate_scene")
def generate_scene(
    req: GenerateSceneRequest,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    t_start = time.perf_counter()
    log.info("─" * 60)
    log.info(f"→ [generate_scene] user={current_user['email']}  project={req.project_id}")
    log.info(f"   prompt    : {req.user_prompt!r}")
    log.info(f"   location  : {req.location!r}")
    log.info(f"   characters: {req.active_characters}")

    # Verify project ownership
    project = db.query(Project).filter_by(
        id=req.project_id, user_id=current_user["user_id"]
    ).first()
    if not project:
        raise HTTPException(status_code=404, detail="Project not found")

    # Compute next seq_index for this project
    max_seq = db.query(func.max(Scene.sequence_index)).filter_by(
        project_id=req.project_id
    ).scalar() or 0
    seq_index = max_seq + 1

    # Resolve effective location (never let it be blank)
    effective_location = req.location.strip() or 'Unspecified'

    # Run the generation pipeline
    context_builder = ContextBuilder(db, vector_db, project_id=req.project_id)
    state_updater = StateUpdater(db, vector_db)
    orchestrator = StoryOrchestrator(context_builder, state_updater, local_llm, groq_client)

    success, text, critic_report = orchestrator.generate_next_scene(
        user_prompt=req.user_prompt,
        active_characters=req.active_characters,
        location=effective_location,
        seq_index=seq_index,
        project_id=req.project_id,
        characters_freetext=req.characters_freetext or None,
    )

    elapsed = time.perf_counter() - t_start

    if success:
        # Persist the scene to DB
        scene = Scene(
            id=str(uuid.uuid4()),
            project_id=req.project_id,
            sequence_index=seq_index,
            prompt=req.user_prompt,
            scene_text=text,
            critic_report=critic_report,
            location=req.location,
            participants=req.active_characters,
        )
        db.add(scene)
        db.commit()

        log.info(f"← [generate_scene] SUCCESS in {elapsed:.2f}s  seq={seq_index}")
        log.info(f"   TAS: {critic_report.get('metrics', {}).get('trait_adherence_score')}")
        log.info("─" * 60)
        return {
            "status": "success",
            "scene_id": scene.id,
            "sequence_index": seq_index,
            "scene_text": text,
            "critic_report": critic_report,
        }
    else:
        log.error(f"← [generate_scene] FAILED in {elapsed:.2f}s")
        log.info("─" * 60)
        raise HTTPException(
            status_code=500,
            detail={"message": "Generation failed after max retries", "report": critic_report},
        )


@app.post("/character/create")
def create_character(char: dict, db: Session = Depends(get_db)):
    from db.models import Character
    db_char = Character(**char)
    db.add(db_char)
    db.commit()
    return {"status": "success", "character_id": db_char.id}


@app.get("/health")
def health_check():
    groq_key_ok = bool(os.environ.get("GROQ_API_KEY"))
    ollama_ok = False
    try:
        r = requests.get("http://localhost:11434/api/tags", timeout=2)
        ollama_ok = r.status_code == 200
    except Exception:
        pass
    return {
        "status": "ok",
        "groq_key_configured": groq_key_ok,
        "google_key_configured": bool(os.environ.get("GOOGLE_API_KEY")),
        "ollama_reachable": ollama_ok,
    }
