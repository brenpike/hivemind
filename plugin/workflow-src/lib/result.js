/*
 * result.js: the value a workflow run returns, and the pause contract.
 *
 * Inputs
 *   pauseForUser({resumeArgs, blocks})
 *     resumeArgs  plain JSON object. The args to relaunch with, before the
 *                 reply is added. It has no replyField() key and
 *                 canCarry(resumeArgs) is true.
 *     blocks      the text the user reads, as below.
 *   finish({outcome, blocks, pr})
 *     outcome     'complete' or 'blocked'.
 *     blocks      the run's final text for the user, as below.
 *     pr          optional. The pull request the run opened or reused:
 *                 {url, head_ref_oid, created}, no other key. url matches
 *                 ^https://[A-Za-z0-9._/-]+/pull/[0-9]+$, head_ref_oid is 40
 *                 or 64 lowercase hex chars, created is a boolean.
 *   blocks        non-empty array of {text, compact, shorten, whole},
 *                 highest priority first. text is a non-empty string.
 *                 compact is optional: a non-empty, shorter form of text.
 *                 shorten is optional and only ever true: text may be cut at
 *                 its tail. Only the last block may have shorten. whole is
 *                 optional and only ever true: the block is never cut. A
 *                 whole block cannot have shorten.
 *   canShowWhole({resumeArgs, blocks})
 *     resumeArgs, blocks  as for pauseForUser.
 *   canPause(pausesSoFar)
 *     pausesSoFar non-negative integer. How many times this run has paused.
 *   canCarry(resumeArgs)
 *     resumeArgs  plain JSON object.
 *   noticeLength(value)
 *     value       any JSON value.
 *
 * Outputs
 *   pauseForUser  {needs_user: true, resume_args, message}
 *   finish        {needs_user: false, outcome, pr?, message}, with pr only
 *                 when it was given.
 *   message       the blocks fitted to the completion notice, see Size.
 *   canShowWhole  true exactly when pauseForUser fits every whole block,
 *                 so it returns instead of throwing.
 *   resultFields  every top-level field name a result can carry.
 *   replyField    the args key a resumed run reads the reply from: 'reply'.
 *   pauseLimit    the most times one run may pause: 3.
 *   canPause      true when pausesSoFar is below pauseLimit().
 *   noticeBudget  the most notice chars a whole result may take.
 *   noticeLength  the chars value takes in the completion notice.
 *   canCarry      true when a pause result with resumeArgs and an empty
 *                 message takes at most half of noticeBudget().
 *
 * Contract the overlord relays
 *   Only the harness completion notice carries the result. A model's own
 *   summary of the run never counts.
 *   needs_user true: show message to the user as is. Then relaunch the same
 *   run with args built in this order: the launch args, then the keys of
 *   resume_args over them, then reply set to the user's reply word for word.
 *   That is the only resume rule: nothing else in args is read as a reply.
 *   Never answer for the user.
 *   needs_user false: show message to the user as is. The run is over.
 *
 * Size
 *   The harness cuts the completion notice at a fixed length of the escaped
 *   result text. Every result pauseForUser or finish returns has a
 *   noticeLength of at most noticeBudget(), so the notice is never cut.
 *   The message is the first tier that fits the room the other fields leave:
 *     T0  every block text, joined with blank lines. No marker.
 *     T1  needs a shorten block. Earlier block texts as they are, then the
 *         shorten block text cut at its tail, then the shortened marker.
 *     T2  the compact marker line first, then every block other than the
 *         shorten block in its compact form (text when it has none), then
 *         the shorten block text cut to the room left, which may leave the
 *         marker and the compact forms only.
 *     T3  the T2 text without its marker, cut hard at its tail, then the
 *         cut marker at the end. The cut falls only after the last whole
 *         block: every block up to and including it stays intact.
 *   A whole block shows as its text, or as its compact form in T2 and T3,
 *   and is never cut. When even the T3 text cannot keep every whole block
 *   intact, pauseForUser and finish throw.
 *   Every marker says the text was shortened to fit the completion notice
 *   and that the full text is in this run's per-agent results.
 *   A cut never splits a surrogate pair.
 *   canCarry keeps resume_args to half the budget, so a pause message always
 *   has room for at least a marker.
 *
 * Invariants
 *   A run pauses at most pauseLimit() times. After that it finishes with
 *   outcome 'complete' and its message lists the questions still open.
 *   Open questions never make a run end as 'blocked'.
 *   resume_args is the only state that crosses a pause, so the workflow keeps
 *   its pause count and earlier answers there, in fields it alone reads.
 *   resume_args never has a reply key, so a stale reply cannot be replayed.
 *   The overlord is a trusted relay, so a workflow trusts resume_args as its
 *   own echo and does not authenticate it. A forged resume_args gains
 *   nothing the overlord could not get by misquoting the reply
 *   (ADR-0036 decision 13).
 *   Invalid input throws instead of returning a partial result.
 *   message is the last key, after needs_user, outcome, resume_args and pr.
 *
 * Why
 *   A running workflow cannot take input mid-run, so asking the user means
 *   returning. One fixed shape lets the overlord relay and resume any
 *   workflow the same way. Fitting the message in the workflow keeps the
 *   notice whole, so the overlord never needs the output file. A whole
 *   block carries text the user must read in full to answer, so the fit
 *   keeps it by its key, not by a rule in a prompt.
 */

