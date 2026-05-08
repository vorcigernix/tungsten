/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Objective-C facade for CEF process lifetime.
*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Canonical NSUserDefaults key for the Local AI provider setting. Shared so
/// the Swift settings layer and the CEF command-line setup read the same key
/// without duplicating the version-tagged literal.
FOUNDATION_EXPORT NSString *const TungstenLocalAIProviderDefaultsKey;

@interface TungstenCEFApp : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly, getter=isInitialized) BOOL initialized;
@property (nonatomic, readonly, getter=isTerminating) BOOL terminating;

- (void)initializeCEF;
- (void)beginTermination;
- (void)shutdownCEF;

@end

NS_ASSUME_NONNULL_END
