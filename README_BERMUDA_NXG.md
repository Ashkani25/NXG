# BERMUDA NXG
Online disc football. App: `www/` (Capacitor, Android). Backend: `server/` (Colyseus + Express + MongoDB).
* Offline practice works with empty `API_URL` in `www/js/config.js`.
* Run the server: `cd server && cp .env.example .env && docker compose up -d --build` (needs Docker).
* Match = 5 minutes, unlimited goals, golden goal if tied.
* Full engineering plan for the AI agent: `AGENT_PROMPT.md`.
