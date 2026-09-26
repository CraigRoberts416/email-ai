const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const Module = require('node:module');

function fixture(t, { status, body }) {
  const writes = [];
  const filename = require.resolve('../userStore');
  const isolated = new Module(filename, module);
  isolated.require = name => name === './db' ? {
    query: async (sql, values) => {
      if (sql.startsWith('SELECT')) return { rows: [{ access_token: 'expired-access',
        refresh_token: 'synthetic-refresh', token_expiry: new Date(0) }] };
      writes.push(values); return { rows: [] };
    },
  } : require(require.resolve(name, { paths: [require('node:path').dirname(filename)] }));
  isolated._compile(fs.readFileSync(filename, 'utf8'), filename);
  t.mock.method(global, 'fetch', async () => ({ ok: status === 200, status, json: async () => body }));
  return { users: isolated.exports, writes };
}

test('Google invalid_grant is a reconnect failure, without overwriting saved credentials', async t => {
  const h = fixture(t, { status: 400, body: { error: 'invalid_grant', error_description: 'Token has been expired or revoked.' } });
  await assert.rejects(h.users.getValidAccessToken('expired-grant-fixture'), error =>
    error.statusCode === 401 && error.code === 'MAILBOX_RECONNECT_REQUIRED');
  assert.deepEqual(h.writes, []);
});

test('temporary Google failures do not incorrectly sign the user out', async t => {
  const h = fixture(t, { status: 503, body: { error: 'temporarily_unavailable' } });
  await assert.rejects(h.users.getValidAccessToken('temporary-grant-fixture'), error => error.statusCode !== 401);
  assert.deepEqual(h.writes, []);
});

test('successful token renewal persists and returns the new access token', async t => {
  const h = fixture(t, { status: 200, body: { access_token: 'renewed-access', expires_in: 3600 } });
  assert.equal(await h.users.getValidAccessToken('renewed-grant-fixture'), 'renewed-access');
  assert.equal(h.writes.length, 1);
  assert.equal(h.writes[0][1], 'renewed-access');
});
