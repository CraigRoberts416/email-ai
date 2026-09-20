const MAX_STEPS = 10;
const MAX_BODY_TEXT = 4000;
const MAX_ACTIONS_FOR_AI = 12;
const { confirmationQuote } = require('./unsubscribeEvidence');

const POSITIVE_ACTION_RULES = [
  { pattern: /\bunsubscribe\b/i, score: 12 },
  { pattern: /\bopt.?out\b/i, score: 10 },
  { pattern: /\bremove me\b/i, score: 10 },
  { pattern: /\bstop (all )?(emails?|messages?)\b/i, score: 9 },
  { pattern: /\bno more emails?\b/i, score: 9 },
  { pattern: /\bglobal unsubscribe\b/i, score: 9 },
  { pattern: /\ball emails?\b/i, score: 5 },
  { pattern: /\bnotification preferences?\b/i, score: 6 },
  { pattern: /\bemail preferences?\b/i, score: 6 },
  { pattern: /\bmanage preferences?\b/i, score: 6 },
  { pattern: /\bmanage subscriptions?\b/i, score: 6 },
  { pattern: /\bemail settings?\b/i, score: 6 },
  { pattern: /\baccount settings?\b/i, score: 5 },
  { pattern: /\bturn off\b/i, score: 5 },
  { pattern: /\bdisable\b/i, score: 5 },
  { pattern: /\bconfirm\b/i, score: 4 },
  { pattern: /\byes\b/i, score: 3 },
  { pattern: /\bsubmit\b/i, score: 3 },
  { pattern: /\bfinish\b/i, score: 3 },
  { pattern: /\bdone\b/i, score: 3 },
  { pattern: /\bsave\b/i, score: 2 },
  { pattern: /\bupdate preferences?\b/i, score: 2 },
  { pattern: /\bcontinue\b/i, score: 1 },
  { pattern: /\bnext\b/i, score: 1 },
];

const NEGATIVE_ACTION_RULES = [
  { pattern: /\bsubscribe\b/i, score: -14 },
  { pattern: /\bstay subscribed\b/i, score: -14 },
  { pattern: /\bkeep (me )?subscribed\b/i, score: -14 },
  { pattern: /\bkeep receiving\b/i, score: -12 },
  { pattern: /\blog ?in\b/i, score: -15 },
  { pattern: /\bsign ?in\b/i, score: -15 },
  { pattern: /\bpassword\b/i, score: -15 },
  { pattern: /\bcreate account\b/i, score: -12 },
  { pattern: /\bprivacy\b/i, score: -8 },
  { pattern: /\bterms\b/i, score: -8 },
  { pattern: /\bhelp\b/i, score: -6 },
  { pattern: /\bsupport\b/i, score: -6 },
  { pattern: /\bcancel\b/i, score: -10 },
  { pattern: /\bgo back\b/i, score: -10 },
  { pattern: /\bback\b/i, score: -6 },
];

const RECOVERY_PAGE_PATTERNS = [
  /\boops,? something went wrong\b/i,
  /\bplease try again\b/i,
  /\btemporarily unavailable\b/i,
  /\bnotification preferences?\b/i,
  /\bupdate .*account settings?\b/i,
];

const RECOVERY_ACTION_RULES = [
  { pattern: /\bnotification preferences?\b/i, score: 8 },
  { pattern: /\bemail preferences?\b/i, score: 8 },
  { pattern: /\bmanage preferences?\b/i, score: 8 },
  { pattern: /\bmanage subscriptions?\b/i, score: 8 },
  { pattern: /\bemail settings?\b/i, score: 8 },
  { pattern: /\baccount settings?\b/i, score: 6 },
];

const MANUAL_PATTERNS = [
  { pattern: /\bcaptcha\b/i, situation: 'the unsubscribe page is blocked by a captcha' },
  { pattern: /\bi am not a robot\b/i, situation: 'the unsubscribe page is blocked by a captcha' },
  { pattern: /\bsign in\b/i, situation: 'the unsubscribe page requires the user to log in' },
  { pattern: /\blog in\b/i, situation: 'the unsubscribe page requires the user to log in' },
  { pattern: /\bpassword\b/i, situation: 'the unsubscribe page requires the user to log in' },
];

const EMAIL_FIELD_PATTERNS = [
  /\bemail\b/i,
  /\bemail address\b/i,
  /\bsubscriber\b/i,
];

