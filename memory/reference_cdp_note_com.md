# note.com CDP Draft Reference

## §1 Command

Use the shared draft helper from the shogun repo:

```bash
CDP_PORT=9234 bash scripts/note_draft.sh /abs/path/to/article.md
```

The helper launches Chrome when the CDP port is down, opens
`https://note.com/notes/new`, and saves the Markdown as a note.com draft.

## §2 Credentials

Credentials are loaded from `/mnt/c/Python_app/auto-ops/.env.note`.

Required keys:

- `NOTE_EMAIL`
- `NOTE_PASSWORD`

If either value is missing, stop and fix `.env.note`; do not prompt the user for
credentials in chat.

## §3 Login And reCAPTCHA

When note.com redirects to `/login`, `scripts/note_draft.sh` performs the login
flow automatically:

1. Fill the email and password inputs using native DOM setters plus `input` and
   `change` events.
2. Click the login button.
3. If a Google reCAPTCHA anchor iframe appears, click the checkbox by iframe
   coordinates via `Input.dispatchMouseEvent`.
4. If an image challenge appears, capture `/tmp/note_recaptcha_challenge.png`
   and wait up to 120 seconds for the agent or operator to solve it in the
   browser.

The checkbox lives in the `recaptcha/api2/anchor` iframe. Image challenges live
in the `recaptcha/api2/bframe` iframe. Cross-origin iframe DOM cannot be read
from the main frame, so the script uses page-level screenshot plus mouse
coordinates rather than direct DOM access for the challenge.

## §4 bframe Image Challenge Procedure

When the browser shows a 4x4 image challenge:

1. Capture a fresh screenshot with `Page.captureScreenshot`.
2. Locate the `recaptcha/api2/bframe` iframe rectangle from the main page.
3. Map the visible 4x4 grid to tile centers inside that rectangle.
4. Click all matching tiles with `Input.dispatchMouseEvent`.
5. Click the verify button at the lower-right of the challenge.
6. Confirm the page leaves `/login` before continuing to editor automation.

If the grid layout changes, recapture the screenshot and recompute coordinates
from the visible frame. Do not reuse stale coordinates.

## §5 Markdown Conversion Rules

- `# Title` becomes the note title textarea and is not inserted into the body.
- `## Heading` becomes an h3-style note heading.
- `---` becomes a horizontal rule.
- Consecutive plain text lines are joined into one paragraph.
- Bullet lines are inserted as separate paragraphs.