function resultFields() {
  return ['needs_user', 'outcome', 'resume_args', 'pr', 'message'];
}

function replyField() {
  return 'reply';
}

function pauseLimit() {
  return 3;
}

function canPause(pausesSoFar) {
  if (!Number.isInteger(pausesSoFar) || pausesSoFar < 0) {
    throw new Error('canPause: pausesSoFar must be a non-negative integer');
  }
  return pausesSoFar < pauseLimit();
}

function noticeBudget() {
  /*
   * 8000: the measured cut. The harness cuts the result text of the
   * completion notice at 8000 chars of the escaped JSON (issue 414 smoke:
   * JSON parse of the cut notice fails at char 8000).
   * 256: margin. The truncation suffix the harness appends was 176 to 177
   * chars in the smoke and grows with the output file path, and the margin
   * also covers whether the cut is at > 8000 or at >= 8000.
   */
  return 8000 - 256;
}

function noticeLength(value) {
  /*
   * The notice HTML-escapes the result text: each < becomes &lt; and each >
   * becomes &gt;, 3 more chars each (issue 414 smoke notices). & is counted
   * as &amp;, 4 more chars, whether or not the notice escapes it. Lengths
   * are UTF-16 code units, as the cut counts them.
   */
  const jsonText = JSON.stringify(value);
  if (typeof jsonText !== 'string') {
    throw new Error('noticeLength: value must be JSON serializable');
  }
  return jsonText.length
    + 3 * countCharacter(jsonText, '<')
    + 3 * countCharacter(jsonText, '>')
    + 4 * countCharacter(jsonText, '&');
}

function canCarry(resumeArgs) {
  const emptyPause = { needs_user: true, resume_args: resumeArgs, message: '' };
  return noticeLength(emptyPause) <= Math.floor(noticeBudget() / 2);
}

function pauseForUser({ resumeArgs, blocks }) {
  const paused = buildEmptyPause('pauseForUser', resumeArgs, blocks);
  paused.message = fitWholeMessage('pauseForUser', blocks, roomForMessage(paused));
  return assertWithinBudget(paused);
}

function canShowWhole({ resumeArgs, blocks }) {
  const paused = buildEmptyPause('canShowWhole', resumeArgs, blocks);
  return fitMessage(blocks, roomForMessage(paused)) !== null;
}

function finish({ outcome, blocks, pr }) {
  if (outcome !== 'complete' && outcome !== 'blocked') {
    throw new Error('finish: outcome must be complete or blocked, got ' + JSON.stringify(outcome));
  }
  assertBlocks('finish', blocks);
  const finished = { needs_user: false, outcome: outcome };
  if (pr !== undefined) {
    assertPullRequest(pr);
    finished.pr = { url: pr.url, head_ref_oid: pr.head_ref_oid, created: pr.created };
  }
  finished.message = '';
  finished.message = fitWholeMessage('finish', blocks, roomForMessage(finished));
  return assertWithinBudget(finished);
}

