// Mail from people, grouped the way a chat app groups it.
//
// The unit here is the PARTICIPANT SET, not the Gmail thread. Two threads with
// the same people in them are one conversation; the same subject line with a
// new person on it is a different one. That is not a reinterpretation of email
// — it is what email already does when you reply-all to a new address, and
// mail clients simply hide the fork behind a shared subject.
//
// People only. A no-reply address is not a participant: a conversation implies
// a reply is possible and someone is on the other end, and presenting a
// machine configured not to listen as a chat would be a lie about what happens
// when you write back.

const { query } = require('./db');
const gmailSync = require('./gmailSync');
const messageStore = require('./messageStore');
const { newText, unwrap } = require('./replyText');
const { extractAttachments } = require('./emailAttachments');

const FREE_MAIL = new Set([
  'gmail.com', 'yahoo.com', 'outlook.com', 'hotmail.com', 'icloud.com',
  'live.com', 'msn.com', 'ymail.com', 'aol.com', 'protonmail.com', 'proton.me',
]);

/// Mailboxes nobody reads. The strongest signal available, and it lives in the
/// address rather than the display name, which senders style however they like.
const AUTOMATED = [
  'noreply', 'no-reply', 'donotreply', 'do-not-reply', 'notification',
  'notifications', 'mailer', 'mail', 'support', 'help', 'info', 'hello',
  'team', 'news', 'newsletter', 'updates', 'update', 'receipts', 'receipt',
  'billing', 'invoice', 'account', 'accounts', 'alerts', 'alert', 'service',
  'contact', 'admin', 'automated', 'bounce', 'postmaster', 'via',
];

const CORPORATE = [
  ' inc', ' inc.', ' llc', ' ltd', ' ltd.', ' corp', ' corp.', ' pbc',
  ' co.', ' gmbh', ' plc', ' s.a.', ' b.v.',
];

/// Words that appear in a company's name and effectively never in a person's.
///
/// Gmail files plenty of commercial mail in Primary — a bank alert and a card
/// statement are correspondence by its reckoning — so Primary alone let "Ally
/// Bank" and "American Express" through as people. Two words each, no legal
/// suffix, no automated local part: nothing else available catches them.
const TRADE_WORDS = new Set([
  'bank', 'express', 'insurance', 'assurance', 'airlines', 'airways', 'air',
  'health', 'healthcare', 'medical', 'dental', 'energy', 'electric', 'gas',
  'capital', 'financial', 'finance', 'credit', 'card', 'rewards', 'loyalty',
  'store', 'shop', 'market', 'markets', 'media', 'news', 'group', 'holdings',
  'partners', 'ventures', 'labs', 'studio', 'studios', 'agency', 'services',
  'solutions', 'systems', 'technologies', 'tech', 'digital', 'global',
  'international', 'university', 'college', 'school', 'hospital', 'clinic',
  'motors', 'auto', 'realty', 'properties', 'hotel', 'hotels', 'resorts',
  'airline', 'railway', 'transit', 'telecom', 'wireless', 'mobile', 'cable',
  'delivery', 'logistics', 'shipping', 'post', 'mail', 'support', 'team',
  'club', 'society', 'association', 'foundation', 'institute', 'council',
  // Things a report is, which no parent names a child. "Mailsuite Daily
  // Report" is three plausible words and an address whose local part is
  // `daily-report` — it reached the People list as a person.
  'report', 'reports', 'daily', 'weekly', 'monthly', 'digest', 'bulletin',
  'summary', 'roundup', 'recap', 'alerts', 'notification', 'notifications',
  'reminder', 'reminders', 'invoice', 'receipt', 'statement', 'newsletter',
]);

/// A draft is not a message. Gmail keeps it in the thread next to the message
/// it eventually became, so without this a reply appears twice — once as the
/// thing you typed and once as the thing you sent.
function isDraft(labelIds) {
  return (labelIds ?? []).includes('DRAFT');
}

