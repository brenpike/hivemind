/*
 * standard-delivery approvals.js: the approval rules of the
 * standard-delivery workflow, the destructive changes the user's own
 * replies approved.
 *
 * Inputs
 *   approvals  run.approvals of main.js createRunState: a list of
 *              {category, item}, one per key.
 *   ask        one ask, as resolveDecision (plan.js) builds it. Its items
 *              are ask.items when set, one list per option in option order,
 *              else the destructive list of each brief option, [] when an
 *              option lists none. An item is read as {category, item}.
 *   asks       the asks one pause showed, in shown order.
 *   choices    readReplyChoices (lib/brief.js) of the reply to that pause.
 *   result     a blocked worker or gate edit result that passed its schema.
 *   description  the description of a destructive list schema.
 *
 * Outputs
 *   applyApprovalChoices(approvals, asks, choices)  a new list: for each
 *              choice, the chosen option adds its items not yet listed, and
 *              every item only its sibling options list is removed. The
 *              key of an item is its category and item text.
 *   hasDestructiveOption(ask)  true when an option of ask lists an item.
 *   buildDestructiveListSchema(description)  the one schema of the
 *              destructive list of a worker, gate edit or review result: at
 *              most 4 entries {category, item}, category an integer 1 to
 *              10, item a string of at most 160 code points.
 *   readGateHold(result, approvals)  the type of a blocked result:
 *              {nextAction: 'report'} when its blocker gives no reason; for a
 *              hold, a stage of destructive-fix-gate or a blocker starting
 *              with the security-policy.md gate text, {nextAction, holds},
 *              holds its listed items not in approvals and nextAction
 *              approve, or report when holds is empty, since a hold that
 *              lists no item, or only approved ones, holds back no change
 *              the run can ask about; else {nextAction} with its own
 *              next_action.
 *   describeGateWait()  the words after a step name of a step that waits
 *              for approval at the destructive-fix gate.
 *   describeApprovalsHome(approvals, replyHome)  the replyHome of
 *              dataBlocksSentence (lib/facts.js) for a prompt that also
 *              carries the approvals block: replyHome as given when
 *              approvals is empty.
 *   listApprovalsBlock(approvals)  [] when approvals is empty, else the
 *              one approvals data block.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   Only a choice code read from the user's own reply changes the list: a
 *   decision the run took never reaches it, and a reply in the user's own
 *   words gives no choice, so it approves nothing. The list is a function
 *   of the replies alone, so a resume that replays them rebuilds it.
 *   A prompt carries the approvals block, named the user's decision by its
 *   data line, only when the list is not empty, so with no approval every
 *   prompt is as before.
 *
 * Why
 *   Only the user's own reply choosing an option that names a destructive
 *   change approves it (security-policy.md, Destructive Fix Confirmation
 *   Gate, issue 499), so the rule lives in one place every reply round
 *   calls.
 */

function applyApprovalChoices(approvals, asks, choices) {
  const shownLabels = choices.length === 0 ? [] : listShownLabels(asks);
  return choices.reduce((kept, choice) => applyApprovalChoice(kept, listOptionItems(asks[shownLabels.indexOf(choice.label)]), choice.optionIndex), [...approvals]);
}

function applyApprovalChoice(approvals, optionItems, optionIndex) {
  const chosen = optionItems[optionIndex] ?? [];
  const withdrawn = optionItems.flat().filter((entry) => !hasItem(chosen, entry));
  const kept = approvals.filter((entry) => !hasItem(withdrawn, entry));
  return chosen.reduce((list, entry) => (hasItem(list, entry) ? list : list.concat([entry])), kept);
}

function hasDestructiveOption(ask) {
  return listOptionItems(ask).some((items) => items.length > 0);
}

function listOptionItems(ask) {
  const options = Array.isArray(ask.brief.options) ? ask.brief.options : [];
  const lists = Array.isArray(ask.items) ? ask.items : options.map((option) => option.destructive);
  return lists.map((items) => (Array.isArray(items) ? items.map(readItem) : []));
}

function readItem(entry) {
  return { category: entry.category, item: entry.item };
}

function hasItem(items, entry) {
  return items.some((other) => other.category === entry.category && other.item === entry.item);
}

function buildDestructiveListSchema(description) {
  const entry = {
    type: 'object',
    additionalProperties: false,
    required: ['category', 'item'],
    properties: { category: { type: 'integer', enum: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] }, item: { type: 'string', maxLength: 160 } }
  };
  return { type: 'array', maxItems: 4, description: description, items: entry };
}

function readGateHold(result, approvals) {
  if (quoteDiagnostic(result.blocker) === undefined) {
    return { nextAction: 'report' };
  }
  if (result.stage !== 'destructive-fix-gate' && !isDestructiveGateBlocker(result.blocker)) {
    return { nextAction: result.next_action };
  }
  const listed = Array.isArray(result.destructive) ? result.destructive.map(readItem) : [];
  const holds = listed.filter((entry) => !hasItem(approvals, entry));
  return { nextAction: holds.length === 0 ? 'report' : 'approve', holds: holds };
}

function isDestructiveGateBlocker(text) {
  return text.trimStart().toLowerCase().startsWith('proposed fix requires human confirmation');
}

function describeGateWait() {
  return ' waits for your approval at the destructive-fix gate';
}

function describeApprovalsHome(approvals, replyHome) {
  if (approvals.length === 0) {
    return replyHome;
  }
  return replyHome === undefined ? 'The approvals block' : replyHome + ', like the approvals block,';
}

function listApprovalsBlock(approvals) {
  return approvals.length === 0 ? [] : [formatDataBlock('approvals', approvals)];
}
