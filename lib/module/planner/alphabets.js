"use strict";

import { FOLD_FROM, FOLD_TO } from "./fold.js";
import { splitGlyphs } from "./glyphs.js";

/**
 * Alphabets are kept by script, never by language. Each script has one canonical order holding
 * every letter its languages use — a language's own letters sit next to the letter they grew from
 * (ґ after г, ђ after д, ł after l) — and a core shared by nearly all of them. A board travels
 * through the core plus whatever extra letters its own old and new text contain: a Belarusian
 * word never flashes ї, a Ukrainian one never flashes ы, and Serbian, Kazakh or Polish need no
 * table of their own.
 *
 * Anything no table holds — a rare script, a CJK character, a sign — is "other": it changes in one
 * step and never rolls. That is the rule that keeps an unknown alphabet from breaking a board.
 */

const letters = s => s.split(' ');
const range = (from, to) => Array.from({
  length: to - from + 1
}, (_, i) => String.fromCodePoint(from + i));
function table(id, order, core = order) {
  return {
    id,
    order,
    core: new Set(core)
  };
}
const LATIN = table('latin', letters('a æ b c d đ ð e f g h i ı j k l ł m n ñ ŋ o ø œ p q r s ß t þ u v w x y z'), letters('a b c d e f g h i j k l m n o p q r s t u v w x y z'));
const CYRILLIC = table('cyrillic', letters('а ә б в г ґ ғ д ђ ѓ е є ё ж җ з ѕ и і ї й ј к қ ќ л љ м н ң њ о ө п р с т ћ у ў ү ұ ф х һ ц ч џ ш щ ъ ы ь э ю я'), letters('а б в г д е ж з и к л м н о п р с т у ф х ц ч ш'));
const GREEK = table('greek', letters('α β γ δ ε ζ η θ ι κ λ μ ν ξ ο π ρ σ ς τ υ φ χ ψ ω'), letters('α β γ δ ε ζ η θ ι κ λ μ ν ξ ο π ρ σ τ υ φ χ ψ ω'));
const ARMENIAN = table('armenian', [...range(0x0561, 0x0586), 'և'], range(0x0561, 0x0586));
const GEORGIAN = table('georgian', range(0x10d0, 0x10f0));

// Unicode encodes the Indic and Southeast Asian scripts and the kana in their traditional order
// (vowels, then consonants, as a varnamala reads), so each alphabet is its block's letters. The
// gaps a block keeps for unassigned code points are dropped by \p{L}; on an engine without
// Unicode properties these tables are left out, and their syllables change in one step.
const LETTER = (() => {
  try {
    return new RegExp('^\\p{L}$', 'u');
  } catch {
    return null;
  }
})();
const MARK = (() => {
  try {
    return new RegExp('^\\p{M}$', 'u');
  } catch {
    return null;
  }
})();
const BLOCKS = [['devanagari', 0x0904, 0x0939], ['bengali', 0x0985, 0x09b9], ['gurmukhi', 0x0a05, 0x0a39], ['gujarati', 0x0a85, 0x0ab9], ['oriya', 0x0b05, 0x0b39], ['tamil', 0x0b85, 0x0bb9], ['telugu', 0x0c05, 0x0c39], ['kannada', 0x0c85, 0x0cb9], ['malayalam', 0x0d05, 0x0d3a], ['sinhala', 0x0d85, 0x0dc6], ['thai', 0x0e01, 0x0e2e], ['lao', 0x0e81, 0x0eae], ['tibetan', 0x0f40, 0x0f6c], ['myanmar', 0x1000, 0x102a], ['khmer', 0x1780, 0x17b3], ['hiragana', 0x3041, 0x3096], ['katakana', 0x30a1, 0x30fa]];
const SYLLABIC_TABLES = LETTER === null ? [] : BLOCKS.map(([id, from, to]) => table(id, range(from, to).filter(ch => LETTER.test(ch))));
const SYLLABLE_LETTERS = new Set(SYLLABIC_TABLES.flatMap(t => t.order));

// Each numeral system its own ten: ASCII, Arabic-Indic, Persian, the Indic and Southeast Asian
// ones, fullwidth.
const DIGIT_TABLES = [0x0030, 0x0660, 0x06f0, 0x0966, 0x09e6, 0x0a66, 0x0ae6, 0x0b66, 0x0be6, 0x0c66, 0x0ce6, 0x0d66, 0x0de6, 0x0e50, 0x0ed0, 0x0f20, 0x1040, 0x17e0, 0xff10].map(zero => table('digit', range(zero, zero + 9)));
const LETTER_TABLES = [LATIN, CYRILLIC, GREEK, ARMENIAN, GEORGIAN, ...SYLLABIC_TABLES];
const TABLES = [...LETTER_TABLES, ...DIGIT_TABLES];
const KNOWN = new Set(TABLES.flatMap(t => t.order));
const FOLD = new Map(Array.from(FOLD_FROM).map((ch, i) => [ch, Array.from(FOLD_TO)[i]]));

