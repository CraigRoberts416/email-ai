# Zero Shot

Zero shot is the core product philosophy.

The model generates the app's copy at runtime from the actual context it has access to. Email interpretations, summaries, quotes, recaps, and personalized messages must never be replaced by invented or prewritten interpretations.

This means:

- No prescribed phrases, examples, or templates in prompts
- Tone is defined once (see `server/prompts/tone.md`) and injected into every prompt via `{{tone}}`
- The model is trusted to generate freely within that tone
- Copy that reflects real context (sender name, page content, field labels) is always preferred over generic fallbacks

The goal is an app that feels alive — not one that rotates through a list of pre-written witticisms.

When adding a new prompt or modifying an existing one, do not add example outputs. Describe the job, inject the tone, and let the model work.

## Operational fallback exception

Short, literal fallback labels may keep navigation, settings, loading, recovery, and accessibility controls usable while generated UI copy is unavailable. This is a narrow implementation resilience exception: a failed copy request must not prevent someone from retrying, returning to their inbox, or understanding a control.

Generated UI copy remains preferred. Fallbacks must describe a known interface action or state, never invent an email interpretation, claim an action succeeded, or turn missing data into an empty inbox. Completion language describes a cleared review feed; it does not claim every email obligation is resolved.
