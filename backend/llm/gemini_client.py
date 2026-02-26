import os
import json
import google.generativeai as genai
from typing import Dict, Any, List

class GeminiSynthesizer:
    def __init__(self):
        # Assumes GOOGLE_API_KEY is in environment variables
        genai.configure(api_key=os.environ.get("GOOGLE_API_KEY"))
        # Using 1.5 Pro for its massive context window and strong reasoning
        self.model = genai.GenerativeModel('gemini-1.5-pro')
        
    def synthesize_long_term_memory(self, recent_scenes: List[str], current_states: str) -> Dict[str, Any]:
        """
        Runs periodically (e.g., every 5-10 scenes). Reads raw generated text to re-align Structured DB
        and generate precise vector summaries.
        """
        system_prompt = (
            "You are the Synthesizer and Librarian for a massive story. "
            "Analyze the recent scenes and the current character/world states. "
            "Output ONLY valid JSON detailing state updates required to align the Ground Truth "
            "with the narrative that actually happened. Also provide concise summaries of each new scene.\n"
            "Schema:\n"
            "{\n"
            '  "state_patches": {\n'
            '     "character_id_1": {"key_to_update": "new_value", "key_to_remove": null}\n'
            '  },\n'
            '  "vector_summaries": [\n'
            '     {"scene_id": "sc_001", "summary": "Semantic summary for RAG", "emotional_valance": "tense"}\n'
            '  ],\n'
            '  "major_drift_warning": "Any long-term inconsistencies detected (or null)"\n'
            "}"
        )
        
        raw_text = "\n\n---\n\n".join(recent_scenes)
        prompt = f"{system_prompt}\n\n### CURRENT STATES ###\n{current_states}\n\n### RECENT NARRATIVE CHUNK ###\n{raw_text}"
        
        # Gemini 1.5 Pro natively supports JSON output structure in the prompt
        response = self.model.generate_content(prompt, generation_config={"response_mime_type": "application/json"})
        
        try:
            return json.loads(response.text)
        except Exception as e:
            return {"error": f"Synthesis failed: {str(e)}"}
