"use strict";

import { resolveScripts, scrambleLetters } from "./alphabets.js";
import { splitGlyphs } from "./glyphs.js";
import { cellPath, durationFor, easingFor, SCRAMBLE_STEP_MS } from "./paths.js";
import { hash, mulberry32, permutation } from "./random.js";
import { originAt } from "./retarget.js";
export const DEFAULT_DURATION_MS = 650;
export const DEFAULT_STAGGER_MS = 40;

/** Cell index reserved for board-level randomness (the random stagger order). */
const BOARD_CELL = -1;
/** Cell index reserved for the board's coin: which parity of cells comes from above. */
const BOARD_DIRECTION = -2;
export function createBoard() {
  return {
    revision: 0,
    cells: []
  };
}
function drafts(board, text, now) {
  const chars = splitGlyphs(text);
  const n = Math.max(chars.length, board.cells.length);
  return Array.from({
    length: n
  }, (_, i) => ({
    i,
    to: chars[i] ?? '',
    ...originAt(board.cells[i], now)
  }));
}
function settled(d) {
  const cell = {
    i: d.i,
    from: d.to,
    to: d.to,
    path: [d.to],
    delayMs: 0,
    durationMs: 0,
    easing: 'out',
    dir: 1,
    land: 0
  };
  return d.resume ? {
    ...cell,
    resume: d.resume
  } : cell;
}
function staggerOrdinals(count, order, seed) {
  switch (order) {
    case 'ltr':
      return Array.from({
        length: count
      }, (_, i) => i);
    case 'rtl':
      return Array.from({
        length: count
      }, (_, i) => count - 1 - i);
    case 'random':
      return permutation(mulberry32(seed), count);
  }
}
function forcedDir(s, i, dir) {
  if (s.direction === 'up') return 1;
  if (s.direction === 'down') return -1;
  // -1: the new glyph comes from above.
  if (s.direction === 'random') return i % 2 === s.topParity ? -1 : 1;
  return dir;
}
function animated(d, ordinal, s) {
  const rng = mulberry32(hash(s.seed, s.revision, d.i));
  const {
    path,
    dir
  } = cellPath(s.transition, d.from, d.to, {
    scripts: s.scripts,
    rng
  });
  const cell = {
    i: d.i,
    from: d.from,
    to: d.to,
    path,
    delayMs: ordinal * s.stagger,
    durationMs: durationFor(s.transition, s.duration),
    easing: d.resume ? 'out' : easingFor(s.transition),
    dir: forcedDir(s, d.i, dir),
    land: path.length - 1
  };
  if (s.transition === 'scramble') {
    cell.stepMs = SCRAMBLE_STEP_MS;
    if (d.to !== '') cell.letters = scrambleLetters(d.to, s.scripts);
  }
  if (d.resume) cell.resume = d.resume;
  return cell;
}

/** Trailing cells that are empty on both sides carry nothing for the player; the board forgets them. */
function withoutTrailingBlanks(cells) {
  let end = cells.length;
  while (end > 0) {
    const last = cells[end - 1];
    if (last.from !== '' || last.to !== '') break;
    end--;
  }
  return cells.slice(0, end);
}
function totalMs(cells) {
  return cells.reduce((max, c) => Math.max(max, c.delayMs + c.durationMs), 0);
}
export function planTransition(board, input) {
  const transition = input.transition ?? 'reel';
  const revision = board.revision + 1;
  const seed = input.seed ?? 1;
  const all = drafts(board, input.text, input.now);
  let cells;
  if (input.instant) {
    cells = all.map(d => settled({
      i: d.i,
      to: d.to,
      from: d.to
    }));
  } else {
    const settings = {
      transition,
      duration: input.duration ?? DEFAULT_DURATION_MS,
      stagger: input.stagger ?? DEFAULT_STAGGER_MS,
      direction: input.direction ?? 'random',
      topParity: mulberry32(hash(seed, revision, BOARD_DIRECTION))() < 0.5 ? 0 : 1,
      seed,
      revision,
      // Every glyph before and after: a letter the board is leaving must still be in its alphabet.
      scripts: resolveScripts(input.alphabet ?? 'auto', all.map(d => d.from + d.to).join(''))
    };
    const changed = all.filter(d => d.from !== d.to);
    const ordinals = staggerOrdinals(changed.length, input.staggerOrder ?? 'ltr', hash(seed, revision, BOARD_CELL));
    const ordinalOf = new Map(changed.map((d, n) => [d.i, ordinals[n]]));
    cells = all.map(d => {
      const ordinal = ordinalOf.get(d.i);
      return ordinal === undefined ? settled(d) : animated(d, ordinal, settings);
    });
  }
  cells = withoutTrailingBlanks(cells);
  const plan = {
    v: 1,
    transition,
    totalMs: totalMs(cells),
    cells
  };
  const next = {
    revision,
    cells: cells.map(cell => ({
      cell,
      startMs: input.now
    }))
  };
  return {
    plan,
    board: next
  };
}
//# sourceMappingURL=plan.js.map