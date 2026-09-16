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

async function listConversations(userId, ownEmail, { limit = 200, resolveAvatar } = {}) {
  // The whole archive, not just what arrived after onboarding.
  //
  // This carried `post_cutoff = TRUE`, inherited from the feed, where it is
  // correct: a feed is what has happened since you got here. People is not a
  // feed. It answers "who do you talk to", which is a question about history,
  // and the history is the part that actually knows the answer.
  //
  // The cost was not marginal. On a real mailbox of 127,000 messages, 125,950
  // of them are pre-cutoff — so this filter was building an address book from
  // 0.8% of the evidence. Measured against Gmail's own Primary classification:
  // 8,821 qualifying messages from 794 senders in the archive, of which the
  // filter admitted 111 messages from 27 senders. Somebody with twenty years
  // of correspondence was being shown the handful of people who happened to
  // write in the days since they installed the app.
  //
  // Primary is applied in SQL rather than in the loop below so the row budget
  // is spent on candidates instead of on newsletters — it takes 127,000 rows
  // down to about 9,000, which is the whole qualifying set rather than a
  // recent slice of it. The JS `isPrimary` check stays as the guard it always
  // was; this is the same rule, pushed down.
  const { rows } = await query(`
    SELECT message_id, thread_id, subject, from_name, from_email, snippet,
           internal_date, participants, unsubscribe_url, label_ids, quote, summary,
           body_text
    FROM messages
    WHERE user_id = $1
      AND NOT EXISTS (
            SELECT 1 FROM unnest(label_ids) l
            WHERE l LIKE 'CATEGORY_%' AND l <> 'CATEGORY_PERSONAL'
          )
    ORDER BY internal_date DESC
    LIMIT 20000
  `, [userId]);

  const me = (ownEmail ?? '').toLowerCase();
  const conversations = new Map();

  for (const row of rows) {
    const fromEmail = (row.from_email ?? '').toLowerCase();
    const mine = fromEmail === me;
    const hasUnsubscribe = !!row.unsubscribe_url;

    // Gmail's own classification, and it outranks every heuristic below it.
    //
    // A word count on the display name is a weak test and the real mailbox
    // proved it immediately: "Ally Bank", "American Express", "USPS Informed
    // Delivery" and "Nextdoor Local News" are all two or three words and all
    // filed as people. Google already sorted this mail — anything carrying a
    // CATEGORY_ label is Promotions, Social, Updates or Forums, and Primary is
    // the absence of one. That is the signal.
    if (!isPrimary(row.label_ids)) continue;

    // Who is in this, other than me.
    const others = [];
    if (!mine) others.push({ name: row.from_name, email: fromEmail });
    for (const p of row.participants ?? []) {
      if (!p?.email || p.email === me) continue;
      others.push(p);
    }
    if (!others.length) continue;

    // Every participant has to be a person. One automated address on a thread
    // makes the whole thing a notification, not a conversation.
    if (!others.every(p => isPerson({ ...p, hasUnsubscribe: hasUnsubscribe && !mine }))) continue;

    const key = setKey(others.map(p => p.email));
    if (!conversations.has(key)) {
      conversations.set(key, {
        id: key,
        participants: [],
        seen: new Set(),
        lastMessageId: row.message_id,
        threadId: row.thread_id,
        subject: row.subject,
        preview: null,
        lastAt: Number(row.internal_date),
        lastFromMe: mine,
        unread: false,
        messageCount: 0,
      });
    }

    const c = conversations.get(key);
    for (const p of others) {
      if (c.seen.has(p.email)) continue;
      c.seen.add(p.email);
      c.participants.push({
        name: p.name || p.email.split('@')[0],
        email: p.email,
        avatarUri: resolveAvatar ? avatarFor(p.email, resolveAvatar) : null,
      });
    }
    c.messageCount++;
    if ((row.label_ids ?? []).includes('UNREAD') && !mine) c.unread = true;

    if (Number(row.internal_date) >= c.lastAt) {
      c.lastAt = Number(row.internal_date);
      c.lastMessageId = row.message_id;
      c.threadId = row.thread_id;
      c.subject = row.subject;
      c.lastFromMe = mine;
      // The real first line when the body has been fetched, the model's quote
      // or Gmail's snippet until then. Never the subject: a preview should be
      // something that was said.
      //
      // The list does not fetch. Sixty conversations is sixty Gmail round
      // trips for one line each, where opening a thread pays for one thread.
      c.preview = firstLine(row.body_text) || row.quote || row.snippet || '';
    }
  }

  return Array.from(conversations.values())
    .map(({ seen, ...rest }) => rest)
    .sort((a, b) => b.lastAt - a.lastAt)
    .slice(0, limit);
}

