import requests
import json
import logging
from typing import Dict, Any

from llm.base_llm import BaseLLM

log = logging.getLogger("loreweaver.local_llm")

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


class LocalLLMClient(BaseLLM):
    def __init__(self, base_url="http://localhost:11434", model="dolphin3:latest"):
        self.base_url = base_url
        self.model = model

    def _call_ollama(self, system_prompt: str, user_prompt: str, json_mode: bool = False) -> str:
        """Low-level helper to call Ollama generate endpoint."""
        fmt = "json" if json_mode else ""
        payload = {
            "model": self.model,
            "system": system_prompt,
            "prompt": user_prompt,
            "stream": False,
            "format": fmt if fmt else None,
            "options": {
                "temperature": 0.7,
                "num_predict": 2500,
            },
        }
        # Remove None values
        payload = {k: v for k, v in payload.items() if v is not None}

        log.info(f"[_call_ollama] model={self.model}  json_mode={json_mode}  prompt_len={len(user_prompt)}")
        response = requests.post(f"{self.base_url}/api/generate", json=payload)
        response.raise_for_status()
        return response.json().get("response", "")

    # -- Plan ------------------------------------------------------------------
    def plan_scene(self, current_state: str, working_memory: str, user_prompt: str) -> Dict[str, Any]:
        prompt = (
            f"### STATE ###\n{current_state}\n\n"
            f"### RECENT MEMORY ###\n{working_memory}\n\n"
            f"### USER PROMPT ###\n{user_prompt}"
        )
        log.debug(f"[plan_scene] Sending to Ollama ({len(prompt)} chars)")
        try:
            raw = self._call_ollama(PLAN_SYSTEM, prompt, json_mode=True)
            log.debug(f"[plan_scene] Raw response: {raw[:500]}")
            return json.loads(raw)
        except json.JSONDecodeError as e:
            log.error(f"[plan_scene] JSON parse error: {e}")
            return {"error": "Failed to parse JSON outline from Local LLM"}
        except requests.exceptions.RequestException as e:
            log.error(f"[plan_scene] Ollama request failed: {e}")
            return {"error": f"Local LLM unreachable: {e}"}

    # -- Execute ---------------------------------------------------------------
    def generate_scene(self, context: str, json_outline: Dict[str, Any]) -> str:
        user_prompt = f"{context}\n\n### SCENE OUTLINE TO EXECUTE ###\n{json.dumps(json_outline, indent=2)}"
        log.info(f"[generate_scene] Sending to Ollama  model={self.model}  context_len={len(context)}")
        try:
            result = self._call_ollama(EXECUTE_SYSTEM, user_prompt)
            log.info(f"[generate_scene] Ollama returned {len(result)} chars")
            return result
        except requests.exceptions.RequestException as e:
            log.error(f"[generate_scene] Ollama request failed: {e}")
            return f"Error connecting to Local LLM: {str(e)}"

    # -- Critique --------------------------------------------------------------
    def evaluate_consistency(self, state: str, scene_text: str) -> Dict[str, Any]:
        prompt = f"### STATE CONSTRAINTS ###\n{state}\n\n### SCENE TEXT ###\n{scene_text[:3000]}"
        log.debug(f"[evaluate_consistency] Sending to Ollama critic ({len(prompt)} chars)")
        try:
            raw = self._call_ollama(CRITIC_SYSTEM, prompt, json_mode=True)
            log.debug(f"[evaluate_consistency] Raw response: {raw[:500]}")
            return json.loads(raw)
        except json.JSONDecodeError as e:
            log.error(f"[evaluate_consistency] JSON parse error: {e}")
            return {"approved": False, "error": "Critic evaluation failed (parse error)"}
        except requests.exceptions.RequestException as e:
            log.error(f"[evaluate_consistency] Ollama request failed: {e}")
            return {"approved": False, "error": f"Local LLM unreachable: {e}"}
