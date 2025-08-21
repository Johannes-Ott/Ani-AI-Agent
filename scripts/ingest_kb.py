
import json, os
from pathlib import Path
import requests

DOCS_DIR = "docs"
KB_FILE = "data/kb.json"
OLLAMA_BASE_URL = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434").rstrip("/")

def embed(text):
    r = requests.post(f"{OLLAMA_BASE_URL}/api/embeddings", json={"model":"nomic-embed-text","input":text}, timeout=60)
    r.raise_for_status()
    data = r.json()
    if "embedding" in data:
        return data["embedding"]
    if "data" in data and data["data"] and "embedding" in data["data"][0]:
        return data["data"][0]["embedding"]
    raise RuntimeError(f"Unexpected response: {data}")

def main():
    kb = []
    Path(DOCS_DIR).mkdir(parents=True, exist_ok=True)
    for f in sorted(Path(DOCS_DIR).glob("*.txt")):
        text = f.read_text(encoding="utf-8")
        chunks = [text[i:i+800] for i in range(0, len(text), 800)]
        for i, c in enumerate(chunks, 1):
            kb.append({"source": f.name, "chunk": i, "text": c, "embedding": embed(c)})
    Path(KB_FILE).parent.mkdir(parents=True, exist_ok=True)
    Path(KB_FILE).write_text(json.dumps(kb, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Saved {len(kb)} chunks -> {KB_FILE}")

if __name__ == "__main__":
    main()
