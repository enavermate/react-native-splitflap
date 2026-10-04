"use strict";

/** Must match the curves the native players use, or a retarget lands on the wrong glyph. */
export const ease = {
  out: t => 1 - Math.pow(1 - t, 3),
  inOut: t => t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2,
  linear: t => t
};
function cellTime(bc, now) {
  let t = now - bc.startMs;
  if (bc.loopMs !== undefined && bc.loopMs > 0) t = (t % bc.loopMs + bc.loopMs) % bc.loopMs;
  return t - bc.cell.delayMs;
}
export function positionAt(bc, now) {
  const {
    cell
  } = bc;
  const t = cellTime(bc, now);
  if (cell.land <= 0 || cell.durationMs <= 0 || t >= cell.durationMs) {
    return {
      k: cell.land,
      f: 0,
      moving: false
    };
  }
  if (t <= 0) return {
    k: 0,
    f: 0,
    moving: false
  };
  const p = ease[cell.easing](t / cell.durationMs) * cell.land;
  const k = Math.floor(p);
  if (k >= cell.land) return {
    k: cell.land,
    f: 0,
    moving: false
  };
  return {
    k,
    f: p - k,
    moving: true
  };
}

/** The glyph a viewer sees most of at `now`. */
export function glyphAt(bc, now) {
  const {
    k,
    f
  } = positionAt(bc, now);
  const path = bc.cell.path;
  const index = f < 0.5 ? k : Math.min(k + 1, path.length - 1);
  return path[index] ?? '';
}
//# sourceMappingURL=timeline.js.map