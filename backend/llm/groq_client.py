import os
import json
from groq import Groq
from typing import Dict, Any

class GroqClient:
    def __init__(self):
        # Assumes GROQ_API_KEY is in environment variables
        self.client = Groq()
        self.model = "llama3-70b-8192"
        
    def plan_scene(self, current_state: str, working_memory: str, user_prompt: str) -> Dict[str, Any]:
        """
        Drafts a JSON Scene Outline outlining intent, emotional shifts, and events.
        """
        system_prompt = (
            "You are a master storyteller's Planner. Output ONLY valid JSON outlining the next scene.\n"
            "Schema:\n"
            "{\n"
            '  "intent_summary": "1 sentence semantic summary",\n'
            '  "target_emotional_shift": "e.g., Hope to Despair",\n'
            '  "required_actions": ["List", "of", "events"]\n'
            "}"
        )
        
        prompt = f"### STATE ###\n{current_state}\n\n### RECENT MEMORY ###\n{working_memory}\n\n### USER PROMPT ###\n{user_prompt}"
        
        response = self.client.chat.completions.create(
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": prompt}
            ],
            model=self.model,
            response_format={"type": "json_object"}
        )
        
        try:
            return json.loads(response.choices[0].message.content)
        except Exception:
            return {"error": "Failed to parse JSON outline"}

    def evaluate_consistency(self, state: str, scene_text: str) -> Dict[str, Any]:
        """
        The Critic Model. Evaluates scene_text against given state for drift or violations.
        """
        system_prompt = (
            "You are the Consistency Critic. Evaluate the Scene Text against the State constraints.\n"
            "Output ONLY valid JSON.\n"
            "Schema:\n"
            "{\n"
            '  "approved": boolean,\n'
            '  "metrics": {\n'
            '     "trait_adherence_score": float (0-1),\n'
            '     "temporal_continuity_flags": int (0 is perfect),\n'
            '     "state_drift_detected": ["list", "of", "unprompted", "state changes"]\n'
            '  },\n'
            '  "justification": "Explanation"\n'
            "}"
        )
        
        prompt = f"### STATE CONSTRAINTS ###\n{state}\n\n### SCENE TEXT ###\n{scene_text}"
        
        response = self.client.chat.completions.create(
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": prompt}
            ],
            model=self.model,
            response_format={"type": "json_object"}
        )
        
        try:
            return json.loads(response.choices[0].message.content)
        except Exception:
            return {"approved": False, "error": "Critic evaluation failed"}
