import chromadb

class VectorDBClient:
    def __init__(self, persist_directory="./chroma_db"):
        self.client = chromadb.PersistentClient(path=persist_directory)
        self.collection = self.client.get_or_create_collection(
            name="scene_summaries",
            metadata={"hnsw:space": "cosine"}
        )
        
    def add_scene(self, scene_id: str, summary: str, metadata: dict = None):
        """
        Embeds and stores the scene summary.
        metadata could contain: participants, sequence_index, location
        """
        if metadata is None:
            metadata = {}
        self.collection.add(
            documents=[summary],
            metadatas=[metadata],
            ids=[scene_id]
        )
        
    def query_scenes(self, intent_text: str, n_results: int = 3, filter_dict: dict = None):
        """
        Queries past scenes based on semantic intent.
        filter_dict allows filtering by participants, location, etc.
        """
        results = self.collection.query(
            query_texts=[intent_text],
            n_results=n_results,
            where=filter_dict
        )
        return results
