from fastapi import FastAPI, Depends, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy import create_engine
from typing import List, Dict, Any
from dotenv import load_dotenv
import os
import logging
import requests
import time
import sys

# ──────────────────────────────────────────────────────────────────────────────
# Logging setup
# ──────────────────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s  [%(levelname)-8s]  %(name)s: %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("loreweaver")

# ──────────────────────────────────────────────────────────────────────────────
# Load environment variables from .env file
# ──────────────────────────────────────────────────────────────────────────────
load_dotenv()
log.info("Environment variables loaded from .env")

from db.models import init_db, Base, Character, WorldRule
from db.vector_db import VectorDBClient
from memory.context_builder import ContextBuilder
from memory.state_updater import StateUpdater
from llm.local_llm import LocalLLMClient
from llm.groq_client import GroqClient
from orchestrator.pipeline import StoryOrchestrator


# ──────────────────────────────────────────────────────────────────────────────
# Startup health checks
# ──────────────────────────────────────────────────────────────────────────────
def run_startup_checks():
    errors = []

    # 1. Check API Keys
    groq_key = os.environ.get("GROQ_API_KEY", "")
    google_key = os.environ.get("GOOGLE_API_KEY", "")
    local_ollama_url = os.environ.get("OLLAMA_URL", "http://localhost:11434")

    if not groq_key or groq_key == "dummy_key_to_allow_app_startup" or len(groq_key) < 10:
        errors.append("❌  GROQ_API_KEY is missing or invalid. Set it in backend/.env")
    else:
        log.info(f"✅  GROQ_API_KEY detected (starts with: {groq_key[:8]}…)")

    if not google_key or len(google_key) < 10:
        log.warning("⚠️   GOOGLE_API_KEY is missing. Gemini Synthesizer will be unavailable.")
    else:
        log.info(f"✅  GOOGLE_API_KEY detected (starts with: {google_key[:8]}…)")

    # 2. Check local LLM (Ollama) reachability
    try:
        resp = requests.get(f"{local_ollama_url}/api/tags", timeout=3)
        if resp.status_code == 200:
            models = [m.get("name") for m in resp.json().get("models", [])]
            log.info(f"✅  Ollama is reachable at {local_ollama_url}. Models available: {models}")
        else:
            log.warning(f"⚠️   Ollama responded with HTTP {resp.status_code}. Execution phase may fail.")
    except requests.exceptions.ConnectionError:
        log.warning(f"⚠️   Ollama is NOT reachable at {local_ollama_url}. Scene execution will fail.")
        log.warning("     → Start it with: ollama serve  (and pull a model with: ollama pull llama3)")

    # 3. Fatal errors — halt startup
    if errors:
        for e in errors:
            log.critical(e)
        log.critical("Startup aborted due to missing critical configuration.")
        sys.exit(1)

    log.info("✅  All critical checks passed. Starting API server…\n")

run_startup_checks()


# ──────────────────────────────────────────────────────────────────────────────
# App initialization
# ──────────────────────────────────────────────────────────────────────────────
app = FastAPI(title="LoreWeaver API", description="Research-Grade AI Storytelling Engine")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# SQLite Database Setup
SQLALCHEMY_DATABASE_URL = "sqlite:///./loreweaver.db"
engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False})
init_db(engine)
log.info("✅  SQLite database initialized → loreweaver.db")

# Vector DB Setup
vector_db = VectorDBClient()
log.info("✅  ChromaDB vector store initialized")

# Initialize shared LLM clients
local_llm = LocalLLMClient()
groq_client = GroqClient()
log.info("✅  LLM clients initialized (LocalLLM + Groq)")


# ──────────────────────────────────────────────────────────────────────────────
# DB Dependency
# ──────────────────────────────────────────────────────────────────────────────
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# ──────────────────────────────────────────────────────────────────────────────
# Request / Response models
# ──────────────────────────────────────────────────────────────────────────────
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


# ──────────────────────────────────────────────────────────────────────────────
# Endpoints
# ──────────────────────────────────────────────────────────────────────────────
@app.post("/character/create")
def create_character(char: CharacterCreate, db: Session = Depends(get_db)):
    log.info(f"→ [character/create] Creating character: id={char.id!r}  name={char.name!r}")
    db_char = Character(**char.model_dump())
    db.add(db_char)
    db.commit()
    db.refresh(db_char)
    log.info(f"← [character/create] Success: character_id={db_char.id!r}")
    return {"status": "success", "character_id": db_char.id}


@app.post("/generate_scene")
def generate_scene(req: GenerateSceneRequest, db: Session = Depends(get_db)):
    t_start = time.perf_counter()
    log.info("─" * 60)
    log.info(f"→ [generate_scene] REQUEST RECEIVED")
    log.info(f"   user_prompt      : {req.user_prompt!r}")
    log.info(f"   active_characters: {req.active_characters}")
    log.info(f"   location         : {req.location!r}")
    log.info(f"   seq_index        : {req.seq_index}")

    context_builder = ContextBuilder(db, vector_db)
    state_updater = StateUpdater(db, vector_db)
    orchestrator = StoryOrchestrator(context_builder, state_updater, local_llm, groq_client)

    success, text, critic_report = orchestrator.generate_next_scene(
        user_prompt=req.user_prompt,
        active_characters=req.active_characters,
        location=req.location,
        seq_index=req.seq_index,
    )

    elapsed = time.perf_counter() - t_start

    if success:
        log.info(f"← [generate_scene] SUCCESS in {elapsed:.2f}s")
        log.info(f"   critic approved : {critic_report.get('approved')}")
        log.info(f"   TAS             : {critic_report.get('metrics', {}).get('trait_adherence_score')}")
        log.info(f"   output (first 200 chars): {text[:200]!r}…")
        log.info("─" * 60)
        return {"status": "success", "scene_text": text, "critic_report": critic_report}
    else:
        log.error(f"← [generate_scene] FAILED after {elapsed:.2f}s")
        log.error(f"   critic_report: {critic_report}")
        log.info("─" * 60)
        raise HTTPException(
            status_code=500,
            detail={"message": "Failed generation after max retries", "report": critic_report},
        )


@app.get("/health")
def health_check():
    """Quick liveness endpoint to verify the server is up."""
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