/** Resolved alphabets for one plan; the first one is where loading words are drawn from. */

/**
 * The letter `ch` is filed under: lowercase, and an accented letter folded to its base (á → a,
 * ş → s, ά → α) — unless the accented form is a letter of its own (ñ, й, ё, ї). A glyph no
 * alphabet holds comes back lowercased and is "other".
 */
export function base(ch) {
  const lower = ch.toLowerCase();
  if (KNOWN.has(lower)) return lower;
  const folded = FOLD.get(lower);
  if (folded !== undefined) return folded;
  const [first, ...rest] = Array.from(lower);
  if (first !== undefined && rest.length > 0) {
    // A letter written as its base plus combining marks ("e" + U+0301, or "İ" lowercased to
    // "i" + U+0307) is filed under the base, as the precomposed letter is.
    if (rest.every(isCombiningMark)) return base(first);
    // A syllable (कि, क्ष, ดี) rolls on its first letter; the cell lands on the whole syllable.
    if (SYLLABLE_LETTERS.has(first)) return first;
  }
  return lower;
}
function isCombiningMark(ch) {
  if (MARK !== null && MARK.test(ch)) return true;
  const cp = ch.codePointAt(0) ?? 0;
  return cp >= 0x0300 && cp <= 0x036f || cp >= 0x1ab0 && cp <= 0x1aff || cp >= 0x1dc0 && cp <= 0x1dff || cp >= 0x20d0 && cp <= 0x20ff || cp >= 0xfe20 && cp <= 0xfe2f;
}
function tableOf(ch) {
  const b = base(ch);
  return TABLES.find(t => t.order.includes(b));
}

/** A table cut to its core plus the extra letters `seen` holds. */
function travel(t, seen) {
  return {
    id: t.id,
    letters: t.order.filter(l => t.core.has(l) || seen.has(l))
  };
}

/**
 * The alphabets a plan works with. `seen` is every glyph on the board before and after the change:
 * it decides which extra letters each script travels through and, for `auto`, which script the
 * loading words come from (the text's first letter's, else Latin).
 */
export function resolveScripts(option, seen) {
  if (typeof option === 'object') {
    return [{
      id: 'custom',
      letters: Array.from(new Set(Array.from(option.letters.toLowerCase())))
    }];
  }
  const glyphs = splitGlyphs(seen);
  const bases = new Set(glyphs.map(base));
  const first = option === 'auto' ? glyphs.map(tableOf).find(t => t !== undefined && t.id !== 'digit') : LETTER_TABLES.find(t => t.id === option);
  const ordered = first ? [first, ...TABLES.filter(t => t !== first)] : TABLES;
  return ordered.map(t => travel(t, bases));
}

/** undefined for '' and for anything outside the alphabets ('other'). */
export function scriptOf(ch, scripts) {
  if (!ch) return undefined;
  const b = base(ch);
  return scripts.find(s => s.letters.includes(b));
}
export function indexIn(s, ch) {
  return s.letters.indexOf(base(ch));
}
export function isUpperCase(ch) {
  return ch !== '' && ch !== ch.toLowerCase();
}

/** A letter written in the case of `ref` (the glyph the cell is heading to). */
export function withCase(letter, ref) {
  return isUpperCase(ref) ? letter.toUpperCase() : letter;
}

/**
 * The letters a scramble cell flickers through before it lands on `target`: its script's letters
 * in the target's case. Empty for a glyph no alphabet holds — the player then shows the target
 * itself, so an unknown character never flickers through a script it does not belong to. The plan
 * carries the result, so neither native player keeps a copy of the alphabets.
 */
export function scrambleLetters(target, scripts) {
  const s = scriptOf(target, scripts);
  if (!s) return '';
  return s.letters.map(l => withCase(l, target)).join('');
}

/**
 * `cellWidth: 'uniform'`, and the default width of `flip` and `scramble`: the glyphs a board's cell
 * widths are measured over — every glyph of `text` and the letters each of them travels through, in
 * its case. `uniform` takes the widest of them for every cell; the `flip` and `scramble` default
 * sorts them into narrow, regular and wide.
 */
export function widthGlyphs(text) {
  const scripts = resolveScripts('auto', text);
  const glyphs = new Set();
  for (const ch of splitGlyphs(text)) {
    glyphs.add(ch);
    // A space or a sign belongs to no alphabet: it is measured alone.
    for (const letter of Array.from(scrambleLetters(ch, scripts))) glyphs.add(letter);
  }
  return Array.from(glyphs).sort().join('');
}
//# sourceMappingURL=alphabets.js.map