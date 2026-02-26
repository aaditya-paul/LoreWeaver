# LoreWeaver 📖

A research-grade storytelling engine designed to generate long-form narratives (20k+ words) with strong consistency, coherent character development, and maintained world rules.

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

**Frontend** (Planned)

- Flutter for cross-platform UI

## Installation

### Prerequisites

- Python 3.9 or higher
- (Optional) Local LLM setup (Ollama or llama.cpp)
- API keys for Groq and/or Google Gemini

### Setup

1. **Clone the repository**

   ```bash
   git clone <repository-url>
   cd LoreWeaver
   ```

2. **Install dependencies**

   ```bash
   cd backend
   pip install -r requirements.txt
   ```

3. **Configure environment**
   Create a `.env` file in the `backend` directory:

   ```env
   GROQ_API_KEY=your_groq_key_here
   GEMINI_API_KEY=your_gemini_key_here
   LOCAL_LLM_ENABLED=true
   ```

4. **Initialize databases**

   ```bash
   python -m db.models  # Creates SQLite schema
   python -m db.vector_db  # Initializes ChromaDB
   ```

5. **Run the server**
   ```bash
   python main.py
   ```

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
├── backend/
│   ├── main.py                 # API server entry point
│   ├── requirements.txt        # Python dependencies
│   ├── db/
│   │   ├── models.py          # SQLAlchemy schemas
│   │   └── vector_db.py       # ChromaDB interface
│   ├── llm/
│   │   ├── gemini_client.py   # Google Gemini integration
│   │   ├── groq_client.py     # Groq API client
│   │   └── local_llm.py       # Local model interface
│   ├── memory/
│   │   ├── context_builder.py # 3-tier context assembly
│   │   └── state_updater.py   # Memory synchronization
│   └── orchestrator/
│       └── pipeline.py         # Multi-phase generation pipeline
└── ARCHITECTURE_DESIGN.md      # Detailed technical documentation
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

- [ ] Flutter frontend with real-time generation streaming
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
