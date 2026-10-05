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
 * How wide each cell is. `natural`: a cell moves from the old glyph's width to the new one's, as a
 * `<Text>` would reflow — `reel` and `roll` only; with the default tabular digits a number keeps
 * its width anyway. `uniform`: every cell of the board is as wide as the widest letter of the
 * alphabets the text is written in, in its case, each glyph centred — a station board's look, where
 * words of the same alphabets and case never move sideways.
 *
 * Without one, `reel` and `roll` are `natural`, and `flip` and `scramble` keep each letter near its
 * own width — the alphabets' letters measured and sorted into narrow, regular and wide cells — since
 * they show two glyphs in one cell at once and must not reflow.
 */
export type SplitflapCellWidth = 'natural' | 'uniform';
/** What `flip` and `scramble` accept: they show two glyphs in one cell at once and never reflow. */
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
    /** Each letter near its own width by default. */
    cellWidth?: SplitflapSteadyCellWidth;
    direction?: never;
} | {
    transition: SplitflapTransition;
    /** The background colour right under the text; `flip` paints its flaps with it. */
    surfaceColor: ColorValue;
    /** `natural` for reel and roll; each letter near its own width for flip and scramble. */
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