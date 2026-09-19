const test = require('node:test');
const assert = require('node:assert/strict');
const { canonicalDomain, avatarURL, registerSenderIdentityRoute } = require('./senderIdentity');

test('logos preserve registrable multi-label domains and reject unsafe hosts', () => {
  assert.equal(canonicalDomain('ship.amazon.co.uk'), 'amazon.co.uk');
  assert.equal(canonicalDomain('MAIL.AMAZON.COM'), 'amazon.com');
  assert.equal(canonicalDomain('a.example.com.au'), 'example.com.au');
  assert.equal(canonicalDomain('project.github.io'), 'project.github.io');
  for (const input of ['', 'co.uk', '127.0.0.1', 'localhost', 'a@amazon.com', 'amazon.com/path', 'amazon.com?x', 'a b.com']) {
    assert.equal(canonicalDomain(input), '', input);
  }
  assert.equal(avatarURL('ship.amazon.co.uk', 'public-token'), 'https://img.logo.dev/amazon.co.uk?token=public-token');
  assert.equal(avatarURL('mail.gmail.com', 'public-token'), null);
  assert.equal(avatarURL('proton.me', 'public-token'), null);
});

function setup({ authenticated = true, asset = { bgColor: '#123456', description: 'Known sender' } } = {}) {
  let handler;
  const lookups = [];
  registerSenderIdentityRoute({ get: (path, callback) => { assert.equal(path, '/sender-identity'); handler = callback; } }, {
    resolveUserId: async () => authenticated ? 'user' : null,
    logoToken: 'token',
    heroImage: {
      getCachedAsset: async domain => { lookups.push(domain); return asset; },
      buildHeroImageUrl: (_, domain) => `https://server/hero-image/${domain}`,
    },
  });
  const res = { statusCode: 200, headers: {}, setHeader(k, v) { this.headers[k] = v; },
    status(code) { this.statusCode = code; return this; }, json(body) { this.body = body; return this; } };
  return { handler, res, lookups };
}

test('profile lookup keeps assets available independently of message membership', async () => {
  const { handler, res, lookups } = setup();
  await handler({ query: { address: 'shipping@Ship.Amazon.co.uk' } }, res);
  assert.equal(res.statusCode, 200);
  assert.deepEqual(lookups, ['amazon.co.uk']);
  assert.equal(res.body.heroImageUrl, 'https://server/hero-image/amazon.co.uk');
  assert.equal(res.body.address, 'shipping@ship.amazon.co.uk');
  assert.equal(res.body.senderDescription, 'Known sender');
});

test('profile lookup requires auth and does not invent art for missing assets or people', async () => {
  const denied = setup({ authenticated: false });
  await denied.handler({ query: { address: 'someone@gmail.com' } }, denied.res);
  assert.equal(denied.res.statusCode, 401);
  assert.deepEqual(denied.lookups, []);
  const person = setup();
  await person.handler({ query: { address: 'someone@gmail.com' } }, person.res);
  assert.equal(person.res.body.avatarUri, null);
  assert.equal(person.res.body.heroImageUrl, null);
  assert.deepEqual(person.lookups, []);
  const missing = setup({ asset: null });
  await missing.handler({ query: { address: 'someone@amazon.com' } }, missing.res);
  assert.equal(missing.res.body.heroImageUrl, null);
  const invalid = setup();
  await invalid.handler({ query: { address: 'someone@co.uk' } }, invalid.res);
  assert.equal(invalid.res.statusCode, 400);
});