const POSITIVE_FIELD_PATTERNS = [
  /\bunsubscribe\b/i,
  /\bopt.?out\b/i,
  /\bremove me\b/i,
  /\bstop (all )?(emails?|messages?)\b/i,
  /\ball emails?\b/i,
  /\bmarketing emails?\b/i,
  /\bpromotional emails?\b/i,
  /\bnewsletter\b/i,
  /\bnotification preferences?\b/i,
];

const NEGATIVE_FIELD_PATTERNS = [
  /\bsubscribe\b/i,
  /\bstay subscribed\b/i,
  /\bkeep me subscribed\b/i,
  /\bweekly digest\b/i,
];

const SURVEY_FIELD_PATTERNS = [
  /\bwhy (are you|you’re|are u) (leaving|unsubscribing)\b/i,
  /\breason\b/i,
  /\bfeedback\b/i,
  /\bhow can we improve\b/i,
  /\btell us why\b/i,
  /\bcomment\b/i,
];

const SURVEY_OPTION_PATTERNS = [
  /\btoo many (emails?|messages?)\b/i,
  /\btoo frequent\b/i,
  /\bnot relevant\b/i,
  /\bnot interested\b/i,
  /\bno longer interested\b/i,
  /\bother\b/i,
  /\bprefer not to say\b/i,
  /\bi didn'?t sign up\b/i,
  /\bnever signed up\b/i,
  /\bcontent is not relevant\b/i,
];

const MARKETING_CATEGORY_PATTERNS = [
  /\bmarketing\b/i,
  /\bnewsletter\b/i,
  /\bpromotional\b/i,
  /\boffers?\b/i,
  /\bevents?\b/i,
  /\brecommendations?\b/i,
  /\bannouncements?\b/i,
  /\bupdates?\b/i,
  /\bdigest\b/i,
];

const ESSENTIAL_CATEGORY_PATTERNS = [
  /\baccount\b/i,
  /\bsecurity\b/i,
  /\bpassword\b/i,
  /\border\b/i,
  /\breceipt\b/i,
  /\bbilling\b/i,
  /\btransaction(al)?\b/i,
  /\blegal\b/i,
  /\bsupport\b/i,
];

const EXIT_SURVEY_TEXT = 'Too many emails.';

function normalizeText(value) {
  return String(value ?? '').replace(/\s+/g, ' ').trim();
}

function truncate(value, max = 80) {
  const text = normalizeText(value);
  if (text.length <= max) return text;
  return `${text.slice(0, max - 1)}…`;
}

function matchesAny(text, patterns) {
  return patterns.some(pattern => pattern.test(text));
}

function scoreWithRules(text, rules) {
  return rules.reduce((score, rule) => score + (rule.pattern.test(text) ? rule.score : 0), 0);
}

async function settlePage(page) {
  await page.waitForLoadState('domcontentloaded', { timeout: 10_000 }).catch(() => {});
  await page.waitForLoadState('networkidle', { timeout: 5_000 }).catch(() => {});
  await page.waitForTimeout(900);
}

