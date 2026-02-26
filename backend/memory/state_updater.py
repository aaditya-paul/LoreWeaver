import json
import logging
from typing import List, Dict, Any
from sqlalchemy.orm import Session
from sqlalchemy import func
from db.models import Character, TimelineEvent
from db.vector_db import VectorDBClient

log = logging.getLogger("loreweaver.state_updater")

class StateUpdater:
    def __init__(self, db_session: Session, vector_db: VectorDBClient):
        self.db = db_session
        self.vector_db = vector_db
        
    def update_character_state(self, character_id: str, new_state_patch: Dict[str, Any]):
        """
        Updates the mutable state of a character. 
        new_state_patch contains keys to add/update in the current JSON state.
        """
        character = self.db.query(Character).filter_by(id=character_id).first()
        if not character:
            raise ValueError(f"Character {character_id} not found.")
            
        # Parse current state (assuming it's a dict depending on DB JSON dialect, here we merge dicts)
        current_state = character.current_state if isinstance(character.current_state, dict) else json.loads(character.current_state)
        
        # Apply patch
        for key, value in new_state_patch.items():
            if value is None:
                current_state.pop(key, None) # Remove if None
            else:
                current_state[key] = value
                
        # SQLAlchemy needs to know the JSON column was mutated if we edit in place,
        # so we reassign the reference.
        character.current_state = current_state
        self.db.commit()
        
    def commit_scene(self, scene_id: str, location: str, participants: List[str], summary: str, semantic_intent: str, causal_prereqs: List[str] = None):
        """
        Commits a completed scene to both Structured DB (Timeline) and Vector DB.
        seq_index is auto-computed as max(existing) + 1 to avoid UNIQUE constraint conflicts.
        """
        if causal_prereqs is None:
            causal_prereqs = []

        # Auto-compute the next safe sequence index from the DB
        max_index = self.db.query(func.max(TimelineEvent.sequence_index)).scalar() or 0
        seq_index = max_index + 1
        log.debug(f"[commit_scene] Auto-assigned seq_index={seq_index} (prev max={max_index})")

        # 1. Update Timeline
        new_event = TimelineEvent(
            id=scene_id,
            sequence_index=seq_index,
            location=location,
            participants=participants,
            summary=summary,
            causal_prerequisites=causal_prereqs
        )
        self.db.add(new_event)

        try:
            # 2. Update Vector Episodic Memory
            self.vector_db.add_scene(
                scene_id=scene_id,
                summary=semantic_intent,
                metadata={
                    "sequence_index": seq_index,
                    "location": location,
                    "participants": ",".join(participants)
                }
            )
            self.db.commit()
            log.info(f"[commit_scene] Scene {scene_id} committed as seq_index={seq_index}")
        except Exception as e:
            self.db.rollback()
            log.error(f"[commit_scene] Commit failed, rolled back: {e}")
            raise
