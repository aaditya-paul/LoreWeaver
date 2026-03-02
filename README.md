# LoreWeaver 📖

A research-grade AI storytelling engine that generates long-form narratives (20k+ words) with strong consistency, coherent character development, and maintained world rules — served via a Flutter web UI backed by a FastAPI server.

> **TL;DR — just want to run it?** See [Quick Start (Docker)](#quick-start-docker) below.

## Overview

LoreWeaver solves the fundamental problem of AI-generated long-form fiction: **narrative collapse**. Most LLMs struggle to maintain consistency beyond a few thousand words, leading to contradictory character behaviors, forgotten plot points, and broken world rules.

Instead of relying solely on large context windows, LoreWeaver models stories as **state machines** with hybrid memory architecture, multi-model orchestration, and automated consistency checking.

## Key Features

- **🧠 Hybrid Memory Architecture**: Separates factual state (characters, world rules, timeline) from episodic narrative beats
- **🔄 Multi-Agent Pipeline**: Planning, execution, and critique phases using different specialized models
- **✅ Automated Consistency Checking**: Every scene is validated against character traits, timeline events, and world rules
- **🎯 Smart Context Assembly**: 3-tier retrieval system ensures relevant information is always available
- **⚡ Multi-Model Routing**:
  - Local LLMs for bulk creative generation (zero API cost)
  - Groq for fast planning and critique
  - Gemini for deep synthesis and long-context reasoning
- **📊 Self-Consistency Reports**: Quantified metrics for trait adherence, temporal continuity, and state drift

## Architecture Highlights

```
Scene Generation Pipeline:
1. Planning Phase (Groq) → Scene outline with constraints
2. Execution Phase (Local LLM) → Full scene generation
3. Critique Phase (Groq/Gemini) → Consistency validation
4. State Update → Memory layers synchronized
```

### Memory System

**Structured Memory (SQLite/Graph)**

- Character states, psychology, relationships
- World rules (magic systems, physics, politics)
- Timeline events with causal dependencies

**Episodic Memory (Vector DB)**

- Embedded scene summaries for semantic retrieval
- Metadata-enriched for context-aware querying

### Context Assembly Strategy

1. **Tier 1: High-Priority State** (~1k tokens) - Current characters, location, active rules
2. **Tier 2: Working Memory** (~2k tokens) - Recent scenes for stylistic continuity
3. **Tier 3: Semantic Memory** (~2k tokens) - Dynamically retrieved relevant past events

## Tech Stack

**Backend**

- Python 3.9+
- FastAPI (API Gateway)
- SQLAlchemy (Structured DB)
- ChromaDB (Vector embeddings)

**LLM Integration**

- Local: Llama 3 / Mistral (via llama.cpp or Ollama)
- Groq API: Llama-3-70B for fast inference
- Google Gemini 1.5 Pro: Long-context synthesis

**Frontend**

- Flutter (web, mobile, desktop)
- Served via nginx in Docker

## Quick Start (Docker)

The entire stack — FastAPI backend, ChromaDB, SQLite, and Flutter web frontend — runs with a single command via Docker Compose.

### Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (includes Docker Compose)
- A **Groq API key** (required — get one free at [console.groq.com](https://console.groq.com))
- Optionally a **Google API key** for Gemini synthesis

### 1 — Set up your environment file

```bash
cp backend/.env.example backend/.env
```

Open `backend/.env` and fill in your keys:

```env
GROQ_API_KEY=gsk_your_groq_key_here
GOOGLE_API_KEY=AIza_your_google_key_here   # optional
JWT_SECRET=replace_with_random_string       # used to sign auth tokens
LOCAL_LLM_ENABLED=false
```

Generate a secure `JWT_SECRET` with:

```bash
python -c "import secrets; print(secrets.token_hex(32))"
```

### 2 — Build and start

```bash
docker compose up -d --build
```

That's it. The first build downloads Flutter and compiles the web app — it takes a few minutes. Subsequent starts (without `--build`) are instant.

| Service               | URL                        |
| --------------------- | -------------------------- |
| Frontend              | http://localhost:8080      |
| Backend API / Swagger | http://localhost:8000/docs |

### Stopping

```bash
docker compose down        # stop containers, keep data
docker compose down -v     # stop and wipe all persistent data (DB, ChromaDB)
```

### Live logs

```bash
docker compose logs -f backend    # backend logs
docker compose logs -f frontend   # nginx access logs
```

### Using a local LLM (Ollama)

If you run Ollama on your host machine, set `OLLAMA_URL` in `backend/.env`:

```env
LOCAL_LLM_ENABLED=true
OLLAMA_URL=http://host.docker.internal:11434   # already set in docker-compose.yml
```

Or uncomment the `ollama` service block in `docker-compose.yml` to run it inside Docker, then pull a model:

```bash
docker compose exec ollama ollama pull mistral
```

---

## Manual Setup (without Docker)

### Prerequisites

- Python 3.9+
- Flutter SDK (for frontend development)
- (Optional) Ollama for local LLM

### Backend

1. **Clone the repository**

   ```bash
   git clone https://github.com/aaditya-paul/LoreWeaver.git
   cd LoreWeaver
   ```

2. **Install dependencies**

   ```bash
   cd backend
   pip install -r requirements.txt
   ```

3. **Configure environment** — create `backend/.env`:

   ```env
   GROQ_API_KEY=your_groq_key_here
   GOOGLE_API_KEY=your_google_key_here
   JWT_SECRET=your_random_secret
   LOCAL_LLM_ENABLED=false
   ```

4. **Run the server**

   ```bash
   uvicorn main:app --host 0.0.0.0 --port 8000 --reload
   ```

### Frontend

```bash
cd frontend
flutter pub get
flutter run -d chrome          # web dev server
# or
flutter build web --release    # production build → build/web/
```

By default the Flutter app points to `http://127.0.0.1:8000`. This works as-is for local development.

---

## Usage

### Basic Story Generation

```python
from orchestrator.pipeline import StoryPipeline

pipeline = StoryPipeline()

# Initialize story with characters and world rules
story_config = {
    "characters": [
        {
            "name": "Elena",
            "core_psychology": "brave but reckless, fiercely protective",
            "current_state": {"physical": "healthy", "emotional": "determined"}
        }
    ],
    "world_rules": [
        {"category": "magic", "rule": "Magic requires blood sacrifice"}
    ]
}

pipeline.initialize_story(story_config)

# Generate next scene
scene = pipeline.generate_scene(
    user_prompt="Elena discovers the forbidden library"
)

print(scene.text)
print(scene.consistency_report)
```

### Consistency Report Example

```json
{
  "scene_id": "sc_049",
  "approved": true,
  "metrics": {
    "trait_adherence_score": 0.95,
    "temporal_continuity_flags": 0,
    "state_drift_detected": ["sword_lost"]
  },
  "justification": "Character acted consistently with reckless trait."
}
```

## Project Structure

```
LoreWeaver/
├── docker-compose.yml          # Single-command orchestration (start here)
├── ARCHITECTURE_DESIGN.md      # Detailed technical documentation
│
├── backend/
│   ├── Dockerfile
│   ├── .env.example            # Copy to .env and fill in your keys
│   ├── main.py                 # FastAPI app entry point
│   ├── requirements.txt
│   ├── auth/
│   │   ├── router.py          # /auth/* endpoints (register, login)
│   │   └── deps.py            # JWT helpers
│   ├── db/
│   │   ├── models.py          # SQLAlchemy schemas (User, Project, Scene…)
│   │   └── vector_db.py       # ChromaDB interface
│   ├── llm/
│   │   ├── base_llm.py        # Abstract LLM interface
│   │   ├── gemini_client.py   # Google Gemini integration
│   │   ├── groq_client.py     # Groq API client
│   │   └── local_llm.py       # Ollama / local model interface
│   ├── memory/
│   │   ├── context_builder.py # 3-tier context assembly
│   │   └── state_updater.py   # Memory synchronization
│   ├── orchestrator/
│   │   └── pipeline.py        # Multi-phase generation pipeline
│   └── projects/
│       └── router.py          # /projects/* CRUD endpoints
│
└── frontend/
    ├── Dockerfile              # Flutter web build → nginx
    ├── nginx.conf
    └── lib/
        ├── main.dart           # App entry point + scene generation UI
        ├── auth_screen.dart    # Login / Register screen
        ├── projects_screen.dart
        ├── story_reader.dart   # Scene reader / player
        └── palette.dart        # Design tokens
```

## Evaluation Metrics

LoreWeaver tracks three key consistency metrics:

- **Trait Adherence Score (TAS)**: Measures how well character actions align with their defined psychology
- **Temporal Continuity**: Detects "zombie objects" (references to destroyed items/characters)
- **State Drift Rate**: Identifies unexplained character state changes

## Detailed Documentation

For in-depth technical documentation, including:

- Complete memory architecture schemas
- Model routing decision logic
- Prompt engineering strategies
- State machine implementation details

See [ARCHITECTURE_DESIGN.md](ARCHITECTURE_DESIGN.md)

## Roadmap

- [x] Flutter web frontend with auth, project management, and scene generation
- [x] Docker Compose single-command deployment
- [ ] Real-time scene generation streaming (SSE / WebSocket)
- [ ] Multi-threaded scene generation for side plots
- [ ] Export to EPUB/PDF with formatting preservation
- [ ] Fine-tuned local models for genre-specific generation
- [ ] Interactive character chat during story planning
- [ ] Version control for story branches and alternate timelines

## Contributing

Contributions are welcome! This is a research-grade project exploring the boundaries of AI-assisted creative writing.

Areas of interest:

- Novel consistency checking algorithms
- Memory retrieval optimization
- Alternative state representation schemas
- Evaluation metrics for narrative quality

## License

[Add your license here]

## Acknowledgments

Built with inspiration from cognitive science research on human narrative construction and modern LLM orchestration patterns.

---

**Status**: Active Development | **Version**: 0.1.0-alpha
