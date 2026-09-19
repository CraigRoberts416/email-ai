const test = require('node:test');
const assert = require('node:assert/strict');
const { createUnreadBacklog } = require('../unreadBacklog');

function fixture({ failPage = false, failFolder = false, repeatedToken = false } = {}) {
  const events = [];
  let state = 'pending';
  let time = new Date('2026-09-19T12:00:00Z');
  const service = createUnreadBacklog({
    now: () => time,
    userStore: {
      getUser: async () => ({ unread_sync_state: state }),
      setUnreadSyncState: async (_id, value) => { state = value; events.push(['state', value]); },
    },
    messageStore: {
      unreadMetadataNeeded: async (_id, ids) => ids.filter(id => id !== 'existing'),
      upsertMessages: async (_id, messages) => events.push(['upsert', messages]),
      reconcileUnreadLabels: async (_id, ids, started, excluded) => events.push(['reconcile', ids, started, excluded]),
    },
    listPage: async (_id, token, folder) => {
      events.push(['list', token, folder]);
      if (folder) {
        if (failFolder) throw new Error('folder unavailable');
        return { messageIds: folder === 'SPAM' ? ['spam'] : [], nextPageToken: null };
      }
      if (token && failPage) throw new Error('page unavailable');
      return token
        ? { messageIds: ['old', 'spam'], nextPageToken: repeatedToken ? 'page2' : null }
        : { messageIds: ['existing', 'new'], nextPageToken: 'page2' };
    },
    metadata: async (_id, ids) => ids.map(id => ({ id })),
    toRecord: (message, postCutoff) => ({ messageId: message.id, postCutoff }),
  });
  return { service, events, state: () => state, advance: () => { time = new Date(+time + 60001); } };
}

test('all unread pages and excluded folders reconcile before completeness, without historical alert eligibility', async () => {
  const h = fixture();
  await h.service.ensure('a');
  assert.equal(h.state(), 'complete');
  const reconciliation = h.events.find(event => event[0] === 'reconcile');
  assert.deepEqual(reconciliation[1], ['existing', 'new', 'old', 'spam']);
  assert.deepEqual(reconciliation[3], { SPAM: ['spam'], TRASH: [] });
  assert.ok(h.events.filter(event => event[0] === 'upsert').flatMap(event => event[1])
    .every(record => record.postCutoff === false && record.messageId !== 'existing'));
  assert.deepEqual(h.events.at(-1), ['state', 'complete']);
});

test('a failed later page preserves local read state and never claims completion', async () => {
  const h = fixture({ failPage: true });
  await assert.rejects(h.service.ensure('a'), /page unavailable/);
  assert.equal(h.state(), 'error');
  assert.ok(!h.events.some(event => event[0] === 'reconcile'));
  assert.ok(!h.events.some(event => event[0] === 'state' && event[1] === 'complete'));
});

test('folder reconciliation failures also block completeness and pruning', async () => {
  const h = fixture({ failFolder: true });
  await assert.rejects(h.service.ensure('a'), /folder unavailable/);
  assert.equal(h.state(), 'error');
  assert.ok(!h.events.some(event => event[0] === 'reconcile'));
});

test('concurrent requests share one reconciliation; completed state skips unnecessary reimports', async () => {
  const h = fixture();
  await Promise.all([h.service.ensure('a'), h.service.ensure('a'), h.service.ensure('a')]);
  assert.equal(h.events.filter(event => event[0] === 'reconcile').length, 1);
  h.advance();
  await h.service.ensure('a');
  assert.equal(h.events.filter(event => event[0] === 'reconcile').length, 1);
  await h.service.ensure('a', { force: true });
  assert.equal(h.events.filter(event => event[0] === 'reconcile').length, 2);
});

test('repeated provider page tokens fail visibly instead of looping or declaring completion', async () => {
  const h = fixture({ repeatedToken: true });
  await assert.rejects(h.service.ensure('a'), /repeated/);
  assert.equal(h.state(), 'error');
  assert.ok(!h.events.some(event => event[0] === 'reconcile'));
});
