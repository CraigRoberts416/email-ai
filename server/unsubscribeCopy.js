function pick(list, seed = 0) {
  return list[Math.abs(seed) % list.length];
}

function queuedMessage(seed = 0) {
  return pick([
    'Alright… let’s break you out of this list 🕶️',
    'Initiating unsubscribe heist…',
    'Going undercover…',
    'We’re getting you out of here…',
  ], seed);
}

function navigatingMessage(seed = 0) {
  return pick([
    'Tracking down their escape hatch…',
    'Finding where they hide the unsubscribe…',
    'Entering enemy territory…',
    'Locating the tiny link at the bottom…',
  ], seed);
}

function analyzingMessage(step, maxSteps) {
  const phrase = pick([
    'Working through their maze…',
    'Still navigating their nonsense…',
    'They really do not want you to leave…',
  ], step);
  return `${phrase} (${step + 1}/${maxSteps})`;
}

function fillingEmailMessage() {
  return 'Typing your email in…';
}

function fillingChoiceMessage() {
  return 'Choosing the right option…';
}

function fillingTrapMessage() {
  return "Dodging the 'stay subscribed' traps…";
}

function fillingReasonMessage() {
  return 'Answering their little exit survey…';
}

function clickingMessage(actionText = '', step = 0) {
  const text = String(actionText).toLowerCase();

  if (/preferences|settings/.test(text)) {
    return pick([
      'Taking the scenic route through preferences…',
      'Detouring through their settings maze…',
    ], step);
  }

  if (/confirm|submit|save|update|continue|next|finish|done/.test(text)) {
    return pick([
      'Clicking confirm… no turning back…',
      'Found something… investigating…',
    ], step);
  }

  if (/unsubscribe|opt.?out|remove/.test(text)) {
    return pick([
      'Scanning for the unsubscribe button…',
      'They’re hiding it… of course they are…',
      'Zooming in… yep, that’s it…',
    ], step);
  }

  return pick([
    'Found something… investigating…',
    'Zooming in… yep, that’s it…',
  ], step);
}

function verifyingMessage(step = 0) {
  return pick([
    'Making sure you’re actually free…',
    'Checking they didn’t fake it…',
    'Verifying your escape…',
  ], step);
}

function doneMessage(step = 0) {
  return pick([
    'You’re free ✓',
    'You’re officially out ✓',
    'Done. They won’t bother you again ✓',
    'And just like that… you’re gone ✓',
    'Clean exit ✓',
  ], step);
}

function emailDoneMessage(step = 0) {
  return pick([
    "Sent the 'unsubscribe me' note ✓",
    'We asked them nicely (but firmly) ✓',
  ], step);
}

module.exports = {
  analyzingMessage,
  clickingMessage,
  doneMessage,
  emailDoneMessage,
  fillingChoiceMessage,
  fillingEmailMessage,
  fillingReasonMessage,
  fillingTrapMessage,
  navigatingMessage,
  queuedMessage,
  verifyingMessage,
};
