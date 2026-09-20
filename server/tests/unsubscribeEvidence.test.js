const { test } = require('node:test');
const assert = require('node:assert/strict');
const { affirmativeRemoval, confirmationQuote } = require('../unsubscribeEvidence');
const { runUnsubscribeAgent } = require('../unsubscribeAgent');

const snapshot = (bodyText, actions = []) => ({ bodyText, title: 'Email preferences',
  url: 'https://sender.example.invalid/preferences', fields: [], actions });

test('confirmation retains the sender’s explicit removal statement, including already-completed one-click pages', () => {
  for (const text of ['You are unsubscribed.', 'You’re now unsubscribed from our newsletter.',
    'You have been successfully unsubscribed.', 'You have unsubscribed from our newsletter.',
    'You have been removed from our mailing list.', 'Your email address has been removed from the email list.',
    "We've removed you from our mailing list.", 'You no longer receive promotional emails.',
    'You are no longer subscribed to our newsletter.', 'Successfully unsubscribed']) {
    assert.equal(affirmativeRemoval(text), true, text);
    assert.equal(confirmationQuote(snapshot(`Email preferences\n${text}\nReturn home`)), text);
  }
});

test('instructions, conditionals, failure states and generic saved preferences never confirm removal', () => {
  for (const text of ['Click unsubscribe and you will no longer receive emails.',
    'You will no longer receive our emails.', 'You will no longer receive promotional emails.',
    'If you unsubscribe, you will no longer receive emails.', 'You will no longer receive emails after you click Confirm.',
    'You have not been unsubscribed.', 'You have been unsubscribed?', 'You have been unsubscribed if you completed the form.',
    'You have been removed from your shopping cart.', 'You might be successfully unsubscribed.',
    'Unsubscribe successfully by clicking below.', 'Preferences saved.', 'Your preferences have been updated.',
    'Email settings saved.', 'Subscription status updated.', 'No longer receive',
    'Your unsubscribe request was received.', 'Removal is pending.', 'Are you sure you want to unsubscribe?',
    'We could not remove you from our mailing list.']) {
    assert.equal(confirmationQuote(snapshot(text)), null, text);
  }
  assert.equal(confirmationQuote({ ...snapshot(''), title: 'You are unsubscribed',
    url: 'https://sender.example.invalid/unsubscribe/success?status=unsubscribed' }), null,
  'Neither a page title nor success-looking URL is a removal statement');
});

test('a model quote must occur in affirmative source context, not just be a promising substring', () => {
  const quote = 'You have been unsubscribed.';
  assert.equal(confirmationQuote(snapshot(quote), quote), quote);
  assert.equal(confirmationQuote(snapshot('Preferences saved.'), quote), null, 'fabricated quote');
  assert.equal(confirmationQuote(snapshot('If you have been unsubscribed, you may resubscribe.'), 'you have been unsubscribed'), null);
  assert.equal(confirmationQuote(snapshot('You will no longer receive emails after you click Confirm.'), 'You will no longer receive emails'), null);
  assert.equal(confirmationQuote(snapshot(quote), ''), null, 'empty model quote');
});

function browserFixture(snapshots) {
  let index = 0; let clicks = 0; let closed = false;
  const click = async () => { clicks++; index = Math.min(index + 1, snapshots.length - 1); };
  const context = { waitForEvent: async () => null, close: async () => { closed = true; } };
  const locator = { first() { return this; }, scrollIntoViewIfNeeded: async () => {}, click,
    fill: async () => {}, check: async () => {}, uncheck: async () => {}, selectOption: async () => {} };
  const page = { goto: async () => {}, waitForLoadState: async () => {}, waitForTimeout: async () => {},
    evaluate: async (_fn, args) => args?.maxBodyText ? snapshots[index] : false,
    locator: () => locator, context: () => context, mouse: { click }, screenshot: async () => Buffer.from('synthetic') };
  context.newPage = async () => page;
  return { browser: { newContext: async () => context }, get clicks() { return clicks; }, get closed() { return closed; } };
}
function modelFixture(done, vision = done) {
  return {
    responses: { create: async () => ({ output_text: JSON.stringify(done) }) },
    chat: { completions: { create: async ({ model }) => ({ choices: [{ message: {
      content: model === 'gpt-4o' ? JSON.stringify(vision) : 'Checking the sender page',
    } }] }) } },
  };
}
const action = text => ({ id: '1', tag: 'button', text, href: '', disabled: false });
async function run(fixture, openai = null) {
  return runUnsubscribeAgent({ browser: fixture.browser, unsubscribeUrl: 'https://sender.example.invalid/preferences',
    userEmail: 'reader@example.invalid', senderName: 'Synthetic sender', emit() {}, openai });
}

test('production agent does not finish on pre-action instructions or generic post-action saving', async () => {
  const f = browserFixture([snapshot('Click unsubscribe so you will no longer receive emails.', [action('Unsubscribe')]),
    snapshot('Your preferences have been saved.')]);
  const result = await run(f);
  assert.equal(f.clicks, 1, 'conditional text cannot bypass the real action');
  assert.equal(result.step, 'needs_you'); assert.equal(result.outcome, 'outcome_unknown');
  assert.equal(result.handoffURL, 'https://sender.example.invalid/preferences');
  assert.equal(f.closed, true);
});

test('production agent preserves exact affirmative evidence before or after a real action', async () => {
  const quote = 'You have been successfully unsubscribed.';
  for (const pages of [[snapshot(quote)], [snapshot('Unsubscribe from our emails.', [action('Unsubscribe')]), snapshot(quote)]]) {
    const f = browserFixture(pages);
    const result = await run(f);
    assert.equal(result.step, 'done'); assert.equal(result.outcome, 'sender_confirmed');
    assert.ok(result.evidence.includes(`“${quote}”`), 'receipt contains the actual confirmation');
    assert.equal(f.clicks, pages.length - 1); assert.equal(f.closed, true);
  }
});

test('standalone future-tense copy before submission cannot skip the action or become confirmation evidence', async () => {
  const promise = 'You will no longer receive our emails.';
  const confirmation = 'You have been removed from our mailing list.';
  const f = browserFixture([snapshot(promise, [action('Unsubscribe')]), snapshot(confirmation)]);
  const result = await run(f);
  assert.equal(f.clicks, 1, 'future-tense explanation cannot finish the flow before submission');
  assert.equal(result.step, 'done'); assert.equal(result.outcome, 'sender_confirmed');
  assert.ok(result.evidence.includes(confirmation));
  assert.ok(!result.evidence.includes(promise));
  assert.equal(f.closed, true);
});

test('unsubstantiated text-model and vision done verdicts become a usable human check', async () => {
  for (const actions of [[action('Continue')], []]) {
    const f = browserFixture([snapshot('Preferences saved. Click confirm to stop receiving email.', actions)]);
    const result = await run(f, modelFixture({ action: 'done', reason: 'looks complete',
      confirmationQuote: 'You have been unsubscribed.' }));
    assert.equal(result.step, 'needs_you'); assert.equal(result.outcome, 'outcome_unknown');
    assert.equal(result.handoffURL, 'https://sender.example.invalid/preferences');
    assert.equal(f.clicks, 0); assert.equal(f.closed, true);
    assert.ok(!result.evidence.includes('You have been unsubscribed.'), 'invented quote cannot enter receipt evidence');
  }
});
