"use strict";

import { isUpperCase, resolveScripts, scrambleLetters, scriptOf } from "./alphabets.js";
import { splitGlyphs } from "./glyphs.js";
import { hash, mulberry32, pick } from "./random.js";
export const LOADING_WORD_MS = 430;
export const LOADING_WORDS = 8;

/** Cell index reserved for word generation; real cells are 0-based. */
const WORDS_CELL = -2;

/**
 * How long the loading words are: a number of cells, or a range the lengths are drawn from — the
 * shortest and the longest text the board is waiting for, so the words try on the sizes the real
 * one may come in.
 */

function randomWord(length, s, previous, rng) {
  return Array.from({
    length
  }, (_, i) => {
    const letter = pick(rng, s.letters);
    // A cell that would keep its letter looks stuck; one reroll is enough to break most repeats.
    return letter === previous[i] ? pick(rng, s.letters) : letter;
  });
}
function lengthRange(length, exact) {
  if (typeof length === 'number') {
    return exact ? {
      min: length,
      max: length
    } : {
      min: length - 1,
      max: length + 1
    };
  }
  // An app's numbers, not ours: whole cells, at least one, in either order.
  const a = Math.floor(length.min);
  const b = Math.floor(length.max);
  return {
    min: Math.min(a, b),
    max: Math.max(a, b)
  };
}
function randomWords(length, s, rng, exact) {
  const range = lengthRange(length, exact);
  const min = Math.max(1, Number.isFinite(range.min) ? range.min : 1);
  const max = Math.max(min, Number.isFinite(range.max) ? range.max : min);
  const words = [];
  for (let w = 0; w < LOADING_WORDS; w++) {
    const len = min + Math.floor(rng() * (max - min + 1));
    words.push(randomWord(len, s, words[w - 1] ?? [], rng));
  }
  return words;
}

/**
 * A looping plan that shows a new random word every `wordMs`.
 *
 * Every cell steps exactly once per word (a blank where the word is shorter), on a linear
 * clock, so word w is on screen at w × wordMs for every cell and `planTransition` on the
 * returned board lands from whatever word is visible. The roll rule's random letters on
 * appear/disappear are not inserted here: a cell has one clock, and extra steps would pull
 * it off the word grid.
 */
/**
 * The script the loading words are written in. `auto` takes the text's letters; a text with none
 * — a count, a price, a time — takes its digits, so a number loads as numbers in its own numeral
 * system rather than as Latin words. A named or custom alphabet is used as given.
 */
function wordScript(scripts, alphabet, glyphs) {
  if (alphabet === undefined || alphabet === 'auto') {
    const seen = glyphs.map(g => scriptOf(g, scripts));
    const found = seen.find(s => s !== undefined && s.id !== 'digit') ?? seen.find(s => s !== undefined);
    if (found) return found;
  }
  return scripts[0];
}
export function loadingPlan(length, seed, options) {
  const wordMs = options.wordMs ?? LOADING_WORD_MS;
  const scripts = resolveScripts(options.alphabet ?? 'auto', options.text ?? '');
  const glyphs = splitGlyphs(options.text ?? '');
  // A board written in capitals — a station board — loads in capitals too.
  const letters = glyphs.filter(g => g.toLowerCase() !== g.toUpperCase());
  const capitals = letters.length > 0 && letters.every(isUpperCase);
  const words = randomWords(length, wordScript(scripts, options.alphabet, glyphs), mulberry32(hash(seed, 0, WORDS_CELL)), options.exactLength ?? false).map(word => capitals ? word.map(letter => letter.toUpperCase()) : word);
  const cycle = [...words, words[0]];
  const width = Math.max(...words.map(w => w.length));
  const durationMs = LOADING_WORDS * wordMs;
  const cells = Array.from({
    length: width
  }, (_, i) => {
    const path = cycle.map(w => w[i] ?? '');
    const to = path[LOADING_WORDS];
    return {
      i,
      from: path[0],
      to,
      path,
      delayMs: 0,
      durationMs,
      easing: 'linear',
      dir: 1,
      land: LOADING_WORDS,
      ...(options.transition === 'scramble' && to !== '' ? {
        letters: scrambleLetters(to, scripts)
      } : {})
    };
  });
  const plan = {
    v: 1,
    transition: options.transition ?? 'reel',
    totalMs: durationMs,
    cells,
    loop: true
  };
  const board = {
    revision: 0,
    cells: cells.map(cell => ({
      cell,
      startMs: options.now,
      loopMs: durationMs
    }))
  };
  return {
    plan,
    board
  };
}
//# sourceMappingURL=loading.js.map