/// Primary is the absence of a category label. Gmail applies exactly one of
/// these to everything it sorts, so no label means it decided this was
/// correspondence.
function isPrimary(labelIds) {
  const labels = labelIds ?? [];
  return !labels.some(l => typeof l === 'string' && l.startsWith('CATEGORY_')
    && l !== 'CATEGORY_PERSONAL');
}

function isPerson({ name, email, hasUnsubscribe }) {
  if (!email) return false;
  if (hasUnsubscribe) return false;

  // Matched against the address's own tokens, not just its prefix.
  // `calendar-notification@google.com` is plainly a machine and was being
  // read as a person because "notification" was not at the start.
  const local = email.split('@')[0]?.toLowerCase() ?? '';
  const tokens = local.split(/[-._+]/).filter(Boolean);
  if (tokens.some(t => AUTOMATED.includes(t))) return false;

  const display = (name ?? '').trim();
  const lowered = display.toLowerCase();
  if (CORPORATE.some(sfx => lowered.endsWith(sfx) || lowered.includes(sfx + ','))) return false;

  // Any trade word anywhere in the name. "Ally Bank" is not somebody called
  // Bank.
  const nameTokens = lowered.split(/[\s,]+/).map(w => w.replace(/[.]/g, '')).filter(Boolean);
  if (nameTokens.some(w => TRADE_WORDS.has(w))) return false;

  // A person's display name is a given name and a family name. One word is a
  // company; many words is a company or a mailing list.
  //
  // Particles do not count against the total, which is the whole reason this
  // is not a plain word count: "Maria van der Berg" is four words and a
  // person, and a rule that cannot hold that is a rule that quietly files
  // some people as companies.
  const PARTICLES = new Set([
    'van', 'von', 'der', 'den', 'de', 'del', 'della', 'di', 'da', 'dos',
    'la', 'le', 'du', 'bin', 'ibn', 'al', 'st', 'st.', 'mc', 'mac',
  ]);
  const words = display.split(/\s+/).filter(Boolean);
  if (!words.length) return FREE_MAIL.has(email.split('@')[1] ?? '');
  const significant = words.filter(w => !PARTICLES.has(w.toLowerCase().replace(/[.,]/g, '')));
  return significant.length >= 2 && significant.length <= 3;
}

/// The set, as a stable id. Sorted and lowercased so the same people always
/// produce the same conversation however the addresses were ordered on any
/// individual message.
function setKey(addresses) {
  return Array.from(new Set(addresses.map(a => a.toLowerCase()))).sort().join('|');
}

/// A body collapsed to one line, for a list row that shows one line.
///
/// Leading URLs are skipped. A retailer's mail often opens with a tracking
/// link before any words, and a row reading
/// `https://click.sfemail.signetjewelers.com/…` tells the reader nothing about
/// who wrote or what they said. The first line that is actually language wins;
/// if there is none, the URL is better than a blank.
function firstLine(body) {
  if (!body) return '';
  const lines = body.split('\n').map(l => l.trim()).filter(Boolean);
  // Every line that is language, run together — not the first one. A body
  // opens with "Hi Craig," far more often than it opens with the point, and a
  // row reading only the greeting says nothing at all.
  const words = lines.filter(l => !/^(https?:\/\/|www\.)\S*$/i.test(l));
  return (words.length ? words : lines).join(' ').replace(/\s+/g, ' ').trim();
}

/**
 * Every conversation this user has with people, newest first.
 *
 * `me` is excluded from the participant set so a thread with one other person
 * is keyed on them alone — otherwise every conversation would carry the
 * account's own address and two-person chats would look like groups.
 */
/// Their organisation's mark, standing in for a photograph.
///
/// There is no photo of a person available here: Gmail does not hand one over
/// without a contacts scope, and a Gravatar lookup would send a hash of every
/// address in someone's mailbox to a third party in exchange for a picture
/// most of them do not have. The company mark is recognisable, costs nothing,
/// and is already what the feed shows for the same sender — the alternative
/// was a grid of identical grey monograms.
///
/// Free mail gets none. A gmail.com address would otherwise wear Google's
/// logo, which says nothing about who wrote to you.
function avatarFor(email, resolve) {
  const domain = (email ?? '').split('@')[1]?.toLowerCase();
  if (!domain) return null;
  return resolve({ sender: { domain } });
}

