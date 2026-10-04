"use strict";

import { indexIn, scriptOf, withCase } from "./alphabets.js";
import { pick } from "./random.js";
const NEIGHBOUR_REACH = 9;
function randomLetters(n, s, caseRef, rng) {
  return Array.from({
    length: n
  }, () => withCase(pick(rng, s.letters), caseRef));
}
function oneStep(from, to, dir = 1) {
  return {
    path: [from, to],
    dir
  };
}
function through(from, letters, to, dir = 1) {
  return {
    path: [from, ...letters, to],
    dir
  };
}

/** Same script, target later in the alphabet → 1; different scripts read as forward. */
function orderDir(from, to, scripts) {
  const sf = scriptOf(from, scripts);
  const st = scriptOf(to, scripts);
  if (!sf || sf !== st) return 1;
  return indexIn(sf, to) >= indexIn(sf, from) ? 1 : -1;
}

/** A cell that appears or disappears rolls through a few letters so a word grows or shrinks during the roll, not after it. */
function edgePath(from, to, steps, ctx) {
  const s = scriptOf(from || to, ctx.scripts);
  if (!s) return oneStep(from, to);
  return through(from, randomLetters(steps, s, to || from, ctx.rng), to);
}
function rollPath(from, to, ctx) {
  if (!from || !to) return edgePath(from, to, 2, ctx);
  return oneStep(from, to, orderDir(from, to, ctx.scripts));
}
function alphabetPath(from, to, ctx, flip) {
  if (!to && flip) return oneStep(from, '', -1);
  if (!from || !to) return edgePath(from, to, 3, ctx);
  const sf = scriptOf(from, ctx.scripts);
  const st = scriptOf(to, ctx.scripts);
  if (sf && sf === st) {
    const i = indexIn(sf, from);
    const j = indexIn(sf, to);
    const step = j > i ? 1 : -1;
    const dist = Math.abs(j - i);
    if (dist === 0) return oneStep(from, to);
    if (dist <= NEIGHBOUR_REACH) {
      const between = [];
      for (let k = i + step; k !== j; k += step) between.push(withCase(sf.letters[k], to));
      return through(from, between, to, step);
    }
    return through(from, randomLetters(5, sf, to, ctx.rng), to, step);
  }
  if (!st) return oneStep(from, to);
  return through(from, randomLetters(3, st, to, ctx.rng), to);
}
export function cellPath(transition, from, to, ctx) {
  switch (transition) {
    case 'roll':
      return rollPath(from, to, ctx);
    case 'scramble':
      return oneStep(from, to, orderDir(from, to, ctx.scripts));
    case 'reel':
      return alphabetPath(from, to, ctx, false);
    case 'flip':
      return alphabetPath(from, to, ctx, true);
  }
}
export function durationFor(transition, duration) {
  switch (transition) {
    case 'flip':
      return Math.round(duration * 1.6);
    default:
      return duration;
  }
}
export function easingFor(transition) {
  switch (transition) {
    case 'reel':
      return 'inOut';
    case 'flip':
      return 'linear';
    default:
      return 'out';
  }
}
export const SCRAMBLE_STEP_MS = 55;
//# sourceMappingURL=paths.js.map