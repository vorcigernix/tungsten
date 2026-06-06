/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Opt-in browser performance logging shared by Swift and Objective-C++ code.
*/

#import "TungstenPerformanceLog.h"

NSString *const TungstenPerformanceLoggingDefaultsKey = @"Tungsten.PerformanceLoggingEnabled";

static BOOL TungstenPerformanceEnvironmentValueEnablesLogging(NSString *value) {
    if (value.length == 0) {
        return NO;
    }

    NSString *normalized = value.lowercaseString;
    return !([normalized isEqualToString:@"0"] ||
             [normalized isEqualToString:@"false"] ||
             [normalized isEqualToString:@"no"] ||
             [normalized isEqualToString:@"off"]);
}

BOOL TungstenPerformanceLogIsEnabled(void) {
    static BOOL enabled = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *environmentValue = NSProcessInfo.processInfo.environment[@"TUNGSTEN_PERF_LOG"];
        enabled = TungstenPerformanceEnvironmentValueEnablesLogging(environmentValue) ||
            [NSUserDefaults.standardUserDefaults boolForKey:TungstenPerformanceLoggingDefaultsKey];
    });
    return enabled;
}

CFTimeInterval TungstenPerformanceLogNow(void) {
    return CFAbsoluteTimeGetCurrent();
}

static NSString *TungstenPerformanceStringForValue(id value) {
    if ([value isKindOfClass:NSString.class]) {
        return value;
    }

    if ([value isKindOfClass:NSURL.class]) {
        return ((NSURL *)value).absoluteString;
    }

    if ([value respondsToSelector:@selector(stringValue)]) {
        return [value stringValue];
    }

    return [value description];
}

static NSString *TungstenPerformanceMetadataString(NSDictionary<NSString *, id> *metadata) {
    if (metadata.count == 0) {
        return @"";
    }

    NSArray<NSString *> *keys = [metadata.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<NSString *> *pairs = [NSMutableArray arrayWithCapacity:keys.count];
    for (NSString *key in keys) {
        id value = metadata[key];
        if (value == nil || value == NSNull.null) {
            continue;
        }
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, TungstenPerformanceStringForValue(value)]];
    }

    if (pairs.count == 0) {
        return @"";
    }

    return [NSString stringWithFormat:@" %@", [pairs componentsJoinedByString:@" "]];
}

void TungstenPerformanceLogEvent(NSString *event, NSDictionary<NSString *, id> *metadata) {
    if (!TungstenPerformanceLogIsEnabled()) {
        return;
    }

    static CFTimeInterval firstLogTime = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        firstLogTime = TungstenPerformanceLogNow();
    });

    CFTimeInterval elapsed = TungstenPerformanceLogNow() - firstLogTime;
    NSLog(@"[TungstenPerf] +%.3fs %@%@",
          elapsed,
          event,
          TungstenPerformanceMetadataString(metadata));
}

void TungstenPerformanceLogDuration(NSString *event,
                                    CFTimeInterval startTime,
                                    NSDictionary<NSString *, id> *metadata) {
    if (!TungstenPerformanceLogIsEnabled()) {
        return;
    }

    NSMutableDictionary<NSString *, id> *durationMetadata =
        metadata ? [metadata mutableCopy] : [NSMutableDictionary dictionary];
    durationMetadata[@"duration_ms"] = @((TungstenPerformanceLogNow() - startTime) * 1000);
    TungstenPerformanceLogEvent(event, durationMetadata);
}