// Metadata is walked in bounded keyset pages; the end of a query page is never
// mistaken for the end of someone's correspondence. Bodies are read separately.
async function* metadataPages(userId, ownEmail, readQuery, { predicate = 'TRUE', values = [], batchSize = 2000, includePreview = false } = {}) {
  let before = null;
  do {
    const args = [userId, ownEmail, ...values];
    let boundary = '';
    if (before) {
      args.push(before[0], before[1]);
      boundary = `AND (internal_date, message_id COLLATE "C") < ($${args.length - 1}::bigint, $${args.length}::text COLLATE "C")`;
    }
    args.push(batchSize);
    const { rows } = await readQuery(`
      SELECT message_id, thread_id, subject, from_name, from_email,
             internal_date, participants, unsubscribe_url, label_ids
             ${includePreview ? ', LEFT(snippet, 512) AS preview_text' : ''}
      FROM messages WHERE user_id = $1
        AND NOT (COALESCE(label_ids, '{}') && ARRAY['DRAFT', 'SPAM', 'TRASH']::text[])
        AND (lower(from_email) = $2 OR NOT EXISTS (
          SELECT 1 FROM unnest(label_ids) l WHERE l LIKE 'CATEGORY_%' AND l <> 'CATEGORY_PERSONAL'))
        AND (${predicate}) ${boundary}
      ORDER BY internal_date DESC, message_id COLLATE "C" DESC
      LIMIT $${args.length}
    `, args);
    yield rows;
    if (rows.length < batchSize) break;
    const last = rows.at(-1);
    before = [Number(last.internal_date) || 0, last.message_id];
  } while (true);
}

function othersIn(row, me) {
  const others = new Map();
  const from = (row.from_email ?? '').toLowerCase();
  if (from && from !== me) others.set(from, { name: row.from_name, email: from });
  for (const p of Array.isArray(row.participants) ? row.participants : []) {
    const email = p?.email?.toLowerCase();
    if (email && email !== me && !others.has(email)) others.set(email, { ...p, email });
  }
  return [...others.values()];
}

function compareNewest(a, b) {
  return b.lastAt - a.lastAt || (a.id < b.id ? 1 : a.id > b.id ? -1 : 0);
}
function pageLimit(value) { return Math.min(200, Math.max(1, Number.parseInt(value, 10) || 50)); }
function encodeCursor(userId, scope, entry) {
  return Buffer.from(JSON.stringify({ v: 1, user: userId, scope, at: entry.lastAt, id: entry.id })).toString('base64url');
}
function decodeCursor(value, userId, scope) {
  if (!value) return null;
  try {
    if (typeof value !== 'string' || value.length > 8192) throw Error();
    const c = JSON.parse(Buffer.from(value, 'base64url').toString());
    if (c.v !== 1 || c.user !== userId || c.scope !== scope || !Number.isSafeInteger(c.at) || typeof c.id !== 'string') throw Error();
    return { lastAt: c.at, id: c.id };
  } catch { const error = new Error('Invalid conversation cursor'); error.status = 400; throw error; }
}
function selectPage(items, userId, scope, { cursor, limit } = {}) {
  const before = decodeCursor(cursor, userId, scope);
  const available = before ? items.filter(item => compareNewest(item, before) > 0) : items;
  const selected = available.slice(0, pageLimit(limit));
  return { selected, nextCursor: available.length > selected.length
    ? encodeCursor(userId, scope, selected.at(-1)) : null };
}