async function snapshotPage(page) {
  return page.evaluate(({ maxBodyText }) => {
    const normalize = value => String(value ?? '').replace(/\s+/g, ' ').trim();

    const isVisible = el => {
      const style = window.getComputedStyle(el);
      const rect = el.getBoundingClientRect();
      return style.visibility !== 'hidden'
        && style.display !== 'none'
        && rect.width > 0
        && rect.height > 0;
    };

    const getLabelText = el => {
      const parts = [];
      const direct = [
        el.getAttribute('aria-label'),
        el.getAttribute('title'),
        el.getAttribute('placeholder'),
        'value' in el ? el.value : '',
        el.textContent,
      ];
      parts.push(...direct);

      if (el.id) {
        for (const label of Array.from(document.querySelectorAll('label'))) {
          if (label.htmlFor === el.id) parts.push(label.textContent);
        }
      }

      const labelParent = el.closest('label');
      if (labelParent) parts.push(labelParent.textContent);

      const parent = el.parentElement;
      if (parent && parent !== document.body) parts.push(parent.textContent);

      return normalize(parts.filter(Boolean).join(' '));
    };

    const ensureAgentId = el => {
      if (!el.dataset.unsubscribeAgentId) {
        window.__unsubscribeAgentSeq = (window.__unsubscribeAgentSeq ?? 1) + 1;
        el.dataset.unsubscribeAgentId = String(window.__unsubscribeAgentSeq);
      }
      return el.dataset.unsubscribeAgentId;
    };

    const actions = Array.from(document.querySelectorAll('button, a[href], input[type="submit"], input[type="button"], [role="button"]'))
      .filter(isVisible)
      .map(el => ({
        id: ensureAgentId(el),
        tag: el.tagName.toLowerCase(),
        type: normalize(el.getAttribute('type')),
        text: getLabelText(el),
        href: normalize(el.getAttribute('href')),
        disabled: !!el.disabled || el.getAttribute('aria-disabled') === 'true',
      }))
      .filter(action => action.text || action.href)
      .slice(0, 60);

    const fields = Array.from(document.querySelectorAll('input, textarea, select'))
      .filter(isVisible)
      .map(el => {
        const tag = el.tagName.toLowerCase();
        const field = {
          id: ensureAgentId(el),
          tag,
          type: normalize(el.getAttribute('type') || (tag === 'textarea' ? 'textarea' : tag)),
          name: normalize(el.getAttribute('name')),
          text: getLabelText(el),
          placeholder: normalize(el.getAttribute('placeholder')),
          required: !!el.required,
          disabled: !!el.disabled || el.getAttribute('aria-disabled') === 'true',
          checked: 'checked' in el ? !!el.checked : false,
          value: 'value' in el ? normalize(el.value) : '',
          options: tag === 'select'
            ? Array.from(el.options).map(option => ({
                value: normalize(option.value),
                text: normalize(option.textContent),
              })).slice(0, 20)
            : [],
        };
        return field;
      })
      .slice(0, 60);

    return {
      url: window.location.href,
      title: normalize(document.title),
      bodyText: String(document.body?.innerText ?? '').slice(0, maxBodyText),
      actions,
      fields,
    };
  }, { maxBodyText: MAX_BODY_TEXT });
}

function detectSuccess(snapshot) {
  return confirmationQuote(snapshot) != null;
}

function detectManualBlocker(snapshot) {
  const haystack = normalizeText(`${snapshot.title} ${snapshot.bodyText}`);
  for (const rule of MANUAL_PATTERNS.slice(0, 2)) {
    if (rule.pattern.test(haystack)) return rule.situation;
  }

  const hasPasswordField = snapshot.fields.some(field => field.type === 'password');
  if (hasPasswordField) return 'the unsubscribe page requires the user to log in';

  return null;
}

function describeAction(action) {
  const raw = normalizeText(action.text || action.href || `${action.tag} action`);
  const collapsed = raw.replace(/\b(.+?)\s+\1\b/i, '$1');
  return truncate(collapsed, 48);
}

function pageLooksRecoverable(snapshot) {
  return matchesAny(normalizeText(`${snapshot.title} ${snapshot.bodyText}`), RECOVERY_PAGE_PATTERNS);
}

function pageLooksLikePreferences(snapshot) {
  const haystack = normalizeText(`${snapshot.title} ${snapshot.bodyText} ${snapshot.url}`);
  return /\b(preferences?|settings?|subscriptions?)\b/i.test(haystack);
}

function scoreAction(action, history, snapshot) {
  const haystack = normalizeText(`${action.text} ${action.href}`);
  let score = scoreWithRules(haystack, POSITIVE_ACTION_RULES) + scoreWithRules(haystack, NEGATIVE_ACTION_RULES);

  if (action.disabled) score -= 20;
  if (action.tag === 'a' && /unsubscribe|optout|opt-out/i.test(action.href)) score += 6;
  if (action.tag === 'button') score += 1;
  if (!action.text && action.href) score -= 2;
  if (haystack.length > 120) score -= 2;

  if (history.some(entry => entry.signature === haystack)) score -= 12;
  if (pageLooksRecoverable(snapshot)) score += scoreWithRules(haystack, RECOVERY_ACTION_RULES);
  return score;
}

function isSurveyField(field, snapshot) {
  const haystack = normalizeText(`${field.text} ${field.name} ${field.placeholder}`);
  return matchesAny(haystack, SURVEY_FIELD_PATTERNS)
    || (field.tag === 'textarea' && (matchesAny(snapshot.bodyText, SURVEY_FIELD_PATTERNS) || field.required));
}

function isPositiveSurveyChoice(text) {
  return matchesAny(text, SURVEY_OPTION_PATTERNS);
}

