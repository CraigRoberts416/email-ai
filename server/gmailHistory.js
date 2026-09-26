// Gmail history IDs are decimal strings and may exceed JavaScript's safe
// integer range. Compare provider revisions, never response arrival times.
function atOrBefore(incoming, stored) {
  return typeof incoming === 'string' && typeof stored === 'string'
    && /^\d+$/.test(incoming) && /^\d+$/.test(stored)
    && BigInt(incoming) <= BigInt(stored);
}
module.exports = { atOrBefore };
