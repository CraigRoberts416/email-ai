const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const emailImage = require('../emailImage');

test('text-only image backfill records a verified empty result and does not refetch it at next startup', async () => {
  const source = fs.readFileSync(require.resolve('../index'), 'utf8');
  const start = source.indexOf('async function runImageBackfill(userId) {');
  const end = source.indexOf('/// Pulls new mail on a timer', start);
  let stored = null, calls = 0;
  const context = {
    module: { exports: {} }, console: { log() {}, error() {} }, emailImage,
    messageStore: {
      getMessageIdsNeedingImageBackfill: async () => stored === null ? ['text-only'] : [],
      setImageUrl: async (_user, _message, image) => { stored = image; },
    },
    gmailSync: { fetchFullMessage: async (_user, _id, options) => {
      assert.equal(options.priority, 0, 'Startup work uses the background read budget'); calls++;
      return { payload: { mimeType: 'text/plain', body: { data: Buffer.from('Original plain text').toString('base64url') } } };
    } },
  };
  vm.runInNewContext(source.slice(start, end) + '\nmodule.exports = runImageBackfill;', context);
  await context.module.exports('fixture-account');
  assert.equal(stored, '', 'No image is a persisted result rather than an exception');
  await context.module.exports('fixture-account');
  assert.equal(calls, 1, 'A later server start does not spend another Gmail read on the same text-only message');
});