function shouldSelectField(field, snapshot) {
  const haystack = normalizeText(`${field.text} ${field.name} ${field.placeholder}`);
  if (matchesAny(haystack, NEGATIVE_FIELD_PATTERNS)) return false;

  const explicitOptOut = /\bunsubscribe\b|\bopt.?out\b|\bremove me\b|\bstop (all )?(emails?|messages?)\b/i.test(haystack);
  const marketingCategory = matchesAny(haystack, MARKETING_CATEGORY_PATTERNS);

  if (field.type === 'checkbox' && pageLooksLikePreferences(snapshot) && marketingCategory && !explicitOptOut) {
    return false;
  }

  return explicitOptOut || isPositiveSurveyChoice(haystack) || matchesAny(haystack, POSITIVE_FIELD_PATTERNS);
}

function shouldUncheckField(field, snapshot) {
  if (field.type !== 'checkbox' || !field.checked) return false;
  if (!pageLooksLikePreferences(snapshot)) return false;

  const haystack = normalizeText(`${field.text} ${field.name} ${field.placeholder}`);
  if (matchesAny(haystack, ESSENTIAL_CATEGORY_PATTERNS)) return false;
  return matchesAny(haystack, MARKETING_CATEGORY_PATTERNS);
}

function chooseSelectOption(field) {
  return field.options.find(item => {
    const optionText = normalizeText(`${item.text} ${item.value}`);
    return isPositiveSurveyChoice(optionText)
      || (matchesAny(optionText, POSITIVE_FIELD_PATTERNS) && !matchesAny(optionText, NEGATIVE_FIELD_PATTERNS));
  });
}

/// Works out everything the form needs before a single box is touched.
///
/// The counter switches from sites to fields at FILLING because that is what
/// is visibly happening — and a counter cannot say "field 2 of 4" until it
/// knows about the 4. So the plan is built in one pass and executed in
/// another; filling as we discovered fields is what left the tray with a
/// counter it had nothing to count.
function planFieldActions(snapshot, userEmail) {
  const plan = [];
  const handledRadioGroups = new Set();

  for (const field of snapshot.fields) {
    if (field.disabled) continue;
    const haystack = normalizeText(`${field.text} ${field.name} ${field.placeholder}`);

    if (field.tag === 'input' && (field.type === 'email' || matchesAny(haystack, EMAIL_FIELD_PATTERNS))) {
      if (field.value.toLowerCase() !== userEmail.toLowerCase()) {
        plan.push({
          kind: 'email', field, value: userEmail,
          label: truncate(field.text || field.placeholder || field.name, 40),
          // Your address is the only thing we ever type.
          sentence: 'Typing your address',
        });
      }
      continue;
    }

    if ((field.tag === 'textarea' || field.type === 'text') && isSurveyField(field, snapshot) && !field.value) {
      const label = truncate(field.text || field.placeholder || field.name, 40);
      plan.push({
        kind: 'survey', field, label,
        sentence: label ? `Answering "${label}"` : 'Answering their exit survey',
      });
      continue;
    }

    if (shouldUncheckField(field, snapshot)) {
      const label = truncate(field.text || field.name, 40);
      plan.push({
        kind: 'uncheck', field, label,
        sentence: label ? `Unchecking "${label}"` : 'Unchecking a pre-ticked box',
      });
      continue;
    }

    if ((field.type === 'checkbox' || field.type === 'radio') && !field.checked) {
      if (field.type === 'radio' && field.name && handledRadioGroups.has(field.name)) continue;
      if (shouldSelectField(field, snapshot)) {
        const label = truncate(field.text || field.name, 40);
        plan.push({
          kind: 'check', field, label,
          sentence: label ? `Selecting "${label}"` : 'Selecting their opt-out option',
        });
        if (field.type === 'radio' && field.name) handledRadioGroups.add(field.name);
      }
      continue;
    }

    if (field.tag === 'select' && field.options.length > 0) {
      const option = chooseSelectOption(field);
      if (option && option.value && option.value !== field.value) {
        const label = truncate(option.text || option.value, 40);
        plan.push({
          kind: 'select', field, option, label,
          sentence: label ? `Choosing "${label}"` : 'Choosing their opt-out option',
        });
      }
    }
  }

  return plan;
}

async function applyFieldAction(page, entry) {
  const locator = page.locator(`[data-unsubscribe-agent-id="${entry.field.id}"]`).first();

  switch (entry.kind) {
    case 'email':
      await locator.fill(entry.value, { timeout: 5_000 }).catch(() => {});
      return;
    case 'survey':
      await locator.fill(EXIT_SURVEY_TEXT, { timeout: 5_000 }).catch(() => {});
      return;
    case 'uncheck':
      await locator.uncheck({ timeout: 5_000 }).catch(async () => {
        await locator.click({ timeout: 5_000, force: true }).catch(() => {});
      });
      return;
    case 'check':
      await locator.check({ timeout: 5_000 }).catch(async () => {
        await locator.click({ timeout: 5_000, force: true }).catch(() => {});
      });
      return;
    case 'select':
      await locator.selectOption(entry.option.value, { timeout: 5_000 }).catch(() => {});
      return;
    default:
      return;
  }
}

