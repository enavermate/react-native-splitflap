import type { BoardCell, Easing } from './types.js';
/** Must match the curves the native players use, or a retarget lands on the wrong glyph. */
export declare const ease: Readonly<Record<Easing, (t: number) => number>>;
export type Position = {
    /** Pair (path[k], path[k+1]) currently on screen. */
    k: number;
    /** Fraction travelled from path[k] to path[k+1]. */
    f: number;
    moving: boolean;
};
export declare function positionAt(bc: BoardCell, now: number): Position;
/** The glyph a viewer sees most of at `now`. */
export declare function glyphAt(bc: BoardCell, now: number): string;
//# sourceMappingURL=timeline.d.ts.map