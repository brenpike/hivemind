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
 *
 * Outputs
 *   applyApprovalChoices(approvals, asks, choices)  a new list: for each
 *              choice, the chosen option adds its items not yet listed, and
 *              every item only its sibling options list is removed. The
 *              key of an item is its category and item text.
 *   hasDestructiveOption(ask)  true when an option of ask lists an item.
 *
 * Invariants
 *   A contractRows() check is a function of the built script, not of
 *   main.js: the build bundles this module into it, so a row can name a
 *   function of this module.
 *   Only a choice code read from the user's own reply changes the list: a
 *   decision the run took never reaches it, and a reply in the user's own
 *   words gives no choice, so it approves nothing. The list is a function
 *   of the replies alone, so a resume that replays them rebuilds it.
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
