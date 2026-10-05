/**
 * Plan model v1 — the wire format between the JS planner and the native players.
 * Field names are short and frozen: iOS and Android decoders read them by name.
 *
 * Every cell of the board is present in `cells`, including cells whose glyph does not change
 * (path `[ch]`, durationMs 0, land 0). A native player therefore never needs memory of a
 * previous plan to draw the board: it lays out `cells.length` cells and, for each, shows
 * `path[land]` once the cell has settled. Cells beyond `cells.length` do not exist; a cell
 * whose `to` is '' is removed by the player once it has landed.
 */
export type SplitflapTransition = 'flip' | 'reel' | 'roll' | 'scramble';
/**
 * 'out' = cubic out, 'inOut' = cubic in-out, 'linear' = identity.
 * 'linear' exists for the two cases where a curve would show: a flip card that turns at
 * constant speed, and a looping loading plan that must not pulse at each cycle boundary.
 */
export type Easing = 'out' | 'inOut' | 'linear';
export type Plan = {
    v: 1;
    transition: SplitflapTransition;
    totalMs: number;
    cells: CellPlan[];
    /** Replay from the start when totalMs elapses (loading plans). */
    loop?: boolean;
};
export type CellPlan = {
    i: number;
    /** '' = empty: the cell appears (from '') or disappears (to ''). */
    from: string;
    to: string;
    /** path[0] = from … path[land] = to. */
    path: string[];
    delayMs: number;
    durationMs: number;
    easing: Easing;
    /** 1 = the old glyph leaves upward and the new one comes from below. */
    dir: 1 | -1;
    /** Scramble flicker period; the player shows random glyphs of the target script until it locks. */
    stepMs?: number;
    /** Scramble: the letters to flicker through, in the case of `to` (alphabets.ts scrambleLetters). */
    letters?: string;
    /** Index in path where the cell settles. */
    land: number;
    /**
     * Set when this plan interrupted a moving cell. `k`/`f` describe the pair (path[k], path[k+1])
     * of the PREVIOUS plan and the fraction between them at the moment this plan starts; the new
     * `path[0]` is the more visible glyph of that pair, so a player that opens at that offset
     * continues without a jump.
     */
    resume?: {
        k: number;
        f: number;
    };
};
export type StaggerOrder = 'ltr' | 'rtl' | 'random';
/**
 * `random` (default): every other cell comes from above and the rest from below — even cells from
 * above, odd from below, or the other way round, picked at random on each change. `auto`: each cell
 * rolls the way its letter lies in the alphabet. `up` and `down`: every cell one way.
 */
export type Direction = 'random' | 'auto' | 'up' | 'down';
/** The scripts the planner has alphabets for; any other glyph changes in one step. */
export type SplitflapScript = 'latin' | 'cyrillic' | 'greek' | 'armenian' | 'georgian' | 'devanagari' | 'bengali' | 'gurmukhi' | 'gujarati' | 'oriya' | 'tamil' | 'telugu' | 'kannada' | 'malayalam' | 'sinhala' | 'thai' | 'lao' | 'tibetan' | 'myanmar' | 'khmer' | 'hiragana' | 'katakana';
/**
 * The letters a cell travels through. `auto` (default): each letter's own script, read from the
 * text, and the loading words in the text's script. A script name: the same, with the loading
 * words — which have no text to read it from — in that script. `{ letters }`: only these, in this
 * order.
 */
export type AlphabetOption = 'auto' | SplitflapScript | {
    letters: string;
};
export type TransitionInput = {
    text: string;
    transition?: SplitflapTransition;
    /** Base duration in ms (650); flip scales it. */
    duration?: number;
    /** Delay between consecutive changed cells in ms (40). */
    stagger?: number;
    staggerOrder?: StaggerOrder;
    /** Which way each cell rolls; `random` by default. */
    direction?: Direction;
    alphabet?: AlphabetOption;
    seed?: number;
    /** Time the plan starts, in the caller's clock (the same clock later passed for retargets). */
    now: number;
    /** Every cell settles at once: path [to], duration 0. */
    instant?: boolean;
};
/** One cell as the player is currently playing it. */
export type BoardCell = {
    cell: CellPlan;
    /** Plan start in the caller's clock; the cell itself starts at startMs + cell.delayMs. */
    startMs: number;
    /** Period of a looping plan; absent for a one-shot plan. */
    loopMs?: number;
};
/** What the planner remembers between text changes. Immutable: every planning call returns a new one. */
export type Board = {
    revision: number;
    cells: readonly BoardCell[];
};
//# sourceMappingURL=types.d.ts.map