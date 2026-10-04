#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SplitflapEasing) {
  SplitflapEasingOut,
  SplitflapEasingInOut,
  SplitflapEasingLinear,
};

/** One cell of a plan v1 (src/planner/types.ts is the contract; unknown fields are ignored). */
@interface SplitflapCellPlan : NSObject
@property (nonatomic, readonly) NSInteger index;
@property (nonatomic, readonly) NSString *from;
@property (nonatomic, readonly) NSString *to;
@property (nonatomic, readonly) NSArray<NSString *> *path;
@property (nonatomic, readonly) double delayMs;
@property (nonatomic, readonly) double durationMs;
@property (nonatomic, readonly) SplitflapEasing easing;
/** 1 = the old glyph leaves upward and the new one comes from below. */
@property (nonatomic, readonly) NSInteger dir;
@property (nonatomic, readonly) NSInteger land;
/** Scramble flicker period in ms (SCRAMBLE_STEP_MS when the plan omits it). */
@property (nonatomic, readonly) double stepMs;
/**
 * Scramble: the letters to flicker through, in the case of `to` (planner scrambleLetters). Empty
 * for a glyph no alphabet holds; the player then shows the target itself. The planner is the only
 * place alphabets live — the player keeps no copy.
 */
@property (nonatomic, readonly) NSArray<NSString *> *letters;
@property (nonatomic, readonly) BOOL hasResume;
@property (nonatomic, readonly) NSInteger resumeK;
@property (nonatomic, readonly) double resumeF;
@end

@interface SplitflapPlan : NSObject
@property (nonatomic, readonly) NSInteger version;
@property (nonatomic, readonly) NSString *transition;
@property (nonatomic, readonly) double totalMs;
@property (nonatomic, readonly) BOOL loop;
@property (nonatomic, readonly) NSArray<SplitflapCellPlan *> *cells;

/** nil when the JSON is not an object; a version above 1 decodes with an empty `cells`. */
+ (nullable instancetype)planWithJSON:(NSString *)json;

/**
 * The plan cut to its first `count` cells, the last of them landing on `glyph` instead of its own
 * letter: tail truncation applied to an animation, so it ends on what <Text> would show.
 */
- (SplitflapPlan *)planTruncatedTo:(NSUInteger)count endingWith:(NSString *)glyph;

@end

/** Progress 0…1 of a cell easing at a normalized time. */
double SplitflapEase(SplitflapEasing easing, double x);
/** Normalized time at which a cell easing reaches progress p (the inverse of SplitflapEase). */
double SplitflapEaseInverse(SplitflapEasing easing, double p);

NS_ASSUME_NONNULL_END
