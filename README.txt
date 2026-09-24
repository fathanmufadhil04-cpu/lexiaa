LEXIAA NEW V1 — CORE FIXES V3

This package continues the current Lexiaa project and fixes the bugs found during testing.

FILES TO REPLACE IN THE EXISTING PROJECT
- index.html
- config.js
- manifest.webmanifest
- sw.js
- icon-192.png
- icon-512.png

SUPABASE
- Run the updated LEXIAA-NEW-SUPABASE.sql in the NEW Supabase project's SQL Editor.
- The SQL is safe to re-run for the existing tables/policies in this build and adds the leaderboard view.
- Keep only the Supabase URL + Publishable/Anon key in config.js. Never put service_role or any secret in frontend code.

FIXES IN THIS PASS
- Profile avatar in the top-right is now a true edge-to-edge circular image with no inner padding.
- Photo list thumbnails can be opened into a full-screen private photo viewer.
- Photo viewer supports zoom buttons, double-tap zoom, mouse-wheel zoom, and two-finger pinch zoom on touch devices.
- Photo preview still uses private signed URLs.
- Games now show a cross-account leaderboard for Quick Tap and Quiz, using only display name + score fields.
- Personal score History remains private to the logged-in account.
- Signup now gives a clearer message when Supabase Auth rate-limits email signup attempts.

IMPORTANT ABOUT THE SIGNUP RATE-LIMIT MESSAGE
The "email rate limit exceeded" message is from Supabase Auth, not from the Lexiaa UI. Supabase's hosted email sender has a low email-sending quota, and Auth also rate-limits signup requests. For development, wait for the limit to refill or configure the project's Auth settings/custom SMTP. Do not try to bypass the limit in frontend code.

TEST ORDER
1. Profile -> change avatar -> check the top-right avatar.
2. Photos -> Add -> tap/click the thumbnail or preview button -> zoom.
3. Games -> save a score -> check History and Leaderboard.
4. Create another account after the Supabase email rate limit has cleared -> check that its leaderboard score can appear.

NOTE ON LEADERBOARD SECURITY
The leaderboard intentionally exposes only game score + display name through a dedicated database view. It does not expose profile email. Client-side games can still be cheated by a modified browser, so if competitive integrity matters later, score validation should move to a server-side Edge Function.

AI NEXT STEP
The AI UI remains safely gated behind a backend. Deploy a Supabase Edge Function and keep provider API keys server-side; never place an AI secret in config.js.
