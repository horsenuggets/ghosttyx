#import "ObjCExceptionCatcher.h"

#import <AppKit/AppKit.h>
#import <math.h>

BOOL GhosttyAddTabbedWindowSafely(
    id parent,
    id child,
    NSInteger ordered,
    NSError * _Nullable * _Nullable error
) {
    // AppKit occasionally throws NSException while adding tabbed windows,
    // in particular when creating tabs from the tab overview page since some
    // macOS update recently in 2025/2026 (unclear).
    //
    // We must catch it in Objective-C; letting this cross into Swift is unsafe.
    @try {
        [((NSWindow *)parent) addTabbedWindow:(NSWindow *)child ordered:(NSWindowOrderingMode)ordered];
        return YES;
    } @catch (NSException *exception) {
        if (error != NULL) {
            NSString *reason = exception.reason ?: @"Unknown Objective-C exception";
            *error = [NSError errorWithDomain:@"Ghostty.ObjCException"
                                         code:1
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: reason,
                                         @"exception_name": exception.name,
                                     }];
        }

        return NO;
    }
}

static NSError *GhosttyGlassError(NSString *message) {
    return [NSError errorWithDomain:@"Ghostty.GlassEffect" code:1
                          userInfo:@{NSLocalizedDescriptionKey: message}];
}

NSArray<NSString *> *GhosttyGlassFilterInputKeys(
    id filter,
    NSArray<NSString *> *keys,
    NSError **error
) {
    @try {
        Class filterClass = NSClassFromString(@"CAFilter");
        if (filterClass == Nil || ![filter isKindOfClass:filterClass] ||
            ![filter respondsToSelector:NSSelectorFromString(@"type")] ||
            ![filter respondsToSelector:NSSelectorFromString(@"inputKeys")]) {
            return nil;
        }
        if (![[filter valueForKey:@"type"] isEqual:@"glassBackground"]) return nil;

        id supported = [filter valueForKey:@"inputKeys"];
        if (![supported isKindOfClass:[NSArray class]]) return nil;
        NSMutableArray<NSString *> *result = [NSMutableArray array];
        for (NSString *key in keys) {
            if ([supported containsObject:key]) [result addObject:key];
        }
        return result;
    } @catch (NSException *exception) {
        if (error != NULL) *error = GhosttyGlassError(exception.reason ?: exception.name);
        return nil;
    }
}

id GhosttyCopyGlassFilterWithInputs(id filter, NSDictionary<NSString *, NSNumber *> *inputs,
                                  NSError **error) {
    @try {
        NSError *inputError = nil;
        NSArray *supported = GhosttyGlassFilterInputKeys(filter, inputs.allKeys, &inputError);
        if (supported == nil || supported.count != inputs.count ||
            ![filter conformsToProtocol:@protocol(NSCopying)]) {
            if (error != NULL) {
                *error = inputError ?: GhosttyGlassError(@"The native glass filter does not support these inputs.");
            }
            return nil;
        }
        id replacement = [filter copy];
        if (replacement == filter) {
            if (error != NULL) *error = GhosttyGlassError(@"The native glass filter cannot be copied.");
            return nil;
        }
        for (NSString *key in inputs) {
            NSNumber *value = inputs[key];
            if (!isfinite(value.doubleValue)) {
                if (error != NULL) *error = GhosttyGlassError(@"Glass inputs must be finite numbers.");
                return nil;
            }
            [replacement setValue:value forKey:key];
        }
        return replacement;
    } @catch (NSException *exception) {
        if (error != NULL) *error = GhosttyGlassError(exception.reason ?: exception.name);
        return nil;
    }
}
