from abc import ABC, abstractmethod
from typing import Dict, Any, List


class BaseLLM(ABC):
    """Unified interface every LLM backend must implement."""

    @abstractmethod
    def plan_scene(self, current_state: str, working_memory: str, user_prompt: str) -> Dict[str, Any]:
        """Draft a JSON Scene Outline (intent, emotional shift, events)."""
        ...

    @abstractmethod
    def generate_scene(self, context: str, json_outline: Dict[str, Any]) -> str:
        """Execute the outline into narrative prose."""
        ...

    @abstractmethod
    def evaluate_consistency(self, state: str, scene_text: str) -> Dict[str, Any]:
        """Critic model — check the scene against state constraints."""
        ...
