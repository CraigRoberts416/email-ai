const { newText } = require('./replyText');
const { extractAttachments } = require('./emailAttachments');

// Source inspection is independent of interpretation. It runs only for a
// requested profile page and never waits on an AI model or downloads files.
function createProfileSource({ fetchFullMessage, saveSource, image, fetchImpl = fetch,
  concurrency = 4, now = () => Date.now(), logger = console }) {
  const jobs = new Map();
  let running = 0;

  async function inspect(job) {
    const full = await fetchFullMessage(job.userId, job.record.messageId);
    const bodyText = newText(full.payload);
    const attachments = extractAttachments(full.payload, { limit: Infinity, minimumBytes: 0, allowGIF: true, includeInlineImages: true });
    // Preserve original text/files even when an image host is temporarily
    // unavailable. A missing image verdict stays unknown and retryable.
    await saveSource(job.userId, job.record.messageId, { bodyText, attachments });
    if (job.record.imageUrl !== null && job.record.imageUrl !== undefined) return;
    const candidates = image.pickCandidates(image.extractHtml(full.payload)) ?? [];
    let unavailable = false;
    const picture = candidates.length ? await image.resolveBest(candidates, {
      fetchImpl: async (url, options) => {
        try {
          const response = await fetchImpl(url, { ...options,
            signal: AbortSignal.any([options.signal, AbortSignal.timeout(2000)].filter(Boolean)) });
          if (!response.ok) unavailable = true;
          return response;
        } catch (error) { unavailable = true; throw error; }
      },
    }) : null;
    if (!picture && unavailable) throw Error('source image host unavailable');
    await saveSource(job.userId, job.record.messageId, { bodyText, attachments, imageUrl: picture ?? '' });
  }

  function pump() {
    while (running < concurrency) {
      const job = [...jobs.values()].find(value => value.state === 'queued');
      if (!job) return;
      job.state = 'running'; running++;
      inspect(job).then(() => { jobs.delete(job.key); }).catch(error => {
        job.state = 'failed'; job.retryAt = now() + 30_000;
        logger.warn('[profile-source] inspection failed:', error.message);
      }).finally(() => { running--; pump(); });
    }
  }

  function enqueue(userId, records) {
    for (const record of records) {
      if (record.sourceInspected) continue;
      const key = JSON.stringify([userId, record.messageId]);
      const existing = jobs.get(key);
      if (existing && (existing.state !== 'failed' || now() < existing.retryAt)) continue;
      jobs.set(key, { key, userId, record, state: 'queued' });
    }
    // Expired failures must not accumulate after the reader leaves a profile.
    for (const [key, job] of jobs) if (job.state === 'failed' && now() - job.retryAt > 15 * 60_000) jobs.delete(key);
    pump();
  }

  return { enqueue };
}

module.exports = { createProfileSource };
