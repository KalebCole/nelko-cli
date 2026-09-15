#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSErrorDomain const NKRFCOMMErrorDomain;
typedef NS_ERROR_ENUM(NKRFCOMMErrorDomain, NKRFCOMMErrorCode) {
    NKRFCOMMErrorOpenFailed = 1,
    NKRFCOMMErrorWriteFailed = 2,
    NKRFCOMMErrorResponseTimedOut = 3,
    NKRFCOMMErrorCloseFailed = 4,
    NKRFCOMMErrorInvalidMTU = 5,
};

@interface NKRFCOMMTransport : NSObject
- (instancetype)initWithAddress:(NSString *)address channelID:(uint8_t)channelID;
- (nullable NSData *)request:(NSData *)command timeout:(NSTimeInterval)timeout error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
