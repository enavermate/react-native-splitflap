import type { CodegenTypes, ColorValue, ViewProps } from 'react-native';
/**
 * Internal wire contract between `Splitflap` and the native player; not the public API.
 * `plan` is the JSON of a planner `Plan` (v1) — the native decoder reads it by field name.
 */
export interface NativeProps extends ViewProps {
    text: string;
    /** `text` split into cells (planner `splitGlyphs`): the native side never splits on its own. */
    glyphs: ReadonlyArray<string>;
    plan: string;
    fontFamily?: string;
    fontSize?: CodegenTypes.Float;
    fontWeight?: string;
    fontStyle?: string;
    fontVariant?: ReadonlyArray<string>;
    color?: ColorValue;
    letterSpacing?: CodegenTypes.Float;
    lineHeight?: CodegenTypes.Float;
    allowFontScaling?: boolean;
    maxFontSizeMultiplier?: CodegenTypes.Float;
    surfaceColor?: ColorValue;
    cellWidth?: CodegenTypes.WithDefault<'natural' | 'stable' | 'uniform' | 'tiered', 'natural'>;
    /** `uniform` and `tiered`: the glyphs the cell widths are measured over (planner `widthGlyphs`). */
    widthGlyphs?: string;
    reduceMotion?: CodegenTypes.WithDefault<'system' | 'always' | 'never', 'system'>;
    onTransitionStart?: CodegenTypes.DirectEventHandler<Readonly<{
        text: string;
    }>>;
    onTransitionEnd?: CodegenTypes.DirectEventHandler<Readonly<{
        text: string;
        interrupted: boolean;
    }>>;
}
declare const _default: import("react-native/types_generated/Libraries/Utilities/codegenNativeComponent").NativeComponentType<NativeProps>;
export default _default;
//# sourceMappingURL=SplitflapViewNativeComponent.d.ts.map