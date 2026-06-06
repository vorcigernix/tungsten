/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Opt-in browser performance logging shared by Swift and Objective-C++ code.
*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

FOUNDATION_EXPORT NSString *const TungstenPerformanceLoggingDefaultsKey;

BOOL TungstenPerformanceLogIsEnabled(void);
CFTimeInterval TungstenPerformanceLogNow(void);
void TungstenPerformanceLogEvent(NSString *event, NSDictionary<NSString *, id> *_Nullable metadata);
void TungstenPerformanceLogDuration(NSString *event,
                                    CFTimeInterval startTime,
                                    NSDictionary<NSString *, id> *_Nullable metadata);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
