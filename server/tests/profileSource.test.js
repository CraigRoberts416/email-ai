const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createProfileSource } = require('../profileSource');
const { extractAttachments } = require('../emailAttachments');

const image = { extractHtml: () => '', pickCandidates: () => [], resolveBest: async () => null };
function full() {
  return { payload: { mimeType: 'multipart/mixed', parts: [
    { mimeType: 'text/plain', body: { data: Buffer.from('Original sender words.').toString('base64url') } },
    ...Array.from({ length: 10 }, (_, index) => ({ mimeType: 'application/pdf', filename: `small-${index}.pdf`,
      body: { attachmentId: `file-${index}`, size: 1024 } })),
  ] } };
}
async function until(condition) {
  for (let attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.fail('Source inspection did not settle');
}

test('visible-page inspection is nonblocking, coalesced and bounded; text/files come from the original payload', async () => {
  const gates = [], saved = [];
  const source = createProfileSource({ concurrency: 4, image,
    fetchFullMessage: async (userId, messageId) => new Promise(resolve => gates.push({ userId, messageId, resolve })),
    saveSource: async (userId, messageId, content) => saved.push({ userId, messageId, content }),
  });
  const records = Array.from({ length: 9 }, (_, n) => ({ messageId: String(n), sourceInspected: n === 8, imageUrl: null }));
  source.enqueue('a', records);
  source.enqueue('a', records);
  assert.equal(gates.length, 4, 'At most four source requests; repeated page polls share them');
  gates.forEach(gate => gate.resolve(full()));
  await until(() => gates.length === 8);
  gates.slice(4).forEach(gate => gate.resolve(full()));
  await until(() => saved.length === 16);
  assert.equal(new Set(gates.map(gate => gate.messageId)).size, 8);
  assert.ok(gates.every(gate => gate.userId === 'a'));
  assert.ok(saved.every(save => save.content.bodyText === 'Original sender words.'));
  assert.ok(saved.every(save => save.content.attachments.length === 10), 'Profile inspection does not hide small files or the ninth file');
  assert.ok(saved.filter(save => save.content.imageUrl === '').length === 8, 'Confirmed absence is persisted after source inspection');
  assert.ok(saved.every(save => !Object.hasOwn(save.content, 'quote') && !Object.hasOwn(save.content, 'summary')),
    'Original text never becomes an invented AI quote or summary');
  assert.equal(extractAttachments(full().payload).length, 0, 'Existing default attachment extraction behavior remains unchanged');
});

test('source fetch failures remain retryable and are not retried on every polling request', async () => {
  let clock = 0, calls = 0, saved = 0;
  const source = createProfileSource({ image, now: () => clock, logger: { warn() {} },
    fetchFullMessage: async () => { calls++; if (calls === 1) throw Error('offline'); return full(); },
    saveSource: async () => { saved++; },
  });
  const records = [{ messageId: 'one', sourceInspected: false, imageUrl: null }];
  source.enqueue('a', records);
  await until(() => calls === 1);
  await new Promise(resolve => setImmediate(resolve));
  source.enqueue('a', records);
  assert.equal(calls, 1);
  assert.equal(saved, 0, 'Failure cannot mark empty source inspected');
  clock = 30_001;
  source.enqueue('a', records);
  await until(() => saved === 2);
  assert.equal(calls, 2);
});

test('image-host failure preserves source text but never invents an inspected-empty media verdict', async () => {
  const saved = [];
  const source = createProfileSource({ logger: { warn() {} }, fetchFullMessage: async () => full(),
    saveSource: async (_u, _id, value) => saved.push(value),
    image: { extractHtml: () => 'html', pickCandidates: () => ['https://example.invalid/photo.jpg'],
      resolveBest: async (urls, options) => {
        await options.fetchImpl(urls[0], {}).catch(() => {});
        return null;
      } },
    fetchImpl: async () => { throw Error('image host offline'); },
  });
  source.enqueue('a', [{ messageId: 'one', sourceInspected: false, imageUrl: null }]);
  await until(() => saved.length > 0);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(saved.length, 1);
  assert.equal(saved[0].bodyText, 'Original sender words.');
  assert.equal(saved[0].imageUrl, undefined, 'Unknown image state remains unknown');
});
