const { test } = require('node:test');
const assert = require('node:assert/strict');

test('Gmail history searches all dates/read states, excludes Spam/Trash, pages500 and returns metadata without estimates', async () => {
  const paths = ['../userStore', '../messageStore'].map(require.resolve);
  const previous = paths.map(path => require.cache[path]);
  paths.forEach(path => { require.cache[path] = { id: path, filename: path, loaded: true, exports: {} }; });
  require.cache[paths[0]].exports.getValidAccessToken = async () => 'fixture-token';
  const originalFetch = global.fetch;
  const requests = [];
  global.fetch = async (url, options) => {
    requests.push({ url: new URL(url), options });
    return { ok: true, json: async () => new URL(url).pathname.endsWith('/messages')
      ? { messages: [{ id: 'fixture-message' }], nextPageToken: 'next', resultSizeEstimate: 999 }
      : { id: 'fixture-message', labelIds: [], internalDate: '1262304000000', payload: { headers: [
        { name: 'From', value: 'Sender <old@amazon.com>' }, { name: 'Subject', value: 'Original subject' },
      ] } } };
  };
  const syncPath = require.resolve('../gmailSync');
  const priorSync = require.cache[syncPath];
  delete require.cache[syncPath];
  try {
    const sync = require('../gmailSync');
    const listed = await sync.listSenderMessagesPage('fixture', { q: 'from:amazon.com -in:spam -in:trash', pageToken: 'previous' });
    assert.deepEqual(listed, { messageIds: ['fixture-message'], nextPageToken: 'next' });
    const query = requests[0].url.searchParams;
    assert.equal(query.get('maxResults'), '500');
    assert.equal(query.get('includeSpamTrash'), 'false');
    assert.equal(query.get('pageToken'), 'previous');
    assert.equal(query.get('labelIds'), null);
    assert.equal(query.get('q'), 'from:amazon.com -in:spam -in:trash');
    const metadata = await sync.fetchSenderRecords('fixture', listed.messageIds);
    assert.equal(requests[1].url.searchParams.get('format'), 'metadata');
    assert.equal(metadata[0].fromEmail, 'old@amazon.com');
    assert.equal(metadata[0].postCutoff, false);
    assert.deepEqual(metadata[0].labelIds, []);
    assert.equal(metadata[0].internalDate, 1262304000000);
  } finally {
    global.fetch = originalFetch;
    paths.forEach((path, i) => { if (previous[i]) require.cache[path] = previous[i]; else delete require.cache[path]; });
    if (priorSync) require.cache[syncPath] = priorSync; else delete require.cache[syncPath];
  }
});
