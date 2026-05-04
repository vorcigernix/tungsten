/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Objective-C facade for CEF process lifetime.
*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TungstenCEFApp : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly, getter=isInitialized) BOOL initialized;

- (void)initializeCEF;
- (void)shutdownCEF;

@end

NS_ASSUME_NONNULL_END
