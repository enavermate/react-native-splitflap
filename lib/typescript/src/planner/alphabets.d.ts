import type { AlphabetOption, SplitflapScript } from './types.js';
export type ScriptId = SplitflapScript | 'digit' | 'custom';
export type Script = {
    readonly id: ScriptId;
    /** The letters a cell of this plan travels through, lowercase, in alphabet order. */
    readonly letters: readonly string[];
};
/** Resolved alphabets for one plan; the first one is where loading words are drawn from. */
export type Scripts = readonly Script[];
/**
 * The letter `ch` is filed under: lowercase, and an accented letter folded to its base (á → a,
 * ş → s, ά → α) — unless the accented form is a letter of its own (ñ, й, ё, ї). A glyph no
 * alphabet holds comes back lowercased and is "other".
 */
export declare function base(ch: string): string;
/**
 * The alphabets a plan works with. `seen` is every glyph on the board before and after the change:
 * it decides which extra letters each script travels through and, for `auto`, which script the
 * loading words come from (the text's first letter's, else Latin).
 */
export declare function resolveScripts(option: AlphabetOption, seen: string): Scripts;
/** undefined for '' and for anything outside the alphabets ('other'). */
export declare function scriptOf(ch: string, scripts: Scripts): Script | undefined;
export declare function indexIn(s: Script, ch: string): number;
export declare function isUpperCase(ch: string): boolean;
/** A letter written in the case of `ref` (the glyph the cell is heading to). */
export declare function withCase(letter: string, ref: string): string;
/**
 * The letters a scramble cell flickers through before it lands on `target`: its script's letters
 * in the target's case. Empty for a glyph no alphabet holds — the player then shows the target
 * itself, so an unknown character never flickers through a script it does not belong to. The plan
 * carries the result, so neither native player keeps a copy of the alphabets.
 */
export declare function scrambleLetters(target: string, scripts: Scripts): string;
/**
 * `cellWidth: 'uniform'`, and the default width of `flip` and `scramble`: the glyphs a board's cell
 * widths are measured over — every glyph of `text` and the letters each of them travels through, in
 * its case. `uniform` takes the widest of them for every cell; the `flip` and `scramble` default
 * sorts them into narrow, regular and wide.
 */
export declare function widthGlyphs(text: string): string;
//# sourceMappingURL=alphabets.d.ts.map