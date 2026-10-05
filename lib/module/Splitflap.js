"use strict";

import { useMemo, useRef } from 'react';
import { Platform, StyleSheet, Text, UIManager } from 'react-native';
import { createBoard, loadingPlan, planTransition, splitGlyphs, widthGlyphs } from "./planner/index.js";
import NativeSplitflapView from './SplitflapViewNativeComponent';

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

/** What `flip` and `scramble` accept: they show two glyphs in one cell at once and never reflow. */

/** The modes the native view measures in: the public two, and flip's and scramble's dense default. */
import { jsx as _jsx } from "react/jsx-runtime";
/** Each transition's best look; a `cellWidth` passed overrides it. */
const DEFAULT_CELL_WIDTH = {
  flip: 'tiered',
  reel: 'natural',
  roll: 'natural',
  scramble: 'tiered'
};

/**
 * `surfaceColor` is required wherever the transition can be `flip`. A flip turns each letter's
 * halves like a departure board's flaps, and the flaps are painted solid so the half they cover
 * never shows through — painted with this colour. Pass the colour right under the text (the card
 * or the screen the board sits on): then the flaps are invisible and only the letters turn. A
 * guessed colour shows as a block wherever the card is another colour. A fixed other transition
 * needs none; one chosen at run time needs it, since it may be `flip`.
 */
// Each transition takes only the settings it can show well. `direction` is the way a reel or a
// roll travels; a flip always falls and a scramble does not travel, so they take none. A transition
// chosen at run time takes what every transition can show: steady widths, no direction (each
// gets its default), and surfaceColor in case it is flip.

// The types keep `natural` away from flip and scramble; plain JavaScript and casts do not, so the
// board falls back to the transition's own width rather than show the overlap. `stable` and
// `tiered`, the two widths before 0.6, land on that default too, so an app that still passes them
// keeps working.
function resolveCellWidth(transition, requested) {
  const fallback = DEFAULT_CELL_WIDTH[transition ?? 'reel'];
  if (requested === 'uniform') return 'uniform';
  if (requested === 'natural' && fallback === 'natural') return 'natural';
  return fallback;
}
const NATIVE_COMPONENT_NAME = 'SplitflapView';
// Only for a loading board with nothing to size it by (an empty text and no loadingLength). It
// used to be a floor for every board — a two-digit count spun six cells wide — with no reason
// behind the number but "a word-ish width".
const DEFAULT_LOADING_LENGTH = 6;
export function isSplitflapNativeAvailable() {
  if (Platform.OS !== 'ios' && Platform.OS !== 'android') {
    return false;
  }
  try {
    return UIManager.hasViewManagerConfig(NATIVE_COMPONENT_NAME);
  } catch {
    return false;
  }
}
function now() {
  const clock = globalThis.performance;
  return clock ? clock.now() : Date.now();
}
function splitFontProps(style) {
  const {
    fontFamily,
    fontSize,
    fontWeight,
    fontStyle,
    fontVariant,
    color,
    letterSpacing,
    lineHeight,
    ...rest
  } = StyleSheet.flatten(style) ?? {};
  return {
    font: {
      fontFamily,
      fontSize,
      fontWeight: fontWeight == null ? undefined : String(fontWeight),
      fontStyle,
      // Tabular digits by default: every digit one width, so a changing number holds still — what
      // a clock or a price does. A board that wants proportional digits says so
      // (fontVariant: ['proportional-nums']); any fontVariant given replaces the default.
      fontVariant: fontVariant == null ? ['tabular-nums'] : [...fontVariant],
      color,
      letterSpacing,
      lineHeight,
      allowFontScaling: true
    },
    rest
  };
}
export function Splitflap({
  text,
  loading = false,
  loadingLength,
  contentKey,
  animateOnMount = true,
  style,
  transition,
  duration,
  stagger,
  staggerOrder,
  direction,
  alphabet,
  seed,
  reduceMotion = 'system',
  surfaceColor,
  cellWidth: requestedCellWidth,
  onTransitionStart,
  onTransitionEnd,
  accessibilityLabel,
  ...viewProps
}) {
  const cellWidth = resolveCellWidth(transition, requestedCellWidth);
  const boardRef = useRef(createBoard());
  // Sixty boards re-render on every value; the alphabets of a text are the same until it changes.
  const measuredGlyphs = useMemo(() => cellWidth === 'uniform' || cellWidth === 'tiered' ? widthGlyphs(text) : undefined, [cellWidth, text]);
  const plannedRef = useRef(null);
  const key = JSON.stringify([text, loading, loadingLength, contentKey, transition, duration, stagger, staggerOrder, direction, alphabet, seed]);
  if (plannedRef.current?.key !== key) {
    const startMs = now();
    const firstShow = plannedRef.current === null || plannedRef.current.contentKey !== contentKey;
    const result = loading ? loadingPlan(loadingLength ?? (splitGlyphs(text).length || DEFAULT_LOADING_LENGTH), seed ?? 1, {
      now: startMs,
      alphabet,
      text,
      transition,
      exactLength: typeof loadingLength === 'number'
    }) : planTransition(boardRef.current, {
      text,
      now: startMs,
      transition,
      duration,
      stagger,
      staggerOrder,
      direction,
      alphabet,
      seed,
      instant: !animateOnMount && firstShow
    });
    boardRef.current = result.board;
    plannedRef.current = {
      key,
      contentKey,
      plan: JSON.stringify(result.plan),
      glyphs: splitGlyphs(text)
    };
  }
  if (!isSplitflapNativeAvailable()) {
    // The responder callbacks differ only in their TS signatures between View and Text.
    const textProps = viewProps;
    return /*#__PURE__*/_jsx(Text, {
      ...textProps,
      style: style,
      accessibilityLabel: accessibilityLabel ?? text,
      children: text
    });
  }
  const {
    font,
    rest
  } = splitFontProps(style);
  return /*#__PURE__*/_jsx(NativeSplitflapView, {
    ...viewProps,
    ...font,
    style: rest,
    text: text,
    glyphs: plannedRef.current.glyphs,
    plan: plannedRef.current.plan,
    reduceMotion: reduceMotion,
    surfaceColor: surfaceColor,
    cellWidth: cellWidth,
    widthGlyphs: measuredGlyphs,
    accessible: true,
    accessibilityRole: "text",
    accessibilityLabel: accessibilityLabel ?? text,
    onTransitionStart: onTransitionStart ? event => onTransitionStart(event.nativeEvent) : undefined,
    onTransitionEnd: onTransitionEnd ? event => onTransitionEnd(event.nativeEvent) : undefined
  });
}
//# sourceMappingURL=Splitflap.js.map