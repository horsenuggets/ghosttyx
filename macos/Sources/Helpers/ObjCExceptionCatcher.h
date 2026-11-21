#import <Foundation/Foundation.h>

/// This file contains wrappers around various ObjC functions so we can catch
/// exceptions, since you can't natively catch ObjC exceptions from Swift
/// (at least at the time of writing this comment).

/// NSWindow.addTabbedWindow wrapper
FOUNDATION_EXPORT BOOL GhosttyAddTabbedWindowSafely(
    id _Nonnull parent,
    id _Nonnull child,
    NSInteger ordered,
    NSError * _Nullable * _Nullable error
);

/// Lists requested inputs supported by a native glass background filter.
FOUNDATION_EXPORT NSArray<NSString *> * _Nullable GhosttyGlassFilterInputKeys(
    id _Nonnull filter,
    NSArray<NSString *> * _Nonnull keys,
    NSError * _Nullable * _Nullable error
);

/// Copies a native glass filter before changing its verified numeric inputs.
FOUNDATION_EXPORT id _Nullable GhosttyCopyGlassFilterWithInputs(
    id _Nonnull filter,
    NSDictionary<NSString *, NSNumber *> * _Nonnull inputs,
    NSError * _Nullable * _Nullable error
);
