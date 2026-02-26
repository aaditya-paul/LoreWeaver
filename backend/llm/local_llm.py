import requests
import json
import logging
from typing import Dict, Any

log = logging.getLogger("loreweaver.local_llm")

class LocalLLMClient:
    def __init__(self, base_url="http://localhost:11434", model="llama3:8b"):
        self.base_url = base_url
        self.model = model
        
    def generate_scene(self, context: str, json_outline: Dict[str, Any]) -> str:
        """
        Executes the scene by adhering to the JSON outline while adopting the context's tone.
        """
        system_prompt = (
            "You are a master storyteller. Your job is to EXECUTE the provided Scene Outline exactly.\n"
            "Adopt the style and tone from the Working Memory. Do NOT introduce elements not present in the Outline or State.\n"
            "Output ONLY the narrative prose. Do not include meta-commentary."
        )
        
        user_prompt = f"{context}\n\n### SCENE OUTLINE TO EXECUTE ###\n{json.dumps(json_outline, indent=2)}"
        
        payload = {
            "model": self.model,
            "prompt": f"<|system|>\n{system_prompt}\n<|user|>\n{user_prompt}\n<|assistant|>\n",
            "stream": False,
            "options": {
                "temperature": 0.7,
                "num_predict": 2500
            }
        }
        
        log.info(f"[generate_scene] Sending to Ollama  model={self.model}  context_len={len(context)}")
        log.debug(f"[generate_scene] Outline: {json.dumps(json_outline)}")
        try:
            response = requests.post(f"{self.base_url}/api/generate", json=payload)
            response.raise_for_status()
            result = response.json().get("response", "")
            log.info(f"[generate_scene] Ollama returned {len(result)} chars")
            log.debug(f"[generate_scene] Output (first 500 chars):\n{result[:500]}")
            return result
        except requests.exceptions.RequestException as e:
            log.error(f"[generate_scene] Ollama request failed: {e}")
            return f"Error connecting to Local LLM: {str(e)}"
