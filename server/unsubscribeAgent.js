const MAX_STEPS = 6;
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
  { pattern: /\bconfirm\b/i, score: 4 },
  { pattern: /\byes\b/i, score: 3 },
  { pattern: /\bsubmit\b/i, score: 3 },
  { pattern: /\bsave\b/i, score: 2 },
  { pattern: /\bupdate preferences?\b/i, score: 2 },
  { pattern: /\bcontinue\b/i, score: 1 },
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
  { pattern: /\bcaptcha\b/i, message: 'Unsubscribe page needs a captcha' },
  { pattern: /\bi am not a robot\b/i, message: 'Unsubscribe page needs a captcha' },
  { pattern: /\bsign in\b/i, message: 'Unsubscribe page requires a login' },
  { pattern: /\blog in\b/i, message: 'Unsubscribe page requires a login' },
  { pattern: /\bpassword\b/i, message: 'Unsubscribe page requires a login' },
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
];

const NEGATIVE_FIELD_PATTERNS = [
  /\bsubscribe\b/i,
  /\bstay subscribed\b/i,
  /\bkeep me subscribed\b/i,
  /\bweekly digest\b/i,
];

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
    if (rule.pattern.test(haystack)) return rule.message;
  }

  const hasPasswordField = snapshot.fields.some(field => field.type === 'password');
  if (hasPasswordField) return 'Unsubscribe page requires a login';

  return null;
}

function describeAction(action) {
  return truncate(action.text || action.href || `${action.tag} action`, 48);
}

function scoreAction(action, history) {
  const haystack = normalizeText(`${action.text} ${action.href}`);
  let score = scoreWithRules(haystack, POSITIVE_ACTION_RULES) + scoreWithRules(haystack, NEGATIVE_ACTION_RULES);

  if (action.disabled) score -= 20;
  if (action.tag === 'a' && /unsubscribe|optout|opt-out/i.test(action.href)) score += 6;
  if (action.tag === 'button') score += 1;
  if (!action.text && action.href) score -= 2;
  if (haystack.length > 120) score -= 2;

  if (history.some(entry => entry.signature === haystack)) score -= 12;
  return score;
}

async function maybeFillFields(page, snapshot, userEmail, emit) {
  let changed = 0;

  for (const field of snapshot.fields) {
    if (field.disabled) continue;
    const haystack = normalizeText(`${field.text} ${field.name} ${field.placeholder}`);
    const locator = page.locator(`[data-unsubscribe-agent-id="${field.id}"]`).first();

    if (field.tag === 'input' && (field.type === 'email' || matchesAny(haystack, EMAIL_FIELD_PATTERNS))) {
      if (field.value.toLowerCase() !== userEmail.toLowerCase()) {
        emit('filling', 'Filling in your email address…');
        await locator.fill(userEmail, { timeout: 5_000 }).catch(() => {});
        changed += 1;
      }
      continue;
    }

    if ((field.type === 'checkbox' || field.type === 'radio') && !field.checked) {
      if (matchesAny(haystack, POSITIVE_FIELD_PATTERNS) && !matchesAny(haystack, NEGATIVE_FIELD_PATTERNS)) {
        emit('filling', `Selecting ${truncate(field.text || field.name, 40)}…`);
        await locator.check({ timeout: 5_000 }).catch(async () => {
          await locator.click({ timeout: 5_000, force: true }).catch(() => {});
        });
        changed += 1;
      }
      continue;
    }

    if (field.tag === 'select' && field.options.length > 0) {
      const option = field.options.find(item => {
        const optionText = normalizeText(`${item.text} ${item.value}`);
        return matchesAny(optionText, POSITIVE_FIELD_PATTERNS) && !matchesAny(optionText, NEGATIVE_FIELD_PATTERNS);
      });
      if (option && option.value && option.value !== field.value) {
        emit('filling', `Updating ${truncate(field.text || field.name, 40)}…`);
        await locator.selectOption(option.value, { timeout: 5_000 }).catch(() => {});
        changed += 1;
      }
    }
  }

  if (changed > 0) await settlePage(page);
  return changed;
}