async function aggregateConversations(userId, ownEmail, { resolveAvatar, query: readQuery = query,
  batchSize = 2000, includePreview = false, onBatch = () => {} } = {}) {
  const me = (ownEmail ?? '').toLowerCase();
  const conversations = new Map();
  const threadKeys = new Map();
  const orphanSent = [];
  function add(row, key, others) {
    const mine = (row.from_email ?? '').toLowerCase() === me;
    let c = conversations.get(key);
    if (!c) {
      c = { id: key, participants: others.map(p => ({ ...p, name: p.name || p.email.split('@')[0],
        avatarUri: resolveAvatar ? avatarFor(p.email, resolveAvatar) : null })),
      lastMessageId: row.message_id, threadId: row.thread_id, subject: row.subject,
      preview: firstLine(row.preview_text), lastAt: Number(row.internal_date) || 0, lastFromMe: mine,
      unread: false, messageCount: 0 };
      conversations.set(key, c);
    }
    c.messageCount++;
    if ((row.label_ids ?? []).includes('UNREAD') && !mine) c.unread = true;
    const date = Number(row.internal_date) || 0;
    if (date > c.lastAt || (date === c.lastAt && row.message_id > c.lastMessageId)) {
      Object.assign(c, { lastAt: date, lastMessageId: row.message_id,
        threadId: row.thread_id, subject: row.subject, lastFromMe: mine, preview: firstLine(row.preview_text) });
    }
  }
  for await (const rows of metadataPages(userId, me, readQuery, { batchSize, includePreview })) {
    for (const row of rows) {
      const mine = (row.from_email ?? '').toLowerCase() === me;
      const others = othersIn(row, me);
      if (!others.length) { if (mine && row.thread_id) orphanSent.push(row); continue; }
      if (!others.every(p => isPerson({ ...p, hasUnsubscribe: !!row.unsubscribe_url && !mine }))) continue;
      const key = setKey(others.map(p => p.email));
      add(row, key, others);
      if (row.thread_id) {
        if (!threadKeys.has(row.thread_id)) threadKeys.set(row.thread_id, new Set());
        threadKeys.get(row.thread_id).add(key);
      }
    }
    // Publish copies; later batches must never mutate a page already served.
    onBatch([...conversations.values()].map(c => ({ ...c })).sort(compareNewest));
  }
  // Older imports lacked recipients on sent mail. A thread can supply the
  // participant set only when that thread has one unambiguous set.
  for (const row of orphanSent) {
    const keys = threadKeys.get(row.thread_id);
    if (keys?.size === 1) { const key = [...keys][0]; add(row, key, conversations.get(key).participants); }
  }
  return [...conversations.values()].sort(compareNewest);
}

async function listConversationsPage(userId, ownEmail, { limit = 50, cursor, resolveAvatar,
  query: readQuery = query, batchSize = 2000 } = {}) {
  decodeCursor(cursor, userId, 'people');
  const all = await aggregateConversations(userId, ownEmail, { resolveAvatar, query: readQuery, batchSize });
  const { selected, nextCursor } = selectPage(all, userId, 'people', { cursor, limit });
  if (selected.length) {
    const { rows } = await readQuery(`SELECT message_id, LEFT(body_text, 4096) AS body_text,
      LEFT(quote, 4096) AS quote, LEFT(snippet, 4096) AS snippet FROM messages
      WHERE user_id = $1 AND message_id = ANY($2::text[])`, [userId, selected.map(c => c.lastMessageId)]);
    const previews = new Map(rows.map(r => [r.message_id, r]));
    for (const c of selected) {
      const row = previews.get(c.lastMessageId);
      c.preview = Array.from(row ? firstLine(row.body_text) || row.quote || row.snippet || '' : '').slice(0, 512).join('');
    }
  }
  return { conversations: selected, nextCursor, totalConversations: all.length,
    unreadConversations: all.filter(c => c.unread).length };
}

/**
 * A shared directory fills independently of HTTP. Requests only slice an
 * immutable snapshot, so a large archive or a busy database cannot keep a
 * phone waiting for the full scan. Bodies never enter this directory.
 */
