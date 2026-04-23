const MAX_STEPS = 10;
const MAX_BODY_TEXT = 4000;
const MAX_ACTIONS_FOR_AI = 12;

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

const SUCCESS_PATTERNS = [
  /\byou('?| a)re unsubscribed\b/i,
  /\bsuccessfully unsubscribed\b/i,
  /\byou have been unsubscribed\b/i,
  /\byou have been removed\b/i,
  /\bremoved from (our )?(mailing|email) list\b/i,
  /\bno longer receive\b/i,
  /\bpreferences? (have been )?(updated|saved)\b/i,
  /\bsubscription status (has been )?updated\b/i,
  /\bemail settings (have been )?(updated|saved)\b/i,
  /\bunsubscribe(d)? successfully\b/i,
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
      bodyText: normalize(document.body?.innerText ?? '').slice(0, maxBodyText),
      actions,
      fields,
    };
  }, { maxBodyText: MAX_BODY_TEXT });
}

function detectSuccess(snapshot) {
  const haystack = normalizeText(`${snapshot.title} ${snapshot.bodyText} ${snapshot.url}`);
  if (matchesAny(haystack, SUCCESS_PATTERNS)) return true;
  if (/unsubscribe\/success/i.test(snapshot.url)) return true;
  if (/status=unsubscribed/i.test(snapshot.url)) return true;
  return false;
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

async function maybeFillFields(page, snapshot, userEmail, emit) {
  let changed = 0;
  const handledRadioGroups = new Set();

  for (const field of snapshot.fields) {
    if (field.disabled) continue;
    const haystack = normalizeText(`${field.text} ${field.name} ${field.placeholder}`);
    const locator = page.locator(`[data-unsubscribe-agent-id="${field.id}"]`).first();

    if (field.tag === 'input' && (field.type === 'email' || matchesAny(haystack, EMAIL_FIELD_PATTERNS))) {
      if (field.value.toLowerCase() !== userEmail.toLowerCase()) {
        emit('filling', 'Typing in your email address…');
        await locator.fill(userEmail, { timeout: 5_000 }).catch(() => {});
        changed += 1;
      }
      continue;
    }

    if ((field.tag === 'textarea' || field.type === 'text') && isSurveyField(field, snapshot) && !field.value) {
      const label = truncate(field.text || field.placeholder || field.name, 40);
      emit('filling', label ? `Answering: "${label}"…` : 'Filling out the exit survey…');
      await locator.fill(EXIT_SURVEY_TEXT, { timeout: 5_000 }).catch(() => {});
      changed += 1;
      continue;
    }

    if (shouldUncheckField(field, snapshot)) {
      const label = truncate(field.text || field.name, 40);
      emit('filling', label ? `Unchecking "${label}"…` : 'Unchecking a sneaky box…');
      await locator.uncheck({ timeout: 5_000 }).catch(async () => {
        await locator.click({ timeout: 5_000, force: true }).catch(() => {});
      });
      changed += 1;
      continue;
    }

    if ((field.type === 'checkbox' || field.type === 'radio') && !field.checked) {
      if (field.type === 'radio' && field.name && handledRadioGroups.has(field.name)) continue;
      if (shouldSelectField(field, snapshot)) {
        const label = truncate(field.text || field.name, 40);
        emit('filling', label ? `Selecting "${label}"…` : 'Picking the right option…');
        await locator.check({ timeout: 5_000 }).catch(async () => {
          await locator.click({ timeout: 5_000, force: true }).catch(() => {});
        });
        changed += 1;
        if (field.type === 'radio' && field.name) handledRadioGroups.add(field.name);
      }
      continue;
    }

    if (field.tag === 'select' && field.options.length > 0) {
      const option = chooseSelectOption(field);
      if (option && option.value && option.value !== field.value) {
        const label = truncate(option.text || option.value, 40);
        emit('filling', label ? `Selecting "${label}"…` : 'Picking the right option…');
        await locator.selectOption(option.value, { timeout: 5_000 }).catch(() => {});
        changed += 1;
      }
    }
  }

  if (changed > 0) await settlePage(page);
  return changed;
}

async function generateMessage(openai, tone, situation, pageContext = '') {
  if (!openai) return situation;
  try {
    const prompt = [
      tone ?? '',
      '',
      'Write a single short status message (under 12 words) to show the user in a toast notification.',
      `Situation: ${situation}`,
      pageContext ? `Page context: ${pageContext}` : '',
      'Return only the message text, nothing else.',
    ].filter(Boolean).join('\n');
    const response = await openai.responses.create({ model: 'gpt-5', input: prompt });
    return response.output_text?.trim() || situation;
  } catch {
    return situation;
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
{"action":"done","reason":"already unsubscribed"}
{"action":"manual","reason":"needs login, captcha, or human judgment"}

x and y are pixel coordinates in the screenshot (viewport is 1440×1200).`;

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

async function chooseActionWithAi(snapshot, history, openai, tone) {
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
    tone ?? '',
    '',
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
    '{"action":"done","reason":"...","message":"..."}',
    '{"action":"manual","reason":"...","message":"..."}',
    '',
    'message: one short sentence for the user\'s status toast. Describe what you found on this page or what you\'re about to do. Write it in the app\'s tone.',
    'Use "done" only if the page clearly confirms the user is unsubscribed.',
    'Use "manual" if the page requires a captcha, login, or human judgment.',
  ].join('\n');

  try {
    const response = await openai.responses.create({ model: 'gpt-5', input: prompt });
    const raw = response.output_text ?? '';
    const jsonStart = raw.indexOf('{');
    const jsonEnd = raw.lastIndexOf('}');
    if (jsonStart === -1 || jsonEnd === -1) return null;
    const parsed = JSON.parse(raw.slice(jsonStart, jsonEnd + 1));
    return {
      action:      parsed.action,
      candidateId: parsed.candidateId,
      reason:      parsed.reason,
      message:     typeof parsed.message === 'string' ? parsed.message.trim() : null,
    };
  } catch {
    return null;
  }
}

async function chooseNextAction(snapshot, history, openai, tone) {
  const scored = snapshot.actions
    .map(action => ({ action, score: scoreAction(action, history, snapshot) }))
    .sort((a, b) => b.score - a.score);

  const best = scored[0];
  if (best && best.score >= 10) {
    return { action: 'click', candidate: best.action, message: null };
  }

  const aiChoice = await chooseActionWithAi(snapshot, history, openai, tone);
  if (aiChoice?.action === 'done') return { action: 'done', message: aiChoice.message };
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

async function runUnsubscribeAgent({ browser, unsubscribeUrl, userEmail, emit, openai, senderName, tone }) {
  const context = await browser.newContext({
    ignoreHTTPSErrors: true,
    viewport: { width: 1440, height: 1200 },
  });

  let page = await context.newPage();
  const history = [];

  try {
    emit('navigating', `Loading ${senderName}'s unsubscribe page…`);
    await page.goto(unsubscribeUrl, { waitUntil: 'domcontentloaded', timeout: 20_000 });
    await settlePage(page);

    for (let step = 0; step < MAX_STEPS; step += 1) {
      let snapshot = await snapshotPage(page);

      if (detectSuccess(snapshot)) {
        const msg = await generateMessage(openai, tone, `successfully unsubscribed from ${senderName}`, snapshot.title);
        return { status: 'done', message: msg };
      }

      const blocker = detectManualBlocker(snapshot);
      if (blocker) {
        const msg = await generateMessage(openai, tone, blocker, snapshot.title);
        return { status: 'error', message: msg };
      }

      await maybeFillFields(page, snapshot, userEmail, emit);
      snapshot = await snapshotPage(page);

      if (detectSuccess(snapshot)) {
        const msg = await generateMessage(openai, tone, `successfully unsubscribed from ${senderName}`, snapshot.title);
        return { status: 'done', message: msg };
      }

      const choice = await chooseNextAction(snapshot, history, openai, tone);
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
        emit('analyzing', `Taking a closer look at ${senderName}'s page…`);
        const visionChoice = await chooseActionWithVision(page, senderName, openai);
        if (visionChoice?.action === 'click' && visionChoice.x != null && visionChoice.y != null) {
          emit('clicking', `Spotted something — clicking it now…`);
          await page.mouse.click(visionChoice.x, visionChoice.y);
          await settlePage(page);
          const afterSnapshot = await snapshotPage(page);
          if (detectSuccess(afterSnapshot)) {
            const msg = await generateMessage(openai, tone, `successfully unsubscribed from ${senderName}`, afterSnapshot.title);
            return { status: 'done', message: msg };
          }
          continue;
        }
        if (visionChoice?.action === 'done') {
          const msg = await generateMessage(openai, tone, `successfully unsubscribed from ${senderName}`, snapshot.title);
          return { status: 'done', message: msg };
        }
        if (visionChoice?.action === 'manual') {
          const msg = await generateMessage(openai, tone, visionChoice.reason || `${senderName}'s page requires manual action`, snapshot.title);
          return { status: 'error', message: msg };
        }

        if (pageLooksRecoverable(snapshot)) {
          const msg = await generateMessage(openai, tone, `${senderName}'s unsubscribe page appears broken and no safe fallback link was found`, snapshot.title);
          return { status: 'error', message: msg };
        }
        const msg = await generateMessage(openai, tone, `could not find a way to unsubscribe from ${senderName} on this page`, snapshot.title);
        return { status: 'error', message: msg };
      }

      if (choice.action === 'done') {
        return { status: 'done', message: choice.message ?? await generateMessage(openai, tone, `successfully unsubscribed from ${senderName}`, snapshot.title) };
      }

      if (choice.action === 'manual') {
        const manualMsg = await generateMessage(openai, tone, choice.reason || `${senderName}'s unsubscribe page requires manual action`, snapshot.title);
        return { status: 'error', message: manualMsg };
      }

      const clickMsg = choice.message
        ?? (choice.candidate ? `Clicking "${truncate(describeAction(choice.candidate), 30)}"…` : 'Clicking…');
      emit('clicking', clickMsg);
      page = await clickAction(page, choice.candidate);
      history.push({ signature: normalizeText(`${choice.candidate.text} ${choice.candidate.href}`) });

      emit('verifying', 'Checking if that did it…');
      const postClickSnapshot = await snapshotPage(page);
      if (detectSuccess(postClickSnapshot)) {
        return { status: 'done', message: 'Done ✓' };
      }
    }

    const finalSnapshot = await snapshotPage(page);
    if (detectSuccess(finalSnapshot)) {
      const doneMsg = await generateMessage(openai, tone, `successfully unsubscribed from ${senderName}`, finalSnapshot.title);
      return { status: 'done', message: doneMsg };
    }

    const finalMsg = await generateMessage(openai, tone, `reached ${senderName}'s unsubscribe page but could not complete the flow`, finalSnapshot.title);
    return { status: 'error', message: finalMsg };
  } finally {
    await context.close().catch(() => {});
  }
}

module.exports = { runUnsubscribeAgent };
