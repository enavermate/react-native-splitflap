#import <React/RCTViewComponentView.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Plays a planner `Plan` as Core Animation committed once per plan: after the commit the main
 * thread does no per-frame work. Glyphs come from a `SplitflapGlyphAtlas`; cells sit where the
 * shadow node's measurement (state) put them.
 */
@interface SplitflapView : RCTViewComponentView
@end

NS_ASSUME_NONNULL_END
