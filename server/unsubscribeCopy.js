// The unsubscribe status contract — `Feature · Unsubscribe agent /
// 09 · Status vocabulary`, transcribed from Figma.
//
// The enum is fixed, the sentence is free. `step` drives the tray's shape, its
// counter and its progress segments, so it has to be deterministic; the
// sentence is written by the model from what it actually found on the page, so
// it stays alive across runs. Never let the model invent a step.
//
// There is deliberately no `error` here. A failure that is retryable, a page
// with nothing to click, a CAPTCHA that wants a human, and a sender who
// confirmed and then wrote anyway are four different facts, and calling them
// all "error" throws away the only useful thing the agent learned.

const STEPS = [
  'queued', 'navigating', 'analyzing', 'filling',
  'clicking', 'verifying', 'done',
  'no_link', 'needs_you', 'failed', 'still_sending',
];

// Counter semantics per step — drives the tray, not the copy.
const COUNTER = {
  navigating: 'site',  analyzing: 'site',
  filling:    'field', clicking:  'site',
  verifying:  'site',
};

// Static fallbacks. Used when the model is slow, rate-limited or offline.
// Deliberately plain: a fallback that tries to be charming reads as a bug
// the moment it repeats. Never user-visible twice in one run.
const FALLBACK = {
  queued:        () => 'Lining this one up',
  navigating:    (s) => `Opening ${s}'s page`,
  analyzing:     (s) => `Reading ${s}'s page`,
  filling:       (f) => f ? `Filling in "${f}"` : 'Filling in their form',
  clicking:      () => 'Confirming',
  verifying:     () => 'Checking it took',
  done:          (s) => `${s} confirmed it`,
  no_link:       (s) => `${s} has no unsubscribe link`,
  needs_you:     (s) => `${s} wants a human`,
  failed:        (s) => `Could not finish with ${s}`,
  still_sending: (s) => `${s} is still writing to you`,
};

// Once a run reaches one of these it is over. `failed` is retryable and is
// auto-retried once before the user is ever shown it, but by the time it is
// emitted it is as terminal as the rest.
const TERMINAL_STEPS = new Set(['done', 'no_link', 'needs_you', 'failed', 'still_sending']);

// `filling` is the one step whose fallback takes the field label rather than
// the sender — the counter has switched from sites to fields there, and so has
// the subject of the sentence.
const FIELD_SCOPED_STEPS = new Set(['filling']);

// `done` is the only state allowed to use the word "unsubscribed". Claiming it
// for a page that was never read back — or for a local filter — is the one lie
// that kills this feature.
const CLAIM_PATTERN = /\bunsubscribed\b/i;

function isStep(value) {
  return typeof value === 'string' && STEPS.includes(value);
}

function isTerminal(step) {
  return TERMINAL_STEPS.has(step);
}

/// Returns the step only if it is a member of the closed set, and `null`
/// otherwise. Every step that reaches the wire goes through here, so a model
/// that decides to invent `"almost_done"` loses its step rather than the tray
/// losing its shape.
function sanitizeStep(value) {
  return isStep(value) ? value : null;
}

/// The counter the tray should draw for a step: `site`, `field`, or none.
/// `analyzing` deliberately has no sub-counter — nobody cares how many page
/// elements were scanned.
function counterFor(step) {
  return COUNTER[step] ?? null;
}

function claimsUnsubscribed(text) {
  return CLAIM_PATTERN.test(String(text ?? ''));
}

/// The plain sentence for a step. `senderName` for every step except
/// `filling`, which speaks about the field in front of it.
function fallbackMessage(step, { senderName, fieldLabel } = {}) {
  const write = FALLBACK[step];
  if (!write) return '';
  return write(FIELD_SCOPED_STEPS.has(step) ? (fieldLabel || '') : (senderName || 'them'));
}

module.exports = {
  STEPS,
  COUNTER,
  FALLBACK,
  TERMINAL_STEPS,
  isStep,
  isTerminal,
  sanitizeStep,
  counterFor,
  claimsUnsubscribed,
  fallbackMessage,
};
