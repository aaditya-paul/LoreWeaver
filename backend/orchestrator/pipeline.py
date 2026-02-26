import uuid
from typing import List, Dict, Any, Tuple
from backend.memory.context_builder import ContextBuilder
from backend.memory.state_updater import StateUpdater
from backend.llm.local_llm import LocalLLMClient
from backend.llm.groq_client import GroqClient

class StoryOrchestrator:
    def __init__(self, context_builder: ContextBuilder, state_updater: StateUpdater, 
                 local_llm: LocalLLMClient, groq_client: GroqClient):
        self.context_builder = context_builder
        self.state_updater = state_updater
        self.local_llm = local_llm
        self.groq_client = groq_client
        
    def generate_next_scene(self, user_prompt: str, active_characters: List[str], location: str, seq_index: int, max_retries: int = 2) -> Tuple[bool, str, Dict[str, Any]]:
        """
        The core State Machine loop for LoreWeaver generation.
        Returns (Success_Bool, Generated_Text, Critic_Metrics)
        """
        # 1. Fetch Working Memory and High-Priority State for Planning
        tier_1_state = self.context_builder.build_tier_1_context(active_characters, location)
        tier_2_memory = self.context_builder.build_tier_2_context(num_scenes=3)
        
        # 2. Planning Phase
        outline = self.groq_client.plan_scene(tier_1_state, tier_2_memory, user_prompt)
        if "error" in outline:
            return False, "Failed to plan scene", outline
            
        intent_summary = outline.get("intent_summary", "General conversation and movement.")
        
        # 3. Retrieve Episodic Memory & Assemble Full Context
        tier_3_episodic = self.context_builder.build_tier_3_context(intent_summary)
        full_context = f"{tier_1_state}\n\n{tier_2_memory}\n\n{tier_3_episodic}"
        
        # 4. Execution & Critique Loop
        for attempt in range(max_retries):
            # Generate prose execution
            draft_scene = self.local_llm.generate_scene(full_context, outline)
            
            # Critic Evaluation
            critic_report = self.groq_client.evaluate_consistency(tier_1_state, draft_scene)
            
            if critic_report.get("approved"):
                # Commit successes to Memory
                scene_id = f"sc_{uuid.uuid4().hex[:8]}"
                self.state_updater.commit_scene(
                    scene_id=scene_id,
                    seq_index=seq_index,
                    location=location,
                    participants=active_characters,
                    summary=intent_summary,
                    semantic_intent=intent_summary
                )
                
                # Naively parse State Drift and applying it to characters - usually requires more scrutiny
                # For MVP, just printing or logging it from the critic_report
                
                return True, draft_scene, critic_report
            else:
                # Provide feedback to the LLM on next attempt (Not implemented fully in MVP, we just rerun for varying stochasticity)
                pass 
                
        return False, draft_scene, critic_report
