import uuid
import logging
import time
from typing import List, Dict, Any, Tuple
from memory.context_builder import ContextBuilder
from memory.state_updater import StateUpdater
from llm.local_llm import LocalLLMClient
from llm.groq_client import GroqClient

log = logging.getLogger("loreweaver.pipeline")


class StoryOrchestrator:
    def __init__(self, context_builder: ContextBuilder, state_updater: StateUpdater,
                 local_llm: LocalLLMClient, groq_client: GroqClient):
        self.context_builder = context_builder
        self.state_updater = state_updater
        self.local_llm = local_llm
        self.groq_client = groq_client

    def generate_next_scene(
        self,
        user_prompt: str,
        active_characters: List[str],
        location: str,
        seq_index: int,
        max_retries: int = 2,
    ) -> Tuple[bool, str, Dict[str, Any]]:
        """
        Core State Machine loop for LoreWeaver generation.
        Returns (Success_Bool, Generated_Text, Critic_Metrics)
        """
        log.debug("── PIPELINE START ──────────────────────────────────────")

        # ── Phase 1: Build Tier 1 & 2 context for planning ───────────────────
        log.debug("[Phase 1] Building Tier 1 (character state) context…")
        t = time.perf_counter()
        tier_1_state = self.context_builder.build_tier_1_context(active_characters, location)
        log.debug(f"   Tier 1 done in {time.perf_counter()-t:.2f}s  ({len(tier_1_state)} chars)")
        log.debug(f"   Tier 1 content:\n{tier_1_state[:600]}")

        log.debug("[Phase 1] Building Tier 2 (working memory) context…")
        t = time.perf_counter()
        tier_2_memory = self.context_builder.build_tier_2_context(num_scenes=3)
        log.debug(f"   Tier 2 done in {time.perf_counter()-t:.2f}s  ({len(tier_2_memory)} chars)")

        # ── Phase 2: Groq planning ────────────────────────────────────────────
        log.info("[Phase 2] Sending to Groq Planner…")
        t = time.perf_counter()
        outline = self.groq_client.plan_scene(tier_1_state, tier_2_memory, user_prompt)
        log.info(f"   Groq Planner done in {time.perf_counter()-t:.2f}s")
        if "error" in outline:
            log.error(f"   Groq Planner FAILED: {outline}")
            return False, "Failed to plan scene", outline
        log.info(f"   Scene outline: {outline}")

        intent_summary = outline.get("intent_summary", "General conversation and movement.")

        # ── Phase 3: Tier 3 episodic retrieval ───────────────────────────────
        log.debug("[Phase 3] Querying Vector DB for episodic memory…")
        t = time.perf_counter()
        tier_3_episodic = self.context_builder.build_tier_3_context(intent_summary)
        log.debug(f"   Vector query done in {time.perf_counter()-t:.2f}s  ({len(tier_3_episodic)} chars)")

        full_context = f"{tier_1_state}\n\n{tier_2_memory}\n\n{tier_3_episodic}"
        log.debug(f"   Full assembled context length: {len(full_context)} chars")

        # ── Phase 4: Execute + Critique loop ─────────────────────────────────
        draft_scene = ""
        critic_report: Dict[str, Any] = {}

        for attempt in range(max_retries):
            log.info(f"[Phase 4] Execution attempt {attempt + 1}/{max_retries}  →  Local LLM…")
            t = time.perf_counter()
            draft_scene = self.local_llm.generate_scene(full_context, outline)
            elapsed = time.perf_counter() - t
            log.info(f"   Local LLM done in {elapsed:.2f}s  ({len(draft_scene)} chars generated)")
            log.debug(f"   Draft (first 500 chars):\n{draft_scene[:500]}")

            log.info(f"[Phase 4] Running Groq Consistency Critic…")
            t = time.perf_counter()
            critic_report = self.groq_client.evaluate_consistency(tier_1_state, draft_scene)
            log.info(f"   Critic done in {time.perf_counter()-t:.2f}s")
            log.info(f"   Critic report: {critic_report}")

            if critic_report.get("approved"):
                scene_id = f"sc_{uuid.uuid4().hex[:8]}"
                log.info(f"[Phase 4] Scene APPROVED → committing as {scene_id}")
                self.state_updater.commit_scene(
                    scene_id=scene_id,
                    location=location,
                    participants=active_characters,
                    summary=intent_summary,
                    semantic_intent=intent_summary,
                )
                log.debug("── PIPELINE END (success) ───────────────────────────")
                return True, draft_scene, critic_report
            else:
                log.warning(f"[Phase 4] Scene REJECTED on attempt {attempt + 1}. Retrying…")

        log.error("[Phase 4] All retries exhausted — scene rejected.")
        log.debug("── PIPELINE END (failure) ───────────────────────────")
        return False, draft_scene, critic_report
