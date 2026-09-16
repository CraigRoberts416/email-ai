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
]);

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

async function listConversations(userId, ownEmail, { limit = 60, resolveAvatar } = {}) {
  const { rows } = await query(`
    SELECT message_id, thread_id, subject, from_name, from_email, snippet,
           internal_date, participants, unsubscribe_url, label_ids, quote, summary
    FROM messages
    WHERE user_id = $1 AND post_cutoff = TRUE
    ORDER BY internal_date DESC
    LIMIT 2000
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
      // The quote when the model pulled one, the snippet otherwise. Never the
      // subject: a preview should be something that was said.
      c.preview = row.quote || row.snippet || '';
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
  const { rows } = await query(`
    SELECT message_id, thread_id, subject, from_name, from_email, snippet,
           internal_date, participants, label_ids, quote, summary, attachments
    FROM messages
    WHERE user_id = $1
    ORDER BY internal_date ASC
    LIMIT 4000
  `, [userId]);

  const me = (ownEmail ?? '').toLowerCase();
  const out = [];

  for (const row of rows) {
    const fromEmail = (row.from_email ?? '').toLowerCase();
    const mine = fromEmail === me;
    const others = new Set();
    if (!mine) others.add(fromEmail);
    for (const p of row.participants ?? []) {
      if (p?.email && p.email !== me) others.add(p.email.toLowerCase());
    }
    if (!isPrimary(row.label_ids)) continue;
    if (setKey(Array.from(others)) !== setKey(Array.from(wanted))) continue;

    out.push({
      messageId: row.message_id,
      threadId: row.thread_id,
      subject: row.subject,
      fromName: row.from_name,
      fromEmail,
      avatarUri: resolveAvatar ? avatarFor(fromEmail, resolveAvatar) : null,
      mine,
      body: row.quote || row.snippet || '',
      summary: row.summary ?? null,
      internalDate: Number(row.internal_date),
      unread: (row.label_ids ?? []).includes('UNREAD'),
      attachments: row.attachments ?? [],
    });
  }

  return out;
}

module.exports = { listConversations, conversationMessages, isPerson, isPrimary, setKey };
