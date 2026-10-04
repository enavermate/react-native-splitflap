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
export declare function splitGlyphs(text: string): string[];
//# sourceMappingURL=glyphs.d.ts.map