const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { EventEmitter } = require('node:events');
const { createAPNsTransport, isAPNsToken } = require('../apns');

const token = 'ab'.repeat(32);
const keys = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const env = {
  APNS_KEY_ID: 'TESTKEY123', APNS_TEAM_ID: 'TESTTEAM12', APNS_TOPIC: 'com.example.test',
  APNS_PRIVATE_KEY: keys.privateKey.export({ type: 'pkcs8', format: 'pem' }),
};

function harness({ status = 200, reason, config = env } = {}) {
  const requests = [];
  const endpoints = [];
  let time = 1800000000000;
  const transport = createAPNsTransport({
    env: config,
    now: () => time,
    connect: endpoint => {
      endpoints.push(endpoint);
      const session = new EventEmitter();
      session.close = () => { session.closed = true; };
      session.request = headers => {
        const request = new EventEmitter();
        request.setEncoding = () => {};
        request.close = () => {};
        request.end = body => {
          requests.push({ headers, body: JSON.parse(body) });
          process.nextTick(() => {
            request.emit('response', { ':status': status });
            if (reason) request.emit('data', JSON.stringify({ reason }));
            request.emit('end');
          });
        };
        return request;
      };
      return session;
    },
  });
  return { transport, requests, endpoints, advance: milliseconds => { time += milliseconds; } };
}

test('native token validation accepts hex bytes and rejects Expo/path input', () => {
  assert.equal(isAPNsToken(token), true);
  assert.equal(isAPNsToken('cd'.repeat(48)), true);
  assert.equal(isAPNsToken('ExponentPushToken[test]'), false);
  assert.equal(isAPNsToken('../device'), false);
  assert.equal(isAPNsToken(null), false);
});

test('TestFlight uses production APNs with an ES256 JWT verifiable by the signing public key', async () => {
  const h = harness();
  await h.transport.send(token, { aps: { alert: { title: 'Sender', body: 'Subject' }, badge: 7 } }, { collapseId: 'arrival-1' });
  const request = h.requests[0];
  assert.equal(h.endpoints[0], 'https://api.push.apple.com');
  assert.equal(request.headers[':path'], `/3/device/${token}`);
  assert.equal(request.headers['apns-topic'], 'com.example.test');
  assert.equal(request.headers['apns-push-type'], 'alert');
  assert.equal(request.headers['apns-collapse-id'], 'arrival-1');
  const jwt = request.headers.authorization.slice('bearer '.length);
  const [header, claims, signature] = jwt.split('.');
  assert.equal(JSON.parse(Buffer.from(header, 'base64url')).alg, 'ES256');
  assert.equal(JSON.parse(Buffer.from(claims, 'base64url')).iss, 'TESTTEAM12');
  assert.equal(crypto.verify('sha256', Buffer.from(`${header}.${claims}`), {
    key: keys.publicKey, dsaEncoding: 'ieee-p1363',
  }, Buffer.from(signature, 'base64url')), true);
  h.transport.close();
});

test('badge-only zero uses alert push type without a banner or sound', async () => {
  const h = harness();
  await h.transport.send(token, { aps: { badge: 0, 'content-available': 1 } });
  assert.equal(h.requests[0].headers['apns-push-type'], 'alert');
  assert.equal(h.requests[0].body.aps.badge, 0);
  assert.equal(h.requests[0].body.aps.alert, undefined);
  assert.equal(h.requests[0].body.aps.sound, undefined);
  h.transport.close();
});

test('sandbox is explicit and pure background pushes use priority 5', async () => {
  const h = harness({ config: { ...env, APNS_ENVIRONMENT: 'sandbox' } });
  await h.transport.send(token, { aps: { 'content-available': 1 } });
  assert.equal(h.endpoints[0], 'https://api.sandbox.push.apple.com');
  assert.equal(h.requests[0].headers['apns-push-type'], 'background');
  assert.equal(h.requests[0].headers['apns-priority'], '5');
  h.transport.close();
});

test('provider tokens and HTTP/2 connection are reused, then JWT rotates before one hour', async () => {
  const h = harness();
  await h.transport.send(token, { aps: { badge: 1 } });
  h.advance(49 * 60000);
  await h.transport.send(token, { aps: { badge: 2 } });
  h.advance(2 * 60000);
  await h.transport.send(token, { aps: { badge: 3 } });
  assert.equal(h.requests[0].headers.authorization, h.requests[1].headers.authorization);
  assert.notEqual(h.requests[1].headers.authorization, h.requests[2].headers.authorization);
  assert.equal(h.endpoints.length, 1);
  h.transport.close();
});

test('missing credentials fail explicitly without attempting network or consuming a claim', async () => {
  const h = harness({ config: {} });
  assert.equal(h.transport.isConfigured(), false);
  await assert.rejects(h.transport.send(token, { aps: { badge: 0 } }), error => error.code === 'APNS_NOT_CONFIGURED');
  assert.equal(h.requests.length, 0);
});

test('APNs rejection exposes a safe reason for invalid-token cleanup', async () => {
  const h = harness({ status: 410, reason: 'Unregistered' });
  await assert.rejects(h.transport.send(token, { aps: { badge: 0 } }), error => error.code === 'Unregistered' && error.statusCode === 410);
  h.transport.close();
});
