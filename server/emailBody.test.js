const test = require('node:test');
const assert = require('node:assert/strict');
const { prepareEmailBody } = require('./emailBody');
const textPart = (mimeType, text) => ({ mimeType, body: { data: Buffer.from(text).toString('base64url') } });

test('nested Gmail body resolves embedded data and attachment images, preserving remote URLs', () => {
  const payload = { parts: [{ parts: [
    textPart('text/plain', 'Hello'),
    textPart('text/html', '<img src="cid:logo%40mail"><img src="CID:photo"><img src="https://sender.test/picture"><style>p{background:url(cid:photo)}</style>'),
  ] }, { mimeType: 'image/png', headers: [{ name: 'Content-ID', value: '<logo@mail>' }], body: { data: 'YWJj' } },
  { mimeType: 'image/jpeg', headers: [{ name: 'content-id', value: '<photo>' }], body: { attachmentId: 'attachment-1' } }] };
  const calls = [];
  const body = prepareEmailBody(payload, (id, mime) => { calls.push([id, mime]); return 'https://mail.test/file?imageType=image%2Fjpeg&t=signed'; });
  assert.equal(body.plainText, 'Hello');
  assert.match(body.htmlRaw, /src="data:image\/png;base64,YWJj"/);
  assert.match(body.htmlRaw, /src="https:\/\/mail.test\/file\?imageType=image%2Fjpeg&t=signed"/);
  assert.match(body.htmlRaw, /background:url\(https:\/\/mail.test\/file\?imageType=image%2Fjpeg&t=signed\)/);
  assert.match(body.htmlRaw, /https:\/\/sender.test\/picture/);
  assert.deepEqual(calls, [['attachment-1', 'image/jpeg']]);
});

test('unknown and non-image CIDs never become image capabilities', () => {
  const payload = { parts: [textPart('text/html', '<img src="cid:unknown"><img src="cid:script">'),
    { mimeType: 'text/html', headers: [{ name: 'Content-ID', value: 'script' }], body: { attachmentId: 'bad' } }] };
  assert.equal(prepareEmailBody(payload, () => { throw Error('unexpected'); }).htmlRaw,
    '<img src="cid:unknown"><img src="cid:script">');
  assert.deepEqual(prepareEmailBody(null, () => ''), { plainText: '', htmlRaw: '' });
});
