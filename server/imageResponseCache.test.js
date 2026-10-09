const test = require('node:test');
const assert = require('node:assert/strict');
const { createImageResponseCache, readBoundedImage } = require('./imageResponseCache');
const image = value => ({ bytes: Buffer.from(value), mime: 'image/png' });

test('concurrent image consumers share one upstream request and reuse its result', async () => {
  const cache = createImageResponseCache();
  let calls = 0;
  const load = async () => { calls++; await new Promise(resolve => setImmediate(resolve)); return image('one'); };
  const [a, b] = await Promise.all([cache.get('a', load), cache.get('a', load)]);
  assert.equal(a, b);
  assert.equal(await cache.get('a', load), a);
  assert.equal(calls, 1);
});

test('bounded cache evicts least-recently used images and does not retain oversized responses', async () => {
  const cache = createImageResponseCache({ maxBytes: 6, maxEntries: 2 });
  const a = await cache.get('a', () => image('aaa'));
  await cache.get('b', () => image('bbb'));
  await cache.get('a', () => { throw Error('cache miss'); });
  await cache.get('c', () => image('ccc'));
  assert.equal(await cache.get('a', () => { throw Error('cache miss'); }), a);
  let calls = 0;
  await cache.get('b', () => { calls++; return image('bbb'); });
  assert.equal(calls, 1);
  for (let i = 0; i < 2; i++) await cache.get('large', () => { calls++; return image('toolarge'); });
  assert.equal(calls, 3);
});

test('failed downloads can retry; streamed size limit stops oversized responses', async () => {
  const cache = createImageResponseCache();
  await assert.rejects(cache.get('a', () => { throw Error('offline'); }), /offline/);
  assert.equal((await cache.get('a', () => image('ok'))).bytes.toString(), 'ok');
  await assert.rejects(readBoundedImage(new Response('oversize'), 2), { status: 413 });
  await assert.rejects(readBoundedImage(new Response('ok', { headers: { 'content-length': '100' } }), 2), { status: 413 });
  assert.equal((await readBoundedImage(new Response('ok'), 2)).toString(), 'ok');
});
