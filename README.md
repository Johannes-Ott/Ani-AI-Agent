# Ani AI Agent v32.3 (Basis)

## Start
1. Docker Desktop (Linux-Engine) & Node.js 18+ installieren.
2. Ordnerstruktur wie vorgegeben anlegen.
3. `start_ani.bat` doppelklicken.

## Was jetzt geht
- Docker wird gestartet (Service/GUI/Kontext).
- n8n & Ollama laufen per `docker compose`.
- Desktop-App wird gestartet.
- Beim Schließen der App: `compose down`, Lock/Logs bleiben sauber.
- Logdatei: `.\logs\launch_ani.log`.

## Nächste Schritte
- Phase 2: Workflow-Import-Button in der App (API-Key + Base URL).
- Phase 3: Python-Sandbox (Docker-Service, Ordner `sandbox\`).
- Phase 4: Unity/VS-Integration, geordnete Ablage in Zielprojekt.
- Phase 5: docs/ als Wissensspeicher (Workflows nutzen die Inhalte).