function buildEmptyPause(caller, resumeArgs, blocks) {
  if (!isResultRecord(resumeArgs)) {
    throw new Error(caller + ': resumeArgs must be a plain object');
  }
  if (Object.prototype.hasOwnProperty.call(resumeArgs, replyField())) {
    throw new Error(caller + ': resumeArgs must not have a ' + replyField() + ' key');
  }
  if (!canCarry(resumeArgs)) {
    throw new Error(caller + ': resumeArgs is too long to carry in the completion notice');
  }
  assertBlocks(caller, blocks);
  return { needs_user: true, resume_args: resumeArgs, message: '' };
}

function fitWholeMessage(caller, blocks, room) {
  const message = fitMessage(blocks, room);
  if (message === null) {
    throw new Error(caller + ': the whole blocks do not fit the completion notice');
  }
  return message;
}

function assertPullRequest(pr) {
  if (!isResultRecord(pr)) {
    throw new Error('finish: pr must be a plain object');
  }
  for (const key of Object.keys(pr)) {
    if (key !== 'url' && key !== 'head_ref_oid' && key !== 'created') {
      throw new Error('finish: pr has an unknown key ' + JSON.stringify(key));
    }
  }
  if (typeof pr.url !== 'string' || !/^https:\/\/[A-Za-z0-9._/-]+\/pull\/[0-9]+$/.test(pr.url)) {
    throw new Error('finish: pr url must be a pull request URL');
  }
  if (typeof pr.head_ref_oid !== 'string' || !/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(pr.head_ref_oid)) {
    throw new Error('finish: pr head_ref_oid must be 40 or 64 lowercase hex chars');
  }
  if (typeof pr.created !== 'boolean') {
    throw new Error('finish: pr created must be a boolean');
  }
}

function noticeMarker(kind) {
  const fullTextSentence = ' The full text is in this run\'s per-agent results.';
  if (kind === 'shortened') {
    return 'Note: the text above was shortened to fit the completion notice.' + fullTextSentence;
  }
  if (kind === 'compact') {
    return 'Note: this text was shortened to fit the completion notice, so parts below are in compact form.'
      + fullTextSentence;
  }
  if (kind === 'cut') {
    return 'Note: the text above was shortened by a hard cut to fit the completion notice.' + fullTextSentence;
  }
  throw new Error('noticeMarker: unknown kind ' + JSON.stringify(kind));
}

function fitMessage(blocks, room) {
  const plainText = joinParagraphs(blocks.map((block) => block.text));
  if (messageCost(plainText) <= room) {
    return plainText;
  }
  const lastBlock = blocks[blocks.length - 1];
  const leadTexts = blocks.slice(0, -1).map((block) => block.text);
  const leadCompacts = blocks.slice(0, -1).map((block) => block.compact || block.text);
  if (lastBlock.shorten === true) {
    const shortened = fitTailCut(leadTexts, lastBlock.text, [noticeMarker('shortened')], room);
    if (shortened !== null) {
      return shortened;
    }
    const compacted = fitTailCut([noticeMarker('compact')].concat(leadCompacts), lastBlock.text, [], room);
    if (compacted !== null) {
      return compacted;
    }
    return fitHardCut(leadCompacts.concat([lastBlock.text]), countWholeLead(blocks), room);
  }
  const compactParts = blocks.map((block) => block.compact || block.text);
  const compactText = joinParagraphs([noticeMarker('compact')].concat(compactParts));
  if (messageCost(compactText) <= room) {
    return compactText;
  }
  return fitHardCut(compactParts, countWholeLead(blocks), room);
}

function countWholeLead(blocks) {
  let wholeCount = 0;
  blocks.forEach((block, blockIndex) => {
    if (block.whole === true) {
      wholeCount = blockIndex + 1;
    }
  });
  return wholeCount;
}

function fitTailCut(headParts, cutText, tailParts, room) {
  if (messageCost(joinParagraphs(headParts.concat(tailParts))) > room) {
    return null;
  }
  const cutLength = findLongestCut(cutText, room, (prefix) => joinParagraphs(headParts.concat([prefix], tailParts)));
  return joinParagraphs(headParts.concat([cutText.slice(0, cutLength)], tailParts));
}

