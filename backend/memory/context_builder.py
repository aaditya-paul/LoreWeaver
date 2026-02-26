from typing import List, Dict, Any
from sqlalchemy.orm import Session
from db.models import Character, WorldRule, TimelineEvent
from db.vector_db import VectorDBClient

class ContextBuilder:
    def __init__(self, db_session: Session, vector_db: VectorDBClient):
        self.db = db_session
        self.vector_db = vector_db
        
    def build_tier_1_context(self, active_character_ids: List[str], location: str) -> str:
        """
        Retrieves High-Priority State: Immutable psychology, mutable states, and relevant world rules.
        """
        context_parts = ["### ACTIVE CHARACTERS ###\n"]
        characters = self.db.query(Character).filter(Character.id.in_(active_character_ids)).all()
        for char in characters:
            context_parts.append(f"Name: {char.name}")
            context_parts.append(f"Core Psychology: {char.core_psychology}")
            context_parts.append(f"Current State: {char.current_state}")
            context_parts.append("")
            
        context_parts.append("### RELEVANT WORLD RULES ###\n")
        # For simplicity, fetching global rules and rules matching the location
        rules = self.db.query(WorldRule).filter(
            (WorldRule.active_scope == 'global') | (WorldRule.active_scope == location)
        ).all()
        for rule in rules:
            context_parts.append(f"[{rule.category}] {rule.rule_text}")
            
        return "\n".join(context_parts)
    
    def build_tier_2_context(self, num_scenes: int = 3) -> str:
        """
        Retrieves Working Memory: The literal raw text of the last N scenes.
        (Ideally fetched from the TimelineEvent table or a dedicated raw text log).
        """
        events = self.db.query(TimelineEvent).order_by(TimelineEvent.sequence_index.desc()).limit(num_scenes).all()
        events.reverse() # chronological
        
        context_parts = ["### RECENT EVENTS (WORKING MEMORY) ###\n"]
        for event in events:
            context_parts.append(f"Scene {event.sequence_index} at {event.location}: {event.summary}")
            
        return "\n".join(context_parts)
        
    def build_tier_3_context(self, intent: str) -> str:
        """
        Retrieves Semantic Episodic Memory using Vector DB based on intended scene actions.
        """
        results = self.vector_db.query_scenes(intent_text=intent, n_results=3)
        context_parts = ["### RELEVANT PAST EVENTS ###\n"]
        
        # ChromaDB query returns a dict with 'documents' list of lists
        if results and 'documents' in results and results['documents']:
            for doc in results['documents'][0]:
                context_parts.append(f"- {doc}")
                
        return "\n".join(context_parts)
        
    def assemble_full_context(self, active_character_ids: List[str], location: str, intent: str) -> str:
        tier_1 = self.build_tier_1_context(active_character_ids, location)
        tier_2 = self.build_tier_2_context()
        tier_3 = self.build_tier_3_context(intent)
        
        return f"{tier_1}\n\n{tier_2}\n\n{tier_3}"
