import os
import json
import logging
from groq import Groq
from typing import Dict, Any

from llm.base_llm import BaseLLM

log = logging.getLogger("loreweaver.groq")


class GroqClient(BaseLLM):
    def __init__(self):
        api_key = os.environ.get("GROQ_API_KEY", "dummy_key_to_allow_app_startup")
        self.client = Groq(api_key=api_key)
        self.model = "openai/gpt-oss-120b"

    # ── Plan ──────────────────────────────────────────────────────────────────
    def plan_scene(self, current_state: str, working_memory: str, user_prompt: str) -> Dict[str, Any]:
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
        log.debug(f"[plan_scene] Sending prompt to Groq ({len(prompt)} chars)")

        response = self.client.chat.completions.create(
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": prompt}
            ],
            model=self.model,
            response_format={"type": "json_object"}
        )

        raw = response.choices[0].message.content
        log.debug(f"[plan_scene] Raw Groq response: {raw}")
        try:
            return json.loads(raw)
        except Exception as e:
            log.error(f"[plan_scene] Failed to parse JSON: {e}")
            return {"error": "Failed to parse JSON outline"}

    # ── Execute ───────────────────────────────────────────────────────────────
    def generate_scene(self, context: str, json_outline: Dict[str, Any]) -> str:
        system_prompt = (
            "You are a master storyteller. Your job is to EXECUTE the provided Scene Outline exactly.\n"
            "Adopt the style and tone from the Working Memory. Do NOT introduce elements not present in the Outline or State.\n"
            "Output ONLY the narrative prose. Do not include meta-commentary."
        )

        user_prompt = f"{context}\n\n### SCENE OUTLINE TO EXECUTE ###\n{json.dumps(json_outline, indent=2)}"
        log.info(f"[generate_scene] Sending to Groq  model={self.model}  context_len={len(context)}")

        try:
            response = self.client.chat.completions.create(
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt}
                ],
                model=self.model,
            )
            result = response.choices[0].message.content or ""
            log.info(f"[generate_scene] Groq returned {len(result)} chars")
            return result
        except Exception as e:
            log.error(f"[generate_scene] Groq request failed: {e}")
            return f"Error from Groq LLM: {str(e)}"

    # ── Critique ──────────────────────────────────────────────────────────────
    def evaluate_consistency(self, state: str, scene_text: str) -> Dict[str, Any]:
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

        prompt = f"### STATE CONSTRAINTS ###\n{state}\n\n### SCENE TEXT ###\n{scene_text[:3000]}"
        log.debug(f"[evaluate_consistency] Sending to Groq critic ({len(prompt)} chars)")

        response = self.client.chat.completions.create(
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": prompt}
            ],
            model=self.model,
            response_format={"type": "json_object"}
        )

        raw = response.choices[0].message.content
        log.debug(f"[evaluate_consistency] Raw Groq critic response: {raw}")
        try:
            return json.loads(raw)
        except Exception as e:
            log.error(f"[evaluate_consistency] Failed to parse JSON: {e}")
            return {"approved": False, "error": "Critic evaluation failed"}
