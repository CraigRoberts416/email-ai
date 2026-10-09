'use strict';

// Share concurrent fetch/resize work and retain a bounded set of hot images.
// Rejections aren't cached: an unavailable sender image can be retried later.
function createImageResponseCache({ maxBytes = 32 * 1024 * 1024, maxEntries = 128 } = {}) {
  const entries = new Map();
  const pending = new Map();
  let bytes = 0;
  return {
    async get(key, load) {
      if (entries.has(key)) {
        const value = entries.get(key);
        entries.delete(key); entries.set(key, value);
        return value;
      }
      if (pending.has(key)) return pending.get(key);
      const work = Promise.resolve().then(load).then(value => {
        if (value && value.bytes.length <= maxBytes) {
          while (entries.size && (bytes + value.bytes.length > maxBytes || entries.size >= maxEntries)) {
            const oldest = entries.keys().next().value;
            bytes -= entries.get(oldest).bytes.length;
            entries.delete(oldest);
          }
          entries.set(key, value); bytes += value.bytes.length;
        }
        return value;
      }).finally(() => pending.delete(key));
      pending.set(key, work);
      return work;
    },
  };
}

async function readBoundedImage(response, limit) {
  if (Number(response.headers.get('content-length')) > limit) {
    await response.body?.cancel();
    throw Object.assign(new Error('image too large'), { status: 413 });
  }
  const chunks = [];
  let bytes = 0;
  for await (const chunk of response.body) {
    bytes += chunk.length;
    if (bytes > limit) throw Object.assign(new Error('image too large'), { status: 413 });
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

module.exports = { createImageResponseCache, readBoundedImage };
