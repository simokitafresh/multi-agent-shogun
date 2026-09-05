# cmd_4416 post-deploy check

Created: 2026-08-30T16:05:00+09:00

## Preconditions

- Render frontend deploy status is `live` for the published cmd_4416 commit.
- `API_HOST` exists on `srv-d4ja8pp5pdvs739a5fsg` and equals `NEXT_PUBLIC_API_HOST`; the exported client uses `NEXT_PUBLIC_API_HOST`.
- The Render frontend remains a static site (`npm run build`, publish directory `out`).
- Use the isolated CDP profile; do not reuse the Lord's Chrome profile.

## One-pass checks

1. HTTP: `GET https://dm-signal-frontend.onrender.com/login` returns 200.
2. API: `GET https://dm-signal-backend.onrender.com/api/public/showcase` returns 200 and `plans[].n` is Basic=3, Standard=17, Premium=25.
3. Mobile viewport: at 375×667, a visible `Sign in` button has its complete bounding box inside the initial viewport.
4. Table: the rendered login page contains all three plan rows and the Basic-DualMomentum hero row.
5. Blackout banner: the month-end message is rendered from the current blackout response; it contains no date, `today`, `soon`, `early`, `近日`, `¥`, or `円` wording.
6. Static/client boundary: `out/login/index.html` contains the H1 and metadata description; after client fetch, the DOM contains `Data through` and at least one numeric value from the showcase response.
7. Regression boundary: successful login redirects to `/`; wrong password and expired-password paths retain their dedicated error copy.

## Binary result

PASS only when checks 1–7 all pass in the same deployed revision. Any mismatch is BLOCK; capture the deployed commit, Render deploy ID, HTTP statuses, viewport bounding box, row labels, banner text, and failing check before rollback or correction.