async function maybeFillFields(page, snapshot, userEmail, emit) {
  const plan = planFieldActions(snapshot, userEmail);
  if (plan.length === 0) return 0;

  for (const [i, entry] of plan.entries()) {
    emit('filling', entry.sentence, {
      fieldIndex: i + 1,
      fieldTotal: plan.length,
      fieldLabel: entry.label,
      evidence:   `field ${i + 1}/${plan.length}: ${entry.kind} — ${entry.label || '(unlabelled)'}`,
    });
    await applyFieldAction(page, entry);
  }

  await settlePage(page);
  return plan.length;
}

// The rules the live sentence is written under — `09 · Status vocabulary`.
// Note what is *not* here: the app's tone. Everywhere else the voice is
// playful, but this line runs up to eleven times per sender, and anything
// witty is grating by the third sender and suspicious by the tenth. The tray
// is the one place the app speaks plainly on purpose.
const SENTENCE_RULES = [
  'RULES',
  '- Under 12 words. It renders on one line in a narrow tray; longer wraps, and a wrapping tray jumps while the user is reading it.',
  '- Present tense, active. It is happening now and the user is watching it happen.',
  '- Describe what you actually found on their page. Quote the real label the page used — "Answering: Why are you leaving?" beats "Filling out the form", and it proves the agent is really there.',
  '- No promises. Say what is being done, never what will happen.',
  '- No personality, no jokes, no exclamation marks, no emoji. This line repeats many times per run.',
  '- Never use the word "unsubscribed". Only the final confirmed state may claim that, and only after the page has been read back.',
  '- Do not open with the same words as the previous lines.',
  '- No surrounding quotes, no trailing full stop.',
];

/// Writes the live sentence. Returns `null` — never a half-English internal
/// phrase — when the model is unavailable, so the caller falls through to the
/// plain static fallback rather than shipping debug text to the tray.
async function generateMessage(openai, situation, pageContext = '', recent = []) {
  if (!openai) return null;
  try {
    const prompt = [
      'You are writing one line of status for an agent that is on a company\'s website right now, unsubscribing a user from their email.',
      'Write ONE sentence describing what is happening at this moment.',
      '',
      ...SENTENCE_RULES,
      '',
      `WHAT IS HAPPENING: ${situation}`,
      pageContext ? `PAGE: ${pageContext}` : '',
      recent.length ? `PREVIOUS LINES (do not reuse their opening):\n${recent.map(line => `- ${line}`).join('\n')}` : '',
      '',
      'Return only the sentence.',
    ].filter(Boolean).join('\n');
    const response = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [{ role: 'user', content: prompt }],
      max_tokens: 40,
    });
    const text = normalizeText(response.choices[0]?.message?.content ?? '').replace(/^["“']|["”'.]$/g, '');
    return text || null;
  } catch {
    return null;
  }
}

