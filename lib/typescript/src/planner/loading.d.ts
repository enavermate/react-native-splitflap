import type { AlphabetOption, Board, Plan, SplitflapTransition } from './types.js';
export declare const LOADING_WORD_MS = 430;
export declare const LOADING_WORDS = 8;
/**
 * How long the loading words are: a number of cells, or a range the lengths are drawn from — the
 * shortest and the longest text the board is waiting for, so the words try on the sizes the real
 * one may come in.
 */
export type LoadingLength = number | {
    min: number;
    max: number;
};
export type LoadingOptions = {
    now: number;
    alphabet?: AlphabetOption;
    /** The text the board will land on, if known: with `auto`, the loading words take its script. */
    text?: string;
    wordMs?: number;
    /** How the words change while loading; the one the real text will land with, so they match. */
    transition?: SplitflapTransition;
    /**
     * A number `length`: every word exactly that many cells. Without it the words wander ±1 around
     * it, which reads as words; a figure whose width is known (a two-digit count) must not grow a
     * cell and shift what stands next to it. A range is always drawn from as given.
     */
    exactLength?: boolean;
};
export declare function loadingPlan(length: LoadingLength, seed: number, options: LoadingOptions): {
    plan: Plan;
    board: Board;
};
//# sourceMappingURL=loading.d.ts.map