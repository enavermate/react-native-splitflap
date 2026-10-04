import { type ColorValue, type StyleProp, type TextStyle, type ViewProps } from 'react-native';
import { type AlphabetOption, type Direction, type LoadingLength, type SplitflapTransition, type StaggerOrder } from './planner/index.js';
export type SplitflapTransitionStartEvent = {
    text: string;
};
export type SplitflapTransitionEndEvent = {
    text: string;
    interrupted: boolean;
};
/**
 * How a cell's width behaves while it animates. `natural`: it moves from the old glyph's width to
 * the new one's, as a `<Text>` would reflow; with the default tabular digits a number keeps its
 * width anyway. `stable`: it takes the widest glyph on the cell's way at once, holds it while the
 * glyphs turn, and narrows to the new glyph once they have landed — as a physical board's fixed
 * cells do — so glyphs neither slide sideways nor reach into a neighbour. `uniform`: every cell of
 * the board is as wide as the widest letter of the alphabets the text is written in, in its case,
 * and each glyph sits centred in its cell — a station board's look. Words of the same alphabets
 * and case never move sideways. `tiered`: three widths instead of one — the alphabets' letters
 * measured and sorted into narrow, regular and wide («i l t» · «a o n» · «m w» in Latin, «ж ш щ»
 * wide in Cyrillic) — each glyph centred in its tier's width, so a word reads almost as dense as
 * text and moves only where a letter changes tier.
 */
export type SplitflapCellWidth = 'natural' | 'stable' | 'tiered' | 'uniform';
/**
 * The widths that hold still while a glyph turns. `flip` and `scramble` show two different glyphs
 * in one cell at once (a flap over a half, a letter every few frames); under `natural` the cell
 * reflows for each of them, so a flip's halves reach into the neighbours and a scramble's word
 * shrinks and jumps mid-turn. Those two take only these.
 */
export type SplitflapSteadyCellWidth = Exclude<SplitflapCellWidth, 'natural'>;
/**
 * `surfaceColor` is required wherever the transition can be `flip`. A flip turns each letter's
 * halves like a departure board's flaps, and the flaps are painted solid so the half they cover
 * never shows through — painted with this colour. Pass the colour right under the text (the card
 * or the screen the board sits on): then the flaps are invisible and only the letters turn. A
 * guessed colour shows as a block wherever the card is another colour. A fixed other transition
 * needs none; one chosen at run time needs it, since it may be `flip`.
 */
type TransitionProps = {
    /** `reel` by default. */
    transition?: 'reel' | 'roll';
    surfaceColor?: ColorValue;
    /** `natural` by default. */
    cellWidth?: SplitflapCellWidth;
    /** `random` by default. */
    direction?: Direction;
} | {
    transition: 'scramble';
    surfaceColor?: ColorValue;
    /** `tiered` by default. */
    cellWidth?: SplitflapSteadyCellWidth;
    direction?: never;
} | {
    transition: SplitflapTransition;
    /** The background colour right under the text; `flip` paints its flaps with it. */
    surfaceColor: ColorValue;
    /** `tiered` for flip and scramble, `natural` for reel and roll. */
    cellWidth?: SplitflapSteadyCellWidth;
    direction?: never;
};
export type SplitflapProps = Omit<ViewProps, 'style'> & TransitionProps & {
    /** The only prop a board needs. */
    text: string;
    /** Loops random words of the text's script until it turns false; the real text then lands. */
    loading?: boolean;
    /**
     * How long the loading words are, in cells. A number: every word exactly that long — for a
     * figure whose width is known (a count of one to three digits). `{ min, max }`: each word a
     * length in that range — the shortest and longest text the board is waiting for, so the words
     * try on the sizes the real one may come in. Without it the words wander ±1 around the text's
     * length, or around DEFAULT_LOADING_LENGTH when the text is empty and there is nothing to size
     * by.
     */
    loadingLength?: LoadingLength;
    /** Replans when it changes even if `text` did not (a new item with the same label). */
    contentKey?: string | number;
    /**
     * `false`: the first text — and the first text after `contentKey` changes, a recycled list row
     * showing a new item — appears at once; only later changes animate. Default `true`.
     */
    animateOnMount?: boolean;
    style?: StyleProp<TextStyle>;
    duration?: number;
    stagger?: number;
    staggerOrder?: StaggerOrder;
    alphabet?: AlphabetOption;
    seed?: number;
    reduceMotion?: 'system' | 'always' | 'never';
    /** A transition began to play; not called when the change shows at once (Reduce Motion). */
    onTransitionStart?: (event: SplitflapTransitionStartEvent) => void;
    onTransitionEnd?: (event: SplitflapTransitionEndEvent) => void;
};
export declare function isSplitflapNativeAvailable(): boolean;
export declare function Splitflap({ text, loading, loadingLength, contentKey, animateOnMount, style, transition, duration, stagger, staggerOrder, direction, alphabet, seed, reduceMotion, surfaceColor, cellWidth: requestedCellWidth, onTransitionStart, onTransitionEnd, accessibilityLabel, ...viewProps }: SplitflapProps): import("react").JSX.Element;
export {};
//# sourceMappingURL=Splitflap.d.ts.map