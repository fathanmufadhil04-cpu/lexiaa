LEXIAA NEW V1 — CORE FOUNDATION

This is a fresh Lexiaa build. The existing GitHub repository can stay the same; replace its deployed files with this project.

SETUP
1. Use the NEW Supabase project.
2. Run LEXIAA-NEW-SUPABASE.sql in Supabase SQL Editor.
3. Keep only the Supabase URL + Publishable/Anon key in config.js. Never put service_role or any secret in frontend code.
4. Deploy through the existing GitHub -> Cloudflare Pages workflow.
5. If an older build appears after deploy, hard-refresh once; the service-worker cache was bumped to v2.

WORKING IN THIS PASS
- Login / signup.
- Automatic profile row on signup.
- RLS-isolated database records.
- Private avatar storage.
- Photos: upload, preview, signed URL, download, delete.
- Music: upload, playback, download, delete.
- Profile: display name, avatar, theme.
- Games: Quick Tap + Quiz + per-user score history.
- AI page remains safely gated behind a backend; no AI secret is exposed in the browser.

AI NEXT STEP
The frontend already has the request path for a Supabase Edge Function at /functions/v1/ai. Deploy a server-side AI function and set AI_ENABLED=true only after the function is ready. Store the provider API key as a Supabase Edge Function secret, never in config.js.