async function chooseActionWithVision(page, senderName, openai) {
  if (!openai) return null;
  try {
    const screenshot = await page.screenshot({ type: 'jpeg', quality: 80 });
    const base64 = screenshot.toString('base64');

    const prompt = `This is a screenshot of a web page for unsubscribing from "${senderName}" emails.

Look at the page carefully. What should I click to complete the unsubscribe?

Return JSON only — one of:
{"action":"click","x":NUMBER,"y":NUMBER,"reason":"brief explanation"}
{"action":"done","reason":"already unsubscribed","confirmationQuote":"exact visible removal confirmation"}
{"action":"manual","reason":"needs login, captcha, or human judgment"}

x and y are pixel coordinates in the screenshot (viewport is 1440×1200).
For done, quote the sender's exact affirmative statement that this reader has been removed from email.
Saved preferences, an unsubscribe button, a success URL or conditional instructions are not confirmation.
If there is no explicit removal confirmation, choose manual rather than done.`;

    const response = await openai.chat.completions.create({
      model: 'gpt-4o',
      messages: [{
        role: 'user',
        content: [
          { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${base64}`, detail: 'high' } },
          { type: 'text', text: prompt },
        ],
      }],
      max_tokens: 200,
    });

    const raw = response.choices[0]?.message?.content ?? '';
    const jsonStart = raw.indexOf('{');
    const jsonEnd = raw.lastIndexOf('}');
    if (jsonStart === -1 || jsonEnd === -1) return null;
    return JSON.parse(raw.slice(jsonStart, jsonEnd + 1));
  } catch {
    return null;
  }
}

async function chooseActionWithAi(snapshot, history, openai, recent = []) {
  if (!openai || snapshot.actions.length === 0) return null;

  const actions = snapshot.actions.slice(0, MAX_ACTIONS_FOR_AI).map(action => ({
    id: action.id,
    text: truncate(action.text, 120),
    href: truncate(action.href, 120),
    tag: action.tag,
    disabled: action.disabled,
  }));
  const fields = snapshot.fields.slice(0, MAX_ACTIONS_FOR_AI).map(field => ({
    text: truncate(field.text, 100),
    name: truncate(field.name, 60),
    type: field.type,
    checked: field.checked,
    required: field.required,
    value: truncate(field.value, 80),
  }));

  const prompt = [
    'You are selecting the next safe browser action to unsubscribe a user from email.',
    'Goal: complete the unsubscribe flow without logging in, resubscribing, or visiting unrelated pages.',
    'Preference centers, surveys, and "tell us why" screens are normal. Continue through them if they help finish the unsubscribe.',
    'If the page says to use account settings or notification preferences, it is okay to try that path as long as the page does not ask for login credentials.',
    'Return JSON only.',
    '',
    `URL: ${snapshot.url}`,
    `Title: ${snapshot.title}`,
    `Body excerpt: ${truncate(snapshot.bodyText, 1600)}`,
    `Recent action history: ${history.map(item => item.signature).slice(-4).join(' | ') || 'none'}`,
    `Available actions: ${JSON.stringify(actions)}`,
    `Visible fields: ${JSON.stringify(fields)}`,
    '',
    'Return one of:',
    '{"action":"click","candidateId":"...","reason":"...","message":"..."}',
    '{"action":"done","reason":"...","message":"...","confirmationQuote":"exact visible removal confirmation"}',
    '{"action":"manual","reason":"...","message":"..."}',
    '',
    '',
    'message: one short sentence for the status line the user is watching, written under these rules:',
    ...SENTENCE_RULES,
    recent.length ? `PREVIOUS LINES (do not reuse their opening):\n${recent.map(line => `- ${line}`).join('\n')}` : '',
    '',
    'Use "done" only if the page clearly confirms the user is off their list.',
    'For done, confirmationQuote must quote the exact affirmative removal statement in the body excerpt. Saved preferences, success URLs, future instructions and conditional text are not removal confirmation.',
    'Use "manual" if the page requires a captcha, login, or human judgment.',
  ].filter(Boolean).join('\n');

  try {
    const response = await openai.responses.create({ model: 'gpt-5', input: prompt });
    const raw = response.output_text ?? '';
    const jsonStart = raw.indexOf('{');
    const jsonEnd = raw.lastIndexOf('}');
    if (jsonStart === -1 || jsonEnd === -1) return null;
    const parsed = JSON.parse(raw.slice(jsonStart, jsonEnd + 1));
    // A done verdict must carry an exact confirming quote. The shared finish
    // boundary checks it against visible source text before accepting it.
    return {
      action:      parsed.action,
      candidateId: parsed.candidateId,
      reason:      parsed.reason,
      message:     typeof parsed.message === 'string' ? normalizeText(parsed.message) || null : null,
      confirmationQuote: typeof parsed.confirmationQuote === 'string' ? parsed.confirmationQuote : null,
    };
  } catch {
    return null;
  }
}

async function chooseNextAction(snapshot, history, openai, recent) {
  const scored = snapshot.actions
    .map(action => ({ action, score: scoreAction(action, history, snapshot) }))
    .sort((a, b) => b.score - a.score);

  const best = scored[0];
  if (best && best.score >= 10) {
    return { action: 'click', candidate: best.action, message: null };
  }

  const aiChoice = await chooseActionWithAi(snapshot, history, openai, recent);
  if (aiChoice?.action === 'done') return { action: 'done', message: aiChoice.message, confirmationQuote: aiChoice.confirmationQuote };
  if (aiChoice?.action === 'manual') return { action: 'manual', reason: aiChoice.reason ?? 'page requires manual action' };
  if (aiChoice?.action === 'click' && aiChoice.candidateId) {
    const candidate = snapshot.actions.find(action => action.id === aiChoice.candidateId);
    if (candidate) return { action: 'click', candidate, message: aiChoice.message };
  }

  if (best && best.score >= 3) {
    return { action: 'click', candidate: best.action, message: null };
  }

  return null;
}

async function clickAction(page, action) {
  const locator = page.locator(`[data-unsubscribe-agent-id="${action.id}"]`).first();
  await locator.scrollIntoViewIfNeeded().catch(() => {});

  const popupPromise = page.context().waitForEvent('page', { timeout: 2_500 }).catch(() => null);

  try {
    await locator.click({ timeout: 7_500, force: true });
  } catch {
    await locator.evaluate(el => el.click()).catch(() => {});
  }

  const popup = await popupPromise;
  const activePage = popup ?? page;
  await settlePage(activePage);
  return activePage;
}

/// What the agent saw, for the run log. The tray shows one line; the log shows
/// every step with what was actually on the page, and it is the only way to
/// debug a site-specific failure without reproducing it locally.
function evidenceOf(snapshot) {
  return truncate(`${snapshot.title || '(untitled)'} — ${snapshot.url}`, 160);
}

async function runUnsubscribeAgent({ browser, unsubscribeUrl, userEmail, emit, openai, senderName }) {
  const context = await browser.newContext({
    ignoreHTTPSErrors: true,
    viewport: { width: 1440, height: 1200 },
  });

  let page = await context.newPage();
  const history = [];

  // The last two sentences, fed back into the prompt so the next one cannot
  // open the same way. Uniform sentence shape is what makes an agent feel
  // fake, and this runs up to eleven times per sender.
  const recent = [];
  const remember = (line) => {
    if (!line) return line;
    recent.push(line);
    if (recent.length > 2) recent.shift();
    return line;
  };

  // Every emit routes through here so the sentence is remembered exactly once,
  // whoever wrote it.
  const say = (step, message, extra) => emit(step, remember(message), extra);

  const finish = async (step, situation, snapshot, message = null, proposedQuote = undefined) => {
    const quote = step === 'done' ? confirmationQuote(snapshot, proposedQuote) : null;
    if (step === 'done' && !quote) {
      return { step: 'needs_you', outcome: 'outcome_unknown',
        message: 'The page did not provide a clear removal confirmation. Check it yourself.',
        evidence: snapshot ? evidenceOf(snapshot) : null, handoffURL: snapshot?.url || unsubscribeUrl };
    }
    return {
      step,
      message: message ?? await generateMessage(openai, situation, snapshot?.title ?? '', recent),
      evidence: quote ? `Sender confirmation: “${quote}” — ${snapshot.url}` : snapshot ? evidenceOf(snapshot) : null,
      handoffURL: ['needs_you', 'no_link', 'failed'].includes(step) ? (snapshot?.url || unsubscribeUrl) : null,
      outcome: step === 'done' ? 'sender_confirmed' : history.length > 0 ? 'outcome_unknown' : null,
    };
  };

  // ANALYZING is reported once per page, not once per pass of the loop. The
  // same sentence arriving three times while nothing on screen changes reads
  // as a stuck agent, and the fallback line is meant never to be seen twice in
  // one run. A new URL is a new thing to read, and gets its own line.
  let lastAnalyzed = null;
  const sayAnalyzing = async (snapshot) => {
    if (snapshot.url === lastAnalyzed) return;
    lastAnalyzed = snapshot.url;
    say(
      'analyzing',
      await generateMessage(openai, `reading ${senderName}'s page to find the unsubscribe control`, snapshot.title, recent),
      { evidence: evidenceOf(snapshot) },
    );
  };

  try {
    say('navigating', null);
    await page.goto(unsubscribeUrl, { waitUntil: 'domcontentloaded', timeout: 20_000 });
    await settlePage(page);

    for (let step = 0; step < MAX_STEPS; step += 1) {
      let snapshot = await snapshotPage(page);
      await sayAnalyzing(snapshot);

      if (detectSuccess(snapshot)) {
        return finish('done', `${senderName}'s own page confirms the user is off their list`, snapshot);
      }

      // We do not solve CAPTCHAs and we do not log in as anyone. Saying why
      // builds more trust than quietly failing, and solving them is how agents
      // get the whole product blocked.
      const blocker = detectManualBlocker(snapshot);
      if (blocker) {
        return finish('needs_you', blocker, snapshot);
      }

      await maybeFillFields(page, snapshot, userEmail, say);
      snapshot = await snapshotPage(page);

      if (detectSuccess(snapshot)) {
        return finish('done', `${senderName}'s own page confirms the user is off their list`, snapshot);
      }

      const choice = await chooseNextAction(snapshot, history, openai, recent);
      if (!choice) {
        // Scroll down and try once more before giving up
        const scrolled = await page.evaluate(() => {
          const before = window.scrollY;
          window.scrollBy(0, 600);
          return window.scrollY !== before;
        });
        if (scrolled) {
          await page.waitForTimeout(800);
          continue;
        }

        // Vision fallback: take a screenshot and let GPT-4o look at the page
        // and decide what to click — works on any page regardless of HTML structure.
        say(
          'analyzing',
          await generateMessage(openai, `looking at a screenshot of ${senderName}'s page to find the control`, snapshot.title, recent),
          { evidence: `vision pass — ${evidenceOf(snapshot)}` },
        );
        const visionChoice = await chooseActionWithVision(page, senderName, openai);
        if (visionChoice?.action === 'click' && visionChoice.x != null && visionChoice.y != null) {
          say(
            'clicking',
            await generateMessage(openai, visionChoice.reason || `clicking a control on ${senderName}'s page`, snapshot.title, recent),
            { evidence: evidenceOf(snapshot) },
          );
          await page.mouse.click(visionChoice.x, visionChoice.y);
          history.push({ signature: `vision click ${visionChoice.x},${visionChoice.y}` });
          await settlePage(page);
          const afterSnapshot = await snapshotPage(page);
          if (detectSuccess(afterSnapshot)) {
            return finish('done', `${senderName}'s own page confirms the user is off their list`, afterSnapshot);
          }
          continue;
        }
        if (visionChoice?.action === 'done') {
          return finish('done', `${senderName}'s own page confirms the user is off their list`, snapshot, null, visionChoice.confirmationQuote ?? '');
        }
        if (visionChoice?.action === 'manual') {
          return finish('needs_you', visionChoice.reason || `${senderName}'s page wants a person`, snapshot);
        }

        // Two different facts, and the difference is the whole point of the
        // enum. A page that is broken or mid-wobble is worth another attempt;
        // a page with nothing on it to click is a standing fact about this
        // sender, and the user gets offered the local fallback instead.
        if (pageLooksRecoverable(snapshot)) {
          return finish('failed', `${senderName}'s unsubscribe page is broken and offers no safe fallback link`, snapshot);
        }
        return history.length > 0
          ? finish('needs_you', `${senderName}'s page has not confirmed removal after the attempted action`, snapshot)
          : finish('no_link', `there is nothing on ${senderName}'s page to click`, snapshot);
      }

      if (choice.action === 'done') {
        return finish('done', `${senderName}'s own page confirms the user is off their list`, snapshot, choice.message, choice.confirmationQuote ?? '');
      }

      if (choice.action === 'manual') {
        return finish('needs_you', choice.reason || `${senderName}'s page wants a person`, snapshot);
      }

      const actionLabel = choice.candidate ? truncate(describeAction(choice.candidate), 40) : 'next step';
      say(
        'clicking',
        choice.message ?? await generateMessage(openai, `clicking "${actionLabel}" on ${senderName}'s page`, snapshot.title, recent),
        { evidence: `clicked "${actionLabel}" — ${evidenceOf(snapshot)}` },
      );
      page = await clickAction(page, choice.candidate);
      history.push({ signature: normalizeText(`${choice.candidate.text} ${choice.candidate.href}`) });

      // The step that separates a real unsubscribe from a hopeful one: the
      // page is read back before anything claims it worked.
      const postClickSnapshot = await snapshotPage(page);
      say(
        'verifying',
        await generateMessage(openai, `re-reading ${senderName}'s page to see whether "${actionLabel}" took`, postClickSnapshot.title, recent),
        { evidence: evidenceOf(postClickSnapshot) },
      );
      if (detectSuccess(postClickSnapshot)) {
        return finish('done', `${senderName}'s own page confirms the user is off their list`, postClickSnapshot);
      }
    }

    const finalSnapshot = await snapshotPage(page);
    if (detectSuccess(finalSnapshot)) {
      return finish('done', `${senderName}'s own page confirms the user is off their list`, finalSnapshot);
    }

    return finish('failed', `ran out of steps on ${senderName}'s page without reaching a confirmation`, finalSnapshot);
  } finally {
    await context.close().catch(() => {});
  }
}

module.exports = { runUnsubscribeAgent };