function createConversationDirectory({ query: readQuery = query, now = () => Date.now(),
  batchSize = 500, ttlMs = 30_000, retentionMs = 15 * 60_000, concurrency = 2,
  aggregate = aggregateConversations, logger = console } = {}) {
  const accounts = new Map();
  const queued = [];
  let running = 0;
  let sequence = 0;

  function pump() {
    while (running < concurrency && queued.length) {
      const job = queued.shift();
      running++;
      job.status = 'indexing';
      job.work = Promise.resolve().then(async () => {
        job.items = await aggregate(job.userId, job.ownEmail, {
          query: readQuery, batchSize, includePreview: true, resolveAvatar: job.resolveAvatar,
          onBatch: items => { job.items = items; },
        });
        job.status = 'complete';
      }).catch(error => {
        job.status = 'failed';
        logger.warn('[conversations] background directory failed:', error.message);
      }).finally(() => {
        job.finishedAt = now();
        running--;
        pump();
      });
    }
  }

  function start(account, userId, ownEmail, sourceVersion, sourceComplete, resolveAvatar) {
    const job = { userId, ownEmail, resolveAvatar, sourceVersion, sourceComplete,
      generation: `${now().toString(36)}-${++sequence}`, items: account.active?.items ?? [], status: 'queued',
      startedAt: now(), finishedAt: null, work: null };
    account.active = job;
    account.snapshots.set(job.generation, job);
    queued.push(job);
    pump();
    return job;
  }

  function page(userId, ownEmail, { cursor, limit = 50, resolveAvatar,
    sourceVersion = '', sourceComplete = false, sourceState = 'pending' } = {}) {
    let boundary = decodeCursor(cursor, userId, 'people');
    let cursorGeneration = null;
    if (cursor) cursorGeneration = JSON.parse(Buffer.from(cursor, 'base64url').toString()).generation ?? null;
    let account = accounts.get(userId);
    if (!account) { account = { active: null, snapshots: new Map(), lastUsed: now() }; accounts.set(userId, account); }
    account.lastUsed = now();
    let active = account.active;
    const inFlight = active && (active.status === 'queued' || active.status === 'indexing');
    const expired = active && active.finishedAt !== null && now() - active.finishedAt >= (active.status === 'failed' ? 5000 : ttlMs);
    if (!active || (!inFlight && (active.sourceVersion !== sourceVersion || (!cursor && expired)))) {
      active = start(account, userId, ownEmail, sourceVersion, sourceComplete, resolveAvatar);
    }
    // A cursor keeps using its completed snapshot while a head refresh builds
    // the next one. After a process restart its date/id boundary still works.
    const job = (cursorGeneration && account.snapshots.get(cursorGeneration)) || active;
    const complete = job.status === 'complete' && job.sourceComplete && sourceComplete
      && job.sourceVersion === sourceVersion;
    const available = boundary ? job.items.filter(item => compareNewest(item, boundary) > 0) : job.items;
    const selected = available.slice(0, pageLimit(limit));
    const waitingForMore = job.status !== 'complete';
    const last = selected.at(-1) ?? boundary;
    const nextCursor = last && (available.length > selected.length || waitingForMore)
      ? Buffer.from(JSON.stringify({ v: 1, user: userId, scope: 'people', at: last.lastAt,
          id: last.id, generation: job.generation })).toString('base64url') : null;
    const state = job.status === 'failed' ? 'failed'
      : job.status !== 'complete' ? 'indexing'
      : complete ? 'complete' : sourceState === 'failed' ? 'failed' : 'syncing';
    // Retain old cursor snapshots briefly, never a second copy forever.
    for (const [id, snapshot] of account.snapshots) {
      if (snapshot !== active && snapshot.finishedAt !== null && now() - snapshot.finishedAt > retentionMs) account.snapshots.delete(id);
    }
    for (const [id, cached] of accounts) {
      if (id !== userId && now() - cached.lastUsed > retentionMs
          && !['queued', 'indexing'].includes(cached.active.status)) accounts.delete(id);
    }
    return { conversations: selected, nextCursor,
      totalConversations: complete ? job.items.length : null,
      unreadConversations: complete ? job.items.filter(c => c.unread).length : null,
      historyComplete: complete, historySyncState: state };
  }
  return { page };
}
const conversationDirectory = createConversationDirectory();

// Legacy array helpers are retained for callers migrating to the page contract.
async function listConversations(userId, ownEmail, options) {
  return (await listConversationsPage(userId, ownEmail, options)).conversations;
}

async function conversationMessagesPage(userId, ownEmail, id, { limit = 50, cursor, resolveAvatar,
  query: readQuery = query, hydrate = hydrateBodies, batchSize = 2000 } = {}) {
  const me = (ownEmail ?? '').toLowerCase();
  const key = setKey(id.split('|').filter(Boolean));
  decodeCursor(cursor, userId, key);
  const addresses = key.split('|');
  const kept = new Map();
  const threads = new Set();
  // Both branches have indexes. Expanding participants with a correlated
  // jsonb_array_elements/EXISTS decoded every message in the account before
  // a small thread could open. Containment narrows candidates first; the
  // exact participant-set check below still keeps reply-all forks separate.
  const participantMatches = addresses.map(email => JSON.stringify([{ email }]));
  const predicate = `lower(from_email) = ANY($3::text[])
    OR lower(participants::text)::jsonb @> ANY($4::jsonb[])`;
  for await (const rows of metadataPages(userId, me, readQuery, {
    predicate, values: [addresses, participantMatches], batchSize,
  })) {
    for (const row of rows) {
      if (setKey(othersIn(row, me).map(p => p.email)) !== key) continue;
      kept.set(row.message_id, row);
      if (row.thread_id) threads.add(row.thread_id);
    }
  }
  if (threads.size) {
    for await (const rows of metadataPages(userId, me, readQuery, {
      predicate: 'lower(from_email) = $2 AND thread_id = ANY($3::text[])', values: [[...threads]], batchSize,
    })) {
      for (const row of rows) {
        // Explicit recipients win over the inherited Gmail thread. A reply-all
        // to another participant set must not leak into this conversation.
        const others = othersIn(row, me);
        if (others.length && setKey(others.map(p => p.email)) !== key) continue;
        kept.set(row.message_id, row);
      }
    }
  }
  const all = [...kept.values()].map(row => ({ id: row.message_id, lastAt: Number(row.internal_date) || 0 })).sort(compareNewest);
  const { selected, nextCursor } = selectPage(all, userId, key, { cursor, limit });
  let messages = [];
  let sourcesPending = false;
  if (selected.length) {
    const { rows } = await readQuery(`SELECT message_id, thread_id, subject, from_name, from_email, snippet,
      internal_date, label_ids, quote, summary, attachments, body_text, source_version FROM messages
      WHERE user_id = $1 AND message_id = ANY($2::text[])`, [userId, selected.map(m => m.id)]);
    rows.sort((a, b) => Number(a.internal_date) - Number(b.internal_date)
      || (a.message_id < b.message_id ? -1 : a.message_id > b.message_id ? 1 : 0));
    sourcesPending = rows.some(needsSourceInspection);
    hydrate(userId, rows).catch(err => console.warn('[conversations] background hydrate:', err.message));
    messages = rows.map(row => {
      const fromEmail = (row.from_email ?? '').toLowerCase();
      return { messageId: row.message_id, threadId: row.thread_id, subject: row.subject,
        fromName: row.from_name, fromEmail, avatarUri: resolveAvatar ? avatarFor(fromEmail, resolveAvatar) : null,
        mine: fromEmail === me, body: unwrap(row.body_text || '') || row.quote || row.snippet || '',
        summary: row.summary ?? null, internalDate: Number(row.internal_date),
        unread: (row.label_ids ?? []).includes('UNREAD'), attachments: row.attachments ?? [] };
    });
  }
  return { messages, nextCursor, totalMessages: all.length, sourcesPending };
}
async function conversationMessages(userId, ownEmail, id, options) {
  return (await conversationMessagesPage(userId, ownEmail, id, options)).messages;
}

