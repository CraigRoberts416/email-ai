// A sender's affirmative, inspectable removal statement is confirmation.
// A successful click, saved preferences, URL slug or model verdict is not.
const normalize = value => String(value ?? '').replace(/\s+/g, ' ').trim();
const canonical = value => normalize(value).replace(/[‘’]/g, "'");

const UNCERTAIN = /\b(if|when|once|unless|until|before|after|would|could|should|might|may|click|tap|press|select|choose|confirm|submit|example|whether|ensure|verify|not|never|failed|failure|error|unable|pending|cannot|can't|couldn't|wasn't|haven't|weren't|isn't|hasn't)\b/i;
const AFFIRMATIVE = [
  /^you(?: are|'re| have been| were) (?:(?:now|already|successfully) )*unsubscribed\b/i,
  /^you have (?:successfully )?unsubscribed\b/i,
  /^you (?:have been|were|are) (?:successfully )?removed from (?:our |the |this |all )?(?:mailing |email |marketing |newsletter |subscription )list\b/i,
  /^your (?:email(?: address)?|address) (?:has been|is|was) (?:successfully )?(?:unsubscribed|removed from (?:our |the |this |all )?(?:mailing |email |marketing |newsletter |subscription )list)\b/i,
  /^we(?: have|'ve) (?:successfully )?(?:unsubscribed you|removed (?:you|your email(?: address)?) from (?:our |the |this |all )?(?:mailing |email |marketing |newsletter |subscription )list)\b/i,
  /^you no longer receive (?:any |our |these |marketing |promotional |newsletter |further |more )*(?:emails?|email messages?|newsletters?)\b/i,
  /^(?:you are |you're )?no longer subscribed to (?:our |the |this )?(?:emails?|mailing list|newsletter)\b/i,
  /^(?:successfully unsubscribed|unsubscribed successfully|unsubscription (?:was |is )?successful)[.!]?$/i,
];

function affirmativeRemoval(statement) {
  const text = canonical(statement);
  return text.length > 0 && text.length <= 600 && !text.includes('?')
    && !UNCERTAIN.test(text) && AFFIRMATIVE.some(pattern => pattern.test(text));
}

function confirmationQuote(snapshot, proposedQuote = null) {
  // Preserve sentence/line context. A model cannot quote a promising fragment
  // out of a conditional instruction and turn it into a confirmed result.
  const statements = String(snapshot?.bodyText ?? '').split(/[\r\n]+|(?<=[.!?])\s+/)
    .map(normalize).filter(Boolean);
  const proposed = proposedQuote == null ? null : normalize(proposedQuote);
  if (proposed != null && (!proposed || !affirmativeRemoval(proposed))) return null;
  for (const statement of statements) {
    if (!affirmativeRemoval(statement)) continue;
    if (proposed != null && !statement.includes(proposed)) continue;
    return statement;
  }
  return null;
}

module.exports = { affirmativeRemoval, confirmationQuote };
