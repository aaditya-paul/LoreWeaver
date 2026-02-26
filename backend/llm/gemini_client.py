import os
import json
import logging
import google.generativeai as genai
from typing import Dict, Any, List

from llm.base_llm import BaseLLM

log = logging.getLogger("loreweaver.gemini")

PLAN_SYSTEM = (
    "You are a master storyteller's Planner. Output ONLY valid JSON outlining the next scene.\n"
    "Schema:\n"
    '{\n'
    '  "intent_summary": "1 sentence semantic summary",\n'
    '  "target_emotional_shift": "e.g., Hope to Despair",\n'
    '  "required_actions": ["List", "of", "events"]\n'
    '}'
)

EXECUTE_SYSTEM = (
    "You are a master storyteller. Your job is to EXECUTE the provided Scene Outline exactly.\n"
    "Adopt the style and tone from the Working Memory. Do NOT introduce elements not present in the Outline or State.\n"
    "Output ONLY the narrative prose. Do not include meta-commentary."
)

CRITIC_SYSTEM = (
    "You are the Consistency Critic. Evaluate the Scene Text against the State constraints.\n"
    "Output ONLY valid JSON.\n"
    "Schema:\n"
    '{\n'
    '  "approved": boolean,\n'
    '  "metrics": {\n'
    '     "trait_adherence_score": float (0-1),\n'
    '     "temporal_continuity_flags": int (0 is perfect),\n'
    '     "state_drift_detected": ["list", "of", "unprompted", "state changes"]\n'
    '  },\n'
    '  "justification": "Explanation"\n'
    '}'
)


class GeminiClient(BaseLLM):
    def __init__(self):
        genai.configure(api_key=os.environ.get("GOOGLE_API_KEY"))
        self.model = genai.GenerativeModel("gemini-2.5-flash")

    def _generate(self, prompt: str, json_mode: bool = False) -> str:
        config = {}
        if json_mode:
            config["response_mime_type"] = "application/json"
        response = self.model.generate_content(prompt, generation_config=config)
        return response.text

    # -- Plan ------------------------------------------------------------------
    def plan_scene(self, current_state: str, working_memory: str, user_prompt: str) -> Dict[str, Any]:
        prompt = (
            f"{PLAN_SYSTEM}\n\n"
            f"### STATE ###\n{current_state}\n\n"
            f"### RECENT MEMORY ###\n{working_memory}\n\n"
            f"### USER PROMPT ###\n{user_prompt}"
        )
        log.debug(f"[plan_scene] Sending to Gemini ({len(prompt)} chars)")
        try:
            raw = self._generate(prompt, json_mode=True)
            log.debug(f"[plan_scene] Raw response: {raw[:500]}")
            return json.loads(raw)
        except json.JSONDecodeError as e:
            log.error(f"[plan_scene] JSON parse error: {e}")
            return {"error": "Failed to parse JSON outline from Gemini"}
        except Exception as e:
            log.error(f"[plan_scene] Gemini request failed: {e}")
            return {"error": f"Gemini error: {e}"}

    # -- Execute ---------------------------------------------------------------
    def generate_scene(self, context: str, json_outline: Dict[str, Any]) -> str:
        prompt = (
            f"{EXECUTE_SYSTEM}\n\n"
            f"{context}\n\n"
            f"### SCENE OUTLINE TO EXECUTE ###\n{json.dumps(json_outline, indent=2)}"
        )
        log.info(f"[generate_scene] Sending to Gemini  context_len={len(context)}")
        try:
            result = self._generate(prompt)
            log.info(f"[generate_scene] Gemini returned {len(result)} chars")
            return result
        except Exception as e:
            log.error(f"[generate_scene] Gemini request failed: {e}")
            return f"Error from Gemini: {str(e)}"

    # -- Critique --------------------------------------------------------------
    def evaluate_consistency(self, state: str, scene_text: str) -> Dict[str, Any]:
        prompt = (
            f"{CRITIC_SYSTEM}\n\n"
            f"### STATE CONSTRAINTS ###\n{state}\n\n"
            f"### SCENE TEXT ###\n{scene_text[:3000]}"
        )
        log.debug(f"[evaluate_consistency] Sending to Gemini critic ({len(prompt)} chars)")
        try:
            raw = self._generate(prompt, json_mode=True)
            log.debug(f"[evaluate_consistency] Raw response: {raw[:500]}")
            return json.loads(raw)
        except json.JSONDecodeError as e:
            log.error(f"[evaluate_consistency] JSON parse error: {e}")
            return {"approved": False, "error": "Critic evaluation failed (parse error)"}
        except Exception as e:
            log.error(f"[evaluate_consistency] Gemini request failed: {e}")
            return {"approved": False, "error": f"Gemini error: {e}"}

    # -- Legacy method kept for backwards compatibility ------------------------
    def synthesize_long_term_memory(self, recent_scenes: List[str], current_states: str) -> Dict[str, Any]:
        system_prompt = (
            "You are the Synthesizer and Librarian for a massive story. "
            "Analyze the recent scenes and the current character/world states. "
            "Output ONLY valid JSON detailing state updates required to align the Ground Truth "
            "with the narrative that actually happened. Also provide concise summaries of each new scene.\n"
            "Schema:\n"
            '{\n'
            '  "state_patches": {\n'
            '     "character_id_1": {"key_to_update": "new_value", "key_to_remove": null}\n'
            '  },\n'
            '  "vector_summaries": [\n'
            '     {"scene_id": "sc_001", "summary": "Semantic summary for RAG", "emotional_valance": "tense"}\n'
            '  ],\n'
            '  "major_drift_warning": "Any long-term inconsistencies detected (or null)"\n'
            '}'
        )
        raw_text = "\n\n---\n\n".join(recent_scenes)
        prompt = f"{system_prompt}\n\n### CURRENT STATES ###\n{current_states}\n\n### RECENT NARRATIVE CHUNK ###\n{raw_text}"

        try:
            return json.loads(self._generate(prompt, json_mode=True))
        except Exception as e:
            return {"error": f"Synthesis failed: {str(e)}"}
