#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Every glyph a board can show, rasterized once into one image; a cell shows a glyph through
 * `contentsRect`, so a transition never draws text. Tiles share one width (the widest glyph) so a
 * layer's bounds never change while its `contentsRect` steps through a path.
 *
 * `centreWidth` > 0 (a `uniform` board): each glyph is drawn centred in that width.
 *
 * Instances are cached per (font, color, letter spacing, line height, scale, centre width) under an 8 MB budget
 * and dropped on a memory warning.
 */
@interface SplitflapGlyphAtlas : NSObject

@property (nonatomic, readonly) CGImageRef image;
@property (nonatomic, readonly) CGFloat scale;
/** Tile height, in points: the line height every cell is laid out on. */
@property (nonatomic, readonly) CGFloat tileHeight;
/** Tile width, in points, padding included. */
@property (nonatomic, readonly) CGFloat tileWidth;
/** Transparent space left of every glyph so overhangs (italics) are not cut. */
@property (nonatomic, readonly) CGFloat padding;

+ (instancetype)atlasWithFont:(UIFont *)font
                        color:(UIColor *)color
                letterSpacing:(CGFloat)letterSpacing
                   lineHeight:(CGFloat)lineHeight
                        scale:(CGFloat)scale
                  centreWidth:(CGFloat)centreWidth
                       glyphs:(NSSet<NSString *> *)glyphs;

+ (void)clearCache;

- (BOOL)hasGlyph:(NSString *)glyph;
/** Normalized rect of the tile (the empty string maps to a blank tile). */
- (CGRect)contentsRectForGlyph:(NSString *)glyph;
/** Advance of the glyph in points, letter spacing included, as the atlas measured it. */
- (CGFloat)advanceForGlyph:(NSString *)glyph;
/** Reverse lookup used when a new plan interrupts a running one. */
- (nullable NSString *)glyphForContentsRect:(CGRect)rect;

@end

NS_ASSUME_NONNULL_END
