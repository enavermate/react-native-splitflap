#import "SplitflapPlan.h"

#import <cmath>

static double SplitflapNumber(NSDictionary *dict, NSString *key, double fallback)
{
  id value = dict[key];
  return [value isKindOfClass:[NSNumber class]] ? [value doubleValue] : fallback;
}

static NSString *SplitflapString(NSDictionary *dict, NSString *key, NSString *fallback)
{
  id value = dict[key];
  return [value isKindOfClass:[NSString class]] ? value : fallback;
}

double SplitflapEase(SplitflapEasing easing, double x)
{
  x = MIN(1, MAX(0, x));
  switch (easing) {
    case SplitflapEasingOut:
      return 1 - pow(1 - x, 3);
    case SplitflapEasingInOut:
      return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2;
    case SplitflapEasingLinear:
      return x;
  }
}

double SplitflapEaseInverse(SplitflapEasing easing, double p)
{
  p = MIN(1, MAX(0, p));
  switch (easing) {
    case SplitflapEasingOut:
      return 1 - cbrt(1 - p);
    case SplitflapEasingInOut:
      return p < 0.5 ? cbrt(p / 4) : 1 - cbrt(2 * (1 - p)) / 2;
    case SplitflapEasingLinear:
      return p;
  }
}

@interface SplitflapCellPlan ()
@property (nonatomic, readwrite) NSString *to;
@property (nonatomic, readwrite) NSArray<NSString *> *path;
@end

@interface SplitflapPlan ()
@property (nonatomic, readwrite) NSArray<SplitflapCellPlan *> *cells;
@end

@implementation SplitflapCellPlan

- (nullable instancetype)initWithDictionary:(NSDictionary *)dict
{
  if (!(self = [super init])) {
    return nil;
  }
  _index = (NSInteger)SplitflapNumber(dict, @"i", -1);
  _from = SplitflapString(dict, @"from", @"");
  _to = SplitflapString(dict, @"to", @"");
  NSMutableArray<NSString *> *path = [NSMutableArray new];
  id rawPath = dict[@"path"];
  if ([rawPath isKindOfClass:[NSArray class]]) {
    for (id glyph in rawPath) {
      [path addObject:[glyph isKindOfClass:[NSString class]] ? glyph : @""];
    }
  }
  if (path.count == 0) {
    [path addObject:_to];
  }
  _path = path;
  _delayMs = MAX(0, SplitflapNumber(dict, @"delayMs", 0));
  _durationMs = MAX(0, SplitflapNumber(dict, @"durationMs", 0));
  NSString *easing = SplitflapString(dict, @"easing", @"out");
  _easing = [easing isEqualToString:@"inOut"] ? SplitflapEasingInOut
      : [easing isEqualToString:@"linear"]    ? SplitflapEasingLinear
                                              : SplitflapEasingOut;
  _dir = SplitflapNumber(dict, @"dir", 1) < 0 ? -1 : 1;
  _land = (NSInteger)MIN((double)(path.count - 1), MAX(0, SplitflapNumber(dict, @"land", path.count - 1)));
  _stepMs = MAX(1, SplitflapNumber(dict, @"stepMs", 55));
  NSMutableArray<NSString *> *letters = [NSMutableArray new];
  NSString *rawLetters = SplitflapString(dict, @"letters", @"");
  [rawLetters enumerateSubstringsInRange:NSMakeRange(0, rawLetters.length)
                                 options:NSStringEnumerationByComposedCharacterSequences
                              usingBlock:^(NSString *letter, NSRange, NSRange, BOOL *) {
                                [letters addObject:letter];
                              }];
  _letters = letters;
  id resume = dict[@"resume"];
  if ([resume isKindOfClass:[NSDictionary class]]) {
    _hasResume = YES;
    _resumeK = (NSInteger)SplitflapNumber(resume, @"k", 0);
    _resumeF = SplitflapNumber(resume, @"f", 0);
  }
  return self;
}

- (SplitflapCellPlan *)copyLandingOn:(NSString *)glyph
{
  SplitflapCellPlan *copy = [SplitflapCellPlan new];
  copy->_index = _index;
  copy->_from = _from;
  NSMutableArray<NSString *> *path = [_path mutableCopy];
  path[_land] = glyph;
  copy->_path = path;
  copy->_to = glyph;
  copy->_delayMs = _delayMs;
  copy->_durationMs = _durationMs;
  copy->_easing = _easing;
  copy->_dir = _dir;
  copy->_land = _land;
  copy->_stepMs = _stepMs;
  // The landing glyph is replaced ("…" of a truncation): it belongs to no alphabet.
  copy->_letters = @[];
  copy->_hasResume = _hasResume;
  copy->_resumeK = _resumeK;
  copy->_resumeF = _resumeF;
  return copy;
}

@end

@implementation SplitflapPlan

+ (nullable instancetype)planWithJSON:(NSString *)json
{
  NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
  if (data == nil) {
    return nil;
  }
  id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  if (![root isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  return [[SplitflapPlan alloc] initWithDictionary:root];
}

- (instancetype)initWithDictionary:(NSDictionary *)dict
{
  if (!(self = [super init])) {
    return nil;
  }
  _version = (NSInteger)SplitflapNumber(dict, @"v", 1);
  _transition = SplitflapString(dict, @"transition", @"roll");
  _totalMs = MAX(0, SplitflapNumber(dict, @"totalMs", 0));
  _loop = [dict[@"loop"] isKindOfClass:[NSNumber class]] && [dict[@"loop"] boolValue];
  NSMutableArray<SplitflapCellPlan *> *cells = [NSMutableArray new];
  id rawCells = dict[@"cells"];
  if (_version <= 1 && [rawCells isKindOfClass:[NSArray class]]) {
    for (id raw in rawCells) {
      if ([raw isKindOfClass:[NSDictionary class]]) {
        [cells addObject:[[SplitflapCellPlan alloc] initWithDictionary:raw]];
      }
    }
  }
  _cells = cells;
  return self;
}

- (SplitflapPlan *)planTruncatedTo:(NSUInteger)count endingWith:(NSString *)glyph
{
  if (count == 0 || count >= _cells.count) {
    return self;
  }
  SplitflapPlan *copy = [SplitflapPlan new];
  copy->_version = _version;
  copy->_transition = _transition;
  copy->_totalMs = _totalMs;
  copy->_loop = _loop;
  NSMutableArray<SplitflapCellPlan *> *cells = [[_cells subarrayWithRange:NSMakeRange(0, count)] mutableCopy];
  cells[count - 1] = [cells[count - 1] copyLandingOn:glyph];
  copy->_cells = cells;
  return copy;
}

@end
