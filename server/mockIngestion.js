// ─── Mock Ingestion ───────────────────────────────────────────────────────
// Simulates what a Gmail Pub/Sub push webhook will do when wired for real.
//
// Pub/Sub plug-in path (future):
//   POST /pubsub-push receives base64-encoded Gmail notification
//   → decode historyId → fetch new message IDs from Gmail History API
//   → for each new message: call ingest(email) with the real cleaned email
//   → replace simulateAI() body with interpretEmail() + decideActionSurface()
//
// The feedStore API (addPending / markReady) is unchanged whether
// the email source is mock or real Pub/Sub.

const { addPending, markReady } = require('./feedStore');

// Pre-written mock emails — real card shape (matches /interpret-single output)
const MOCK_EMAILS = [
  {
    senderName: 'Stripe',
    senderEmail: 'no-reply@stripe.com',
    subject: 'Your weekly revenue summary',
    date: String(Date.now()),
    threadId: 'thread-mock-001',
    threadMessageCount: 1,
    avatarUri: 'https://img.logo.dev/stripe.com?token=pk_bcvjuzCeRt6gzuz5ZoYayg',
    avatarFallbackText: 'S',
    quote: 'Revenue up 12% this week',
    summary: 'Your Stripe account processed $4,820 last week — up 12% from the previous week.',
    action: null,
    actionUrl: null,
    requiresAttention: false,
  },
  {
    senderName: 'GitHub',
    senderEmail: 'noreply@github.com',
    subject: '[email-ai] CI failed on branch main',
    date: String(Date.now() - 600_000),
    threadId: 'thread-mock-002',
    threadMessageCount: 3,
    avatarUri: 'https://img.logo.dev/github.com?token=pk_bcvjuzCeRt6gzuz5ZoYayg',
    avatarFallbackText: 'G',
    quote: 'Build failed: 2 tests did not pass',
    summary: 'The CI pipeline on main failed. Two test suites reported errors — review the logs before merging.',
    action: 'View failed run',
    actionUrl: 'https://github.com',
    requiresAttention: true,
  },
  {
    senderName: 'Linear',
    senderEmail: 'notify@linear.app',
    subject: 'Craig assigned you to ENG-142',
    date: String(Date.now() - 1_800_000),
    threadId: 'thread-mock-003',
    threadMessageCount: 1,
    avatarUri: 'https://img.logo.dev/linear.app?token=pk_bcvjuzCeRt6gzuz5ZoYayg',
    avatarFallbackText: 'L',
    quote: 'Refactor feed polling logic',
    summary: "You've been assigned to ENG-142: Refactor feed polling logic. Priority: High.",
    action: 'Open issue',
    actionUrl: 'https://linear.app',
    requiresAttention: true,
  },
  {
    senderName: 'Vercel',
    senderEmail: 'noreply@vercel.com',
    subject: 'Your deployment is live',
    date: String(Date.now() - 3_600_000),
    threadId: 'thread-mock-004',
    threadMessageCount: 1,
    avatarUri: 'https://img.logo.dev/vercel.com?token=pk_bcvjuzCeRt6gzuz5ZoYayg',
    avatarFallbackText: 'V',
    quote: 'Deployed to production successfully',
    summary: 'email-ai-server was deployed to production 1 hour ago. All checks passed.',
    action: null,
    actionUrl: null,
    requiresAttention: false,
  },
];

let emailIndex = 0;

/**
 * Simulate async AI interpretation with a random 3–6 second delay.
 *
 * Replace this body with real AI calls when Pub/Sub is wired:
 *   const [interpreted, action] = await Promise.all([
 *     interpretEmail(email),
 *     decideActionSurface(email),
 *   ]);
 *   return buildCard(email, interpreted, action);
 */
async function simulateAI(mockEmail) {
  const delayMs = 3000 + Math.random() * 3000;
  await new Promise(resolve => setTimeout(resolve, delayMs));
  return mockEmail;
}

/**
 * Ingest one email: immediately add as pending, resolve to ready after AI delay.
 * This mirrors the shape of a real Pub/Sub handler:
 *   1. notification received → addPending(id) [card appears instantly]
 *   2. fetch + clean email
 *   3. run AI → markReady(id, card) [card resolves]
 */
function ingest() {
  const template = MOCK_EMAILS[emailIndex % MOCK_EMAILS.length];
  emailIndex += 1;

  // Unique id per ingestion so restarting the server or multiple rounds work correctly
  const id = `mock-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

  addPending(id);
  console.log(`[mock-ingestion] pending  → ${id} (${template.senderName})`);

  simulateAI({ ...template, id, date: String(Date.now()) }).then(data => {
    markReady(id, data);
    console.log(`[mock-ingestion] ready    → ${id}`);
  });
}

/**
 * Start mock ingestion.
 * Sends an initial burst of emails (staggered), then adds one more on an interval.
 *
 * When Pub/Sub is wired: remove this function and register the webhook route instead.
 */
function startMockIngestion({ initialCount = 3, intervalMs = 30_000 } = {}) {
  for (let i = 0; i < initialCount; i++) {
    setTimeout(() => ingest(), i * 600);
  }
  setInterval(() => ingest(), intervalMs);
  console.log(`[mock-ingestion] started — ${initialCount} initial emails, then 1 every ${intervalMs / 1000}s`);
}

module.exports = { startMockIngestion, ingest };
