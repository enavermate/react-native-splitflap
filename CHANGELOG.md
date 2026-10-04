# Changelog

## [0.5.2](https://github.com/enavermate/react-native-splitflap/compare/v0.5.0...v0.5.2) — 2026-10-04

- Maintenance only: nothing a consumer of the package sees changed

## [0.5.0] — 2026-10-04

### Added

- `<Splitflap>`: departure-board text played natively — Core Animation on iOS, a frame-driven
  Canvas on Android. Requires the New Architecture
- Four transitions: `flip`, `reel` (default), `roll` and `scramble`
- Cell width modes: `natural`, `stable`, `tiered` and `uniform`; tabular digits by default. Each
  transition defaults to its best: `natural` for `reel` and `roll`, `tiered` for `flip` and
  `scramble`, which do not accept `natural`
- Direction for `reel` and `roll`: `random` (default), `auto`, `up` and `down`
- `surfaceColor`, required by the types wherever the transition can be `flip`
- `animateOnMount`, `contentKey`, `loading`, `loadingLength` (a number of cells or a `{ min, max }`
  range), `reduceMotion`, `seed`
- `onTransitionStart` and `onTransitionEnd`
- Alphabets by script, not by language: Latin, Cyrillic, Greek, Armenian, Georgian, the Indic and
  Southeast Asian scripts, the kana and many numeral systems, or a custom alphabet. A word travels
  through its script's core and only the extra letters it contains. Any other character changes in
  one step, so no script can break a board
- One cell per character as a reader sees it: flags, skin tones, ZWJ families, keycaps, combining
  accents and Indic or Thai syllables stay whole