/// Every message exchanged with one participant set, oldest first — the order
/// a conversation is read in, which is the opposite of a feed.
async function conversationMessages(userId, ownEmail, id, { resolveAvatar } = {}) {
  const wanted = new Set(id.split('|').filter(Boolean));
  const addresses = Array.from(wanted);

  // Filtered in SQL, by address.
  //
  // This used to select everything and sift in JavaScript under
  // `ORDER BY internal_date ASC LIMIT 4000` — which, against 126,000
  // messages, is the OLDEST four thousand. Every conversation worth opening is
  // recent, so the rows were all from 2023 and every thread rendered empty
  // while the endpoint returned 200.
  //
  // The limit still has to be taken off the NEWEST end, which is why the sort
  // is inverted inside and put back outside. A DESC-limited subquery reversed
  // to ASC gives the most recent 500 in reading order; ASC on the outside
  // alone would silently be the same bug in a narrower scope.
  // Threads, not just addresses — because a message YOU sent names nobody
  // this query can match on.
  //
  // A sent message has `from_email` = you, which is never in the wanted set,
  // and its recipient lives in `participants` — a column that is NULL on every
  // one of the 934 sent messages in the real archive, because the backfill
  // never wrote it. So your own half of every old conversation matched neither
  // arm of the filter and silently vanished. The thread rendered as the other
  // person talking into space.
  //
  // Gmail already solved this: a reply carries the `thread_id` of what it
  // replies to, and that column IS populated on all 934. So the addresses find
  // the conversation, and the threads they belong to then pull in everything
  // else said in them — which is exactly the set the user remembers sending.
  const { rows } = await query(`
    WITH anchors AS (
      SELECT thread_id
      FROM messages
      WHERE user_id = $1
        AND (
          lower(from_email) = ANY($2::text[])
          OR EXISTS (
            SELECT 1
            FROM jsonb_array_elements(COALESCE(participants, '[]'::jsonb)) AS p
            WHERE lower(p->>'email') = ANY($2::text[])
          )
        )
      ORDER BY internal_date DESC
      LIMIT 500
    ),
    threads AS (
      SELECT DISTINCT thread_id FROM anchors
      WHERE thread_id IS NOT NULL AND thread_id <> ''
    )
    SELECT * FROM (
      SELECT message_id, thread_id, subject, from_name, from_email, snippet,
             internal_date, participants, label_ids, quote, summary, attachments,
             body_text
      FROM messages
      WHERE user_id = $1
        AND (
          lower(from_email) = ANY($2::text[])
          OR EXISTS (
            SELECT 1
            FROM jsonb_array_elements(COALESCE(participants, '[]'::jsonb)) AS p
            WHERE lower(p->>'email') = ANY($2::text[])
          )
          OR thread_id IN (SELECT thread_id FROM threads)
        )
      ORDER BY internal_date DESC
      LIMIT 1000
    ) recent
    ORDER BY internal_date ASC
  `, [userId, addresses]);

  const me = (ownEmail ?? '').toLowerCase();
  const kept = [];
  const taken = new Set();
  const threads = new Set();

  // Drafts are excluded everywhere, and duplicates of your own messages are
  // collapsed across BOTH passes.
  //
  // Scoping either of these to pass two was not enough, and the real thread
  // showed exactly why: Gmail had filed one reply three times — a DRAFT and
  // two SENT copies — and one of the SENT rows happened to carry
  // `participants`, so it matched pass one by address and skipped a guard
  // that only pass two applied. The set has to be shared or the passes
  // disagree about what has already been shown.
  // Gmail files one message more than once, and the copies are identical in
  // the only three things that can identify a message: the thread it is in,
  // who sent it, and when. Not to the second — to the millisecond. Two
  // genuinely different messages from one person in one thread at the same
  // millisecond do not happen, so this is exact rather than fuzzy.
  //
  // Comparing the text instead was the obvious idea and it did not work: one
  // copy had a fetched `body_text` and the other had only Gmail's snippet, so
  // the two fingerprints were drawn from different sources and never matched.
  // That is also why the duplicate rendered differently — a teaser shown as
  // if it were the message.
  const identity = (row, fromEmail) =>
    `${row.thread_id ?? ''}|${fromEmail}|${row.internal_date}`;
  const seen = new Map();

  /// Keeps one row per identity, preferring the copy that has a real body.
  /// Returns false when the row should be skipped.
  function admit(row, fromEmail, mine) {
    const key = seen.get(identity(row, fromEmail));
    if (key === undefined) {
      seen.set(identity(row, fromEmail), kept.length);
      kept.push({ row, fromEmail, mine });
      taken.add(row.message_id);
      return true;
    }
    // Already have this message. Upgrade it if this copy is the fetched one.
    const held = kept[key];
    if (!held.row.body_text && row.body_text) {
      kept[key] = { row, fromEmail, mine };
      taken.add(row.message_id);
    }
    return false;
  }

  // Pass one: the messages that identify this conversation by who is in them.
  for (const row of rows) {
    if (isDraft(row.label_ids)) continue;
    const fromEmail = (row.from_email ?? '').toLowerCase();
    const mine = fromEmail === me;
    const others = new Set();
    if (!mine) others.add(fromEmail);
    for (const p of row.participants ?? []) {
      if (p?.email && p.email !== me) others.add(p.email.toLowerCase());
    }
    if (!isPrimary(row.label_ids)) continue;
    if (setKey(Array.from(others)) !== setKey(Array.from(wanted))) continue;

    if (row.thread_id) threads.add(row.thread_id);
    admit(row, fromEmail, mine);
  }

  // Pass two: your own replies in those same threads.
  //
  // Only messages you sent, and only into a thread pass one already accepted
  // as this conversation — so this can add your side of a thread and nothing
  // else. It cannot pull in a third party, because it never admits a message
  // that is not from you.
  //
  // `isPrimary` is deliberately not applied here. It is a test of how Gmail
  // sorted incoming mail, and it has no meaning for something you wrote; a
  // reply you sent into a thread belongs in that thread whatever category
  // label the thread happens to carry.
  //
  // Drafts and duplicates are both excluded, and both were only visible once
  // sent mail started rendering at all. Gmail keeps the DRAFT of a reply in
  // the thread beside the message it became, and files the sent copy more
  // than once when a thread carries several labels — so one reply arrived as
  // three rows and drew three identical bubbles.
  for (const row of rows) {
    if (taken.has(row.message_id)) continue;
    if (isDraft(row.label_ids)) continue;
    const fromEmail = (row.from_email ?? '').toLowerCase();
    if (fromEmail !== me) continue;
    if (!row.thread_id || !threads.has(row.thread_id)) continue;

    admit(row, fromEmail, true);
  }

  // Both passes walked the same date-ordered rows, so the second one's
  // additions land after the first one's. Reading order has to be restored or
  // every message you sent appears in a block at the bottom.
  kept.sort((a, b) => Number(a.row.internal_date) - Number(b.row.internal_date));

  // The message, not a preview of it.
  //
  // Sync stores metadata only — `snippet` is Gmail's 200-character teaser and
  // `quote` is one sentence the model pulled out for a feed card. Either one in
  // a chat bubble is a truncated message presented as a whole one. The body is
  // fetched once per message and kept.
  //
  // NOT awaited. Opening a conversation is a read, and a read should never wait
  // on somebody else's network. Blocking here cost five to seven seconds on a
  // first open and put a spinner where a thread should have been — the fix for
  // which is not a nicer spinner, it is not fetching at read time. Sync fills
  // these in before anyone opens anything; this is the backstop for whatever it
  // missed, and it lands in the database for the next read.
  hydrateBodies(userId, kept.map(m => m.row)).catch(err =>
    console.warn('[conversations] background hydrate:', err.message));

  return kept.map(({ row, fromEmail, mine }) => ({
    messageId: row.message_id,
    threadId: row.thread_id,
    subject: row.subject,
    fromName: row.from_name,
    fromEmail,
    avatarUri: resolveAvatar ? avatarFor(fromEmail, resolveAvatar) : null,
    mine,
    // The fragments remain as a fallback, for the moment between a message
    // arriving and its body being fetched, and for the rare mail that is all
    // quoted text. An empty bubble would be worse than a short one.
    // Unwrapped on the way out as well as on the way in.
    //
    // Clearing the column at boot and re-fetching worked, and then kept
    // half-working: the instance draining during a deploy re-wrote some rows
    // with the previous code, so every release left a handful of bodies
    // wrapped. Normalising at read time is idempotent and does not care which
    // version wrote the row.
    body: unwrap(row.body_text || '') || row.quote || row.snippet || '',
    summary: row.summary ?? null,
    internalDate: Number(row.internal_date),
    unread: (row.label_ids ?? []).includes('UNREAD'),
    attachments: row.attachments ?? [],
  }));
}

/// Gmail holds the body; the database holds metadata. This closes the gap for
/// one conversation's worth of messages, writes what it finds back, and mutates
/// the rows in place so the caller reads one shape whether it hit cache or not.
///
/// Bounded three ways: only rows with no `body_text`, only the most recent 60,
/// and eight requests at a time. A conversation is a handful of messages in
/// practice — the caps are for the thread with a decade of history in it, where
/// the recent end is the part anyone scrolls to.
async function hydrateBodies(userId, rows, { limit = 60, concurrency = 8 } = {}) {
  // Either one missing is a reason to fetch, because one fetch answers both.
  // Scoping this to the body alone left the message that actually had an
  // attachment unfixed, since its body had already been stored.
  const blank = v => v === null || v === undefined;
  const missing = rows
    .filter(r => blank(r.body_text) || blank(r.attachments))
    .slice(-limit);
  if (!missing.length) return;

  let next = 0;
  const workers = Array.from({ length: Math.min(concurrency, missing.length) }, async () => {
    while (next < missing.length) {
      const row = missing[next++];
      try {
        const full = await gmailSync.fetchFullMessage(userId, row.message_id);
        const text = newText(full.payload);
        row.body_text = text;
        await query(
          'UPDATE messages SET body_text = $1 WHERE user_id = $2 AND message_id = $3',
          [text, userId, row.message_id]
        );

        // The files, from the payload already in hand.
        //
        // Nadia wrote "please also see the Token 101 attached" and the bubble
        // showed no attachment — it was waiting on the interpretation worker,
        // which is about what a message means and has nothing to do with what
        // it carries. This fetch is already paid for and the parts are right
        // here.
        if (row.attachments === null || row.attachments === undefined) {
          const files = extractAttachments(full.payload);
          row.attachments = files;
          await messageStore.setAttachments(userId, row.message_id, files);
        }
      } catch (err) {
        // A message that will not fetch falls back to its fragment rather than
        // failing the conversation. Left NULL so the next open tries again —
        // this is usually a rate limit or a deleted message, and only one of
        // those is permanent.
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
    for (const p of row.participants ?? []) {
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
  listConversations, conversationMessages, hydrateRecentPeople,
  isPerson, isPrimary, setKey,
};