// Version 2 includes every file and inline CID photo. A legacy empty array
// with a cached body is unchecked, not evidence that no files were sent.
const sourceHydrations = new Map();
function needsSourceInspection(row) {
  return row.body_text == null || row.attachments == null || (row.source_version ?? 0) < 2;
}

async function hydrateBodies(userId, rows, { limit = 60, concurrency = 8 } = {}) {
  const missing = rows.filter(needsSourceInspection).slice(-limit);
  if (!missing.length) return;
  let next = 0;
  const workers = Array.from({ length: Math.min(concurrency, missing.length) }, async () => {
    while (next < missing.length) {
      const row = missing[next++];
      try {
        const key = JSON.stringify([userId, row.message_id]);
        let work = sourceHydrations.get(key);
        if (!work) {
          work = (async () => {
            const full = await gmailSync.fetchFullMessage(userId, row.message_id);
            const bodyText = newText(full.payload);
            const attachments = extractAttachments(full.payload, {
              limit: Infinity, minimumBytes: 0, allowGIF: true, includeInlineImages: true,
            });
            // Persist full files and inspection version together, independently
            // of interpretation. Polling never starts a duplicate Gmail fetch.
            await messageStore.saveProfileSource(userId, row.message_id, { bodyText, attachments });
            return { body_text: bodyText, attachments, source_version: 2 };
          })();
          sourceHydrations.set(key, work);
          work.finally(() => sourceHydrations.delete(key)).catch(() => {});
        }
        Object.assign(row, await work);
      } catch (err) {
        // A failed source remains unchecked and retryable. Cached text/files
        // still render; callers cannot turn failure into an empty-file verdict.
        console.error('[conversations] body fetch failed', row.message_id, err.message);
      }
    }
  });
  await Promise.all(workers);
}

/**
 * Fetch bodies for recent mail from people, ahead of anyone opening it.
 *
 * This is the half that makes a thread open instantly. Reading a conversation
 * used to fetch every body from Gmail while the reader watched, because the
 * bodies were not there yet — the fix is to have them already, not to make the
 * waiting prettier.
 *
 * Runs on the sync schedule, bounded per pass. Only Primary mail from people,
 * because that is the only mail this surface ever shows.
 */
async function hydrateRecentPeople(userId, ownEmail, { limit = 40 } = {}) {
  const { rows } = await query(`
    SELECT message_id, from_name, from_email, participants, label_ids,
           unsubscribe_url, body_text, attachments
    FROM messages
    WHERE user_id = $1
      AND post_cutoff = TRUE
      AND (body_text IS NULL OR attachments IS NULL)
    ORDER BY internal_date DESC
    LIMIT 300
  `, [userId]);

  const me = (ownEmail ?? '').toLowerCase();
  const wanted = [];
  for (const row of rows) {
    if (!isPrimary(row.label_ids)) continue;
    const fromEmail = (row.from_email ?? '').toLowerCase();
    const mine = fromEmail === me;
    const others = [];
    if (!mine) others.push({ name: row.from_name, email: fromEmail });
    for (const p of Array.isArray(row.participants) ? row.participants : []) {
      if (p?.email && p.email.toLowerCase() !== me) others.push(p);
    }
    if (!others.length) continue;
    const hasUnsubscribe = !!row.unsubscribe_url && !mine;
    if (!others.every(p => isPerson({ ...p, hasUnsubscribe }))) continue;
    wanted.push(row);
    if (wanted.length >= limit) break;
  }

  if (!wanted.length) return { hydrated: 0 };
  await hydrateBodies(userId, wanted, { limit });
  console.log(`[bodies] ${wanted.length} message(s) from people`);
  return { hydrated: wanted.length };
}

module.exports = {
  createConversationDirectory, conversationDirectory, listConversations, listConversationsPage, conversationMessages, conversationMessagesPage, hydrateRecentPeople, hydrateBodies,
  isPerson, isPrimary, setKey,
};
