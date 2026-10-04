"use strict";

/**
 * What one cell shows: a user-perceived character, not a code point. A flag is two regional
 * indicators, a family emoji is several emoji joined by ZWJ, a keycap is a digit with U+FE0F and
 * U+20E3, an "é" may be "e" with a combining accent — each is one cell, never torn into pieces.
 *
 * A syllable of an Indic or Thai script is one cell too: a consonant with its vowel signs (कि,
 * ดี), and consonants joined by a virama (क्ष, स्ते) — Unicode's conjunct rule GB9c.
 *
 * This is a deliberate subset of Unicode's extended grapheme clusters (UAX #29): the joins real
 * text uses. Hermes has no Intl.Segmenter, and the native players do not split at all: they take
 * this split as the `glyphs` prop, so every layer agrees on what a cell is. Whatever this misses
 * shows as two cells; it never fails.
 */
export function splitGlyphs(text) {
  const out = [];
  let joinNext = false;
  let flagHalf = false;
  let linker = -1;
  for (const ch of Array.from(text)) {
    const cp = ch.codePointAt(0) ?? 0;
    const last = out.length - 1;
    const conjunct = linker >= 0 && sameBlock(linker, cp) && !isMark(ch);
    if (last >= 0 && (joinNext || conjunct || extendsPrevious(cp, ch) || flagHalf && isRegionalIndicator(cp))) {
      out[last] += ch;
      joinNext = cp === ZWJ;
      flagHalf = false;
      linker = LINKERS.has(cp) ? cp : cp === ZWJ ? linker : -1;
      continue;
    }
    out.push(ch);
    joinNext = false;
    flagHalf = isRegionalIndicator(cp);
    linker = -1;
  }
  return out;
}
const ZWJ = 0x200d;

// The viramas that join the consonant after them into one conjunct (Unicode InCB=Linker):
// Devanagari, Bengali, Gujarati, Oriya, Telugu, Malayalam.
const LINKERS = new Set([0x094d, 0x09cd, 0x0acd, 0x0b4d, 0x0c4d, 0x0d4d]);

/** A linker joins only a consonant of its own script, and each Indic script has its own block. */
function sameBlock(a, b) {
  return Math.floor(a / 128) === Math.floor(b / 128);
}

// Every combining mark, where the engine knows Unicode properties; the fixed ranges below cover
// Latin, Cyrillic, Greek and emoji on an engine that does not.
const MARK = (() => {
  try {
    return new RegExp('^\\p{M}$', 'u');
  } catch {
    return null;
  }
})();
function isMark(ch) {
  return MARK !== null && MARK.test(ch);
}
function isRegionalIndicator(cp) {
  return cp >= 0x1f1e6 && cp <= 0x1f1ff;
}

/** A code point that belongs to the character before it. */
function extendsPrevious(cp, ch) {
  return cp === ZWJ || isMark(ch) || cp >= 0x0300 && cp <= 0x036f ||
  // combining diacritical marks
  cp >= 0x1ab0 && cp <= 0x1aff || cp >= 0x1dc0 && cp <= 0x1dff || cp >= 0x20d0 && cp <= 0x20ff ||
  // combining marks for symbols, the keycap U+20E3
  cp >= 0xfe00 && cp <= 0xfe0f ||
  // variation selectors: text or emoji presentation
  cp >= 0xfe20 && cp <= 0xfe2f || cp >= 0x1f3fb && cp <= 0x1f3ff ||
  // skin tones
  cp >= 0xe0020 && cp <= 0xe007f ||
  // tags: subdivision flags (England, Scotland)
  cp >= 0xe0100 && cp <= 0xe01ef;
}
//# sourceMappingURL=glyphs.js.map