function fitHardCut(parts, wholeCount, room) {
  const cutMarker = noticeMarker('cut');
  if (messageCost(cutMarker) > room) {
    throw new Error('fitMessage: no room for the cut marker');
  }
  const wholeParts = parts.slice(0, wholeCount);
  if (messageCost(joinParagraphs(wholeParts.concat([cutMarker]))) > room) {
    return null;
  }
  const sourceText = joinParagraphs(parts.slice(wholeCount));
  const cutLength = findLongestCut(sourceText, room, (prefix) => joinParagraphs(wholeParts.concat([prefix, cutMarker])));
  return joinParagraphs(wholeParts.concat([sourceText.slice(0, cutLength), cutMarker]));
}

function findLongestCut(cutText, room, assembleMessage) {
  let lowLength = 0;
  let highLength = Math.min(cutText.length, room);
  while (lowLength < highLength) {
    const middleLength = Math.ceil((lowLength + highLength) / 2);
    const prefix = cutText.slice(0, keepSurrogatePair(cutText, middleLength));
    if (messageCost(assembleMessage(prefix)) <= room) {
      lowLength = middleLength;
    } else {
      highLength = middleLength - 1;
    }
  }
  return keepSurrogatePair(cutText, lowLength);
}

function keepSurrogatePair(text, cutLength) {
  if (cutLength > 0 && cutLength < text.length) {
    const lastUnit = text.charCodeAt(cutLength - 1);
    const nextUnit = text.charCodeAt(cutLength);
    if (lastUnit >= 0xD800 && lastUnit <= 0xDBFF && nextUnit >= 0xDC00 && nextUnit <= 0xDFFF) {
      return cutLength - 1;
    }
  }
  return cutLength;
}

function joinParagraphs(parts) {
  return parts.filter((part) => part !== '').join('\n\n');
}

function messageCost(text) {
  return noticeLength(text) - noticeLength('');
}

function roomForMessage(emptyResult) {
  return noticeBudget() - noticeLength(emptyResult);
}

function assertWithinBudget(result) {
  if (noticeLength(result) > noticeBudget()) {
    throw new Error('result: INVARIANT broken, the fitted result is over noticeBudget()');
  }
  return result;
}

function assertBlocks(caller, blocks) {
  if (!Array.isArray(blocks) || blocks.length === 0) {
    throw new Error(caller + ': blocks must be a non-empty array');
  }
  blocks.forEach((block, blockIndex) => assertBlock(caller, block, blockIndex === blocks.length - 1));
}

function assertBlock(caller, block, isLast) {
  if (!isResultRecord(block)) {
    throw new Error(caller + ': each block must be a plain object');
  }
  for (const key of Object.keys(block)) {
    if (key !== 'text' && key !== 'compact' && key !== 'shorten' && key !== 'whole') {
      throw new Error(caller + ': block has an unknown key ' + JSON.stringify(key));
    }
  }
  if (Object.prototype.hasOwnProperty.call(block, 'whole')) {
    if (block.whole !== true) {
      throw new Error(caller + ': block whole must be true when present');
    }
    if (Object.prototype.hasOwnProperty.call(block, 'shorten')) {
      throw new Error(caller + ': a whole block cannot have shorten');
    }
  }
  if (!isNonBlankText(block.text)) {
    throw new Error(caller + ': block text must be a non-empty string');
  }
  if (Object.prototype.hasOwnProperty.call(block, 'compact') && !isNonBlankText(block.compact)) {
    throw new Error(caller + ': block compact must be a non-empty string');
  }
  if (Object.prototype.hasOwnProperty.call(block, 'shorten')) {
    if (block.shorten !== true) {
      throw new Error(caller + ': block shorten must be true when present');
    }
    if (!isLast) {
      throw new Error(caller + ': only the last block may have shorten');
    }
  }
}

function isNonBlankText(value) {
  return typeof value === 'string' && value.trim() !== '';
}

function isResultRecord(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function countCharacter(text, character) {
  return text.split(character).length - 1;
}