async function chooseActionWithAi(snapshot, history, openai) {
  if (!openai || snapshot.actions.length === 0) return null;

  const actions = snapshot.actions.slice(0, MAX_ACTIONS_FOR_AI).map(action => ({
    id: action.id,
    text: truncate(action.text, 120),
    href: truncate(action.href, 120),
    tag: action.tag,
    disabled: action.disabled,
  }));

  const prompt = [
    'You are selecting the next safe browser action to unsubscribe a user from email.',
    'Goal: complete the unsubscribe flow without logging in, resubscribing, or visiting unrelated pages.',
    'Return JSON only.',
    '',
    `URL: ${snapshot.url}`,
    `Title: ${snapshot.title}`,
    `Body excerpt: ${truncate(snapshot.bodyText, 1600)}`,
    `Recent action history: ${history.map(item => item.signature).slice(-4).join(' | ') || 'none'}`,
    `Available actions: ${JSON.stringify(actions)}`,
    '',
    'Return one of:',
    '{"action":"click","candidateId":"...","reason":"..."}',
    '{"action":"done","reason":"..."}',
    '{"action":"manual","reason":"..."}',
    '',
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
    return parsed;
  } catch {
    return null;
  }
}

async function chooseNextAction(snapshot, history, openai) {
  const scored = snapshot.actions
    .map(action => ({ action, score: scoreAction(action, history) }))
    .sort((a, b) => b.score - a.score);

  const best = scored[0];
  if (best && best.score >= 10) {
    return { action: 'click', candidate: best.action, reason: 'heuristic high-confidence match' };
  }

  const aiChoice = await chooseActionWithAi(snapshot, history, openai);
  if (aiChoice?.action === 'done') return { action: 'done', reason: aiChoice.reason ?? 'page confirms unsubscribe' };
  if (aiChoice?.action === 'manual') return { action: 'manual', reason: aiChoice.reason ?? 'page requires manual action' };
  if (aiChoice?.action === 'click' && aiChoice.candidateId) {
    const candidate = snapshot.actions.find(action => action.id === aiChoice.candidateId);
    if (candidate) return { action: 'click', candidate, reason: aiChoice.reason ?? 'AI-selected action' };
  }

  if (best && best.score >= 3) {
    return { action: 'click', candidate: best.action, reason: 'heuristic fallback match' };
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

async function runUnsubscribeAgent({ browser, unsubscribeUrl, userEmail, emit, openai }) {
  const context = await browser.newContext({
    ignoreHTTPSErrors: true,
    viewport: { width: 1440, height: 1200 },
  });

  let page = await context.newPage();
  const history = [];

  try {
    emit('navigating', 'Opening unsubscribe page…');
    await page.goto(unsubscribeUrl, { waitUntil: 'domcontentloaded', timeout: 20_000 });
    await settlePage(page);

    for (let step = 0; step < MAX_STEPS; step += 1) {
      emit('analyzing', `Inspecting unsubscribe page ${step + 1}/${MAX_STEPS}…`);
      let snapshot = await snapshotPage(page);

      if (detectSuccess(snapshot)) {
        return { status: 'done', message: 'Unsubscribed ✓' };
      }

      const blocker = detectManualBlocker(snapshot);
      if (blocker) {
        return { status: 'error', message: blocker };
      }

      await maybeFillFields(page, snapshot, userEmail, emit);
      snapshot = await snapshotPage(page);

      if (detectSuccess(snapshot)) {
        return { status: 'done', message: 'Unsubscribed ✓' };
      }

      const choice = await chooseNextAction(snapshot, history, openai);
      if (!choice) {
        return { status: 'error', message: 'Could not find a safe unsubscribe action' };
      }

      if (choice.action === 'done') {
        return { status: 'done', message: 'Unsubscribed ✓' };
      }

      if (choice.action === 'manual') {
        return { status: 'error', message: choice.reason || 'Unsubscribe page needs manual action' };
      }

      emit('clicking', `Clicking ${describeAction(choice.candidate)}…`);
      page = await clickAction(page, choice.candidate);
      history.push({ signature: normalizeText(`${choice.candidate.text} ${choice.candidate.href}`) });

      emit('verifying', 'Checking whether the unsubscribe worked…');
      const postClickSnapshot = await snapshotPage(page);
      if (detectSuccess(postClickSnapshot)) {
        return { status: 'done', message: 'Unsubscribed ✓' };
      }
    }

    const finalSnapshot = await snapshotPage(page);
    if (detectSuccess(finalSnapshot)) {
      return { status: 'done', message: 'Unsubscribed ✓' };
    }

    return { status: 'error', message: 'Reached the unsubscribe page but could not finish the flow' };
  } finally {
    await context.close().catch(() => {});
  }
}

module.exports = { runUnsubscribeAgent };
