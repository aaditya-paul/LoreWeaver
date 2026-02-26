import logging
from typing import List
from sqlalchemy.orm import Session
from db.models import Character, WorldRule, TimelineEvent, Scene
from db.vector_db import VectorDBClient

log = logging.getLogger("loreweaver.context_builder")


class ContextBuilder:
    def __init__(self, db_session: Session, vector_db: VectorDBClient,
                 project_id: str = None):
        self.db = db_session
        self.vector_db = vector_db
        self.project_id = project_id

    def build_tier_1_context(self, active_character_ids: List[str], location: str,
                             characters_freetext: str = None) -> str:
        """
        Tier 1: Character states + world rules.
        Falls back to raw freetext description if no DB characters match.
        """
        context_parts = ["### ACTIVE CHARACTERS ###"]

        # --- DB characters (if any exist) ---
        characters = []
        if active_character_ids:
            characters = self.db.query(Character).filter(
                Character.id.in_(active_character_ids)
            ).all()

        if characters:
            for char in characters:
                context_parts.append(f"Name: {char.name}")
                context_parts.append(f"Core Psychology: {char.core_psychology}")
                context_parts.append(f"Current State: {char.current_state}")
                context_parts.append("")
        elif characters_freetext:
            # User described characters in plain text → use directly
            context_parts.append(characters_freetext.strip())
        else:
            context_parts.append("(No character data provided. Infer from user prompt.)")

        context_parts.append("")
        context_parts.append("### CURRENT LOCATION ###")
        context_parts.append(location or "Unspecified")

        context_parts.append("")
        context_parts.append("### RELEVANT WORLD RULES ###")
        rules = self.db.query(WorldRule).filter(
            (WorldRule.active_scope == 'global') | (WorldRule.active_scope == location)
        ).all()
        if rules:
            for rule in rules:
                context_parts.append(f"[{rule.category}] {rule.rule_text}")
        else:
            context_parts.append("(No world rules defined yet.)")

        log.debug(f"[tier_1] Built context for location={location!r}, chars={len(characters)}")
        return "\n".join(context_parts)

    def build_tier_2_context(self, num_scenes: int = 3) -> str:
        """
        Tier 2: Working memory — recent scenes from the Scene table, scoped to project.
        Falls back to TimelineEvent summaries if no Scene records exist yet.
        """
        context_parts = ["### RECENT SCENES (WORKING MEMORY) ###"]

        if self.project_id:
            # Use the Scene table — it has real generated text
            recent_scenes = (
                self.db.query(Scene)
                .filter_by(project_id=self.project_id)
                .order_by(Scene.sequence_index.desc())
                .limit(num_scenes)
                .all()
            )
            recent_scenes = list(reversed(recent_scenes))  # chronological

            if recent_scenes:
                for s in recent_scenes:
                    # Use a short excerpt (first 600 chars) of the actual scene text
                    excerpt = s.scene_text[:600].replace("\n", " ")
                    context_parts.append(
                        f"\n[Scene {s.sequence_index} — {s.location}]\n"
                        f"Prompt: {s.prompt}\n"
                        f"Excerpt: {excerpt}…"
                    )
                log.debug(f"[tier_2] Loaded {len(recent_scenes)} recent scenes from DB")
                return "\n".join(context_parts)

        # Fallback: timeline_events (project-scoped if possible)
        query = self.db.query(TimelineEvent)
        if self.project_id:
            query = query.filter_by(project_id=self.project_id)
        events = query.order_by(TimelineEvent.sequence_index.desc()).limit(num_scenes).all()
        events.reverse()

        if events:
            for event in events:
                context_parts.append(
                    f"Scene {event.sequence_index} at {event.location}: {event.summary}"
                )
        else:
            context_parts.append("(No previous scenes in this project yet.)")

        return "\n".join(context_parts)

    def build_tier_3_context(self, intent: str) -> str:
        """
        Tier 3: Semantic episodic memory via vector search.
        """
        results = self.vector_db.query_scenes(intent_text=intent, n_results=3)
        context_parts = ["### RELEVANT PAST EVENTS (SEMANTIC MEMORY) ###"]

        if results and 'documents' in results and results['documents']:
            for doc in results['documents'][0]:
                if doc:
                    context_parts.append(f"- {doc}")
        else:
            context_parts.append("(No relevant past events found.)")

        return "\n".join(context_parts)

    def assemble_full_context(self, active_character_ids: List[str], location: str,
                              intent: str, characters_freetext: str = None) -> str:
        tier_1 = self.build_tier_1_context(active_character_ids, location, characters_freetext)
        tier_2 = self.build_tier_2_context()
        tier_3 = self.build_tier_3_context(intent)
        return f"{tier_1}\n\n{tier_2}\n\n{tier_3}"
