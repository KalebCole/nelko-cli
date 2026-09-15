#import "NativeRFCOMM.h"
#import <IOBluetooth/IOBluetooth.h>

NSErrorDomain const NKRFCOMMErrorDomain = @"dev.nelko.rfcomm";

@interface NKRFCOMMDelegate : NSObject <IOBluetoothRFCOMMChannelDelegate>
@property(nonatomic) NSMutableData *received;
@property(nonatomic) NSDate *lastDataAt;
@end
@implementation NKRFCOMMDelegate
- (instancetype)init { if ((self = [super init])) { _received = [NSMutableData data]; } return self; }
- (void)rfcommChannelData:(IOBluetoothRFCOMMChannel *)channel data:(void *)dataPointer length:(size_t)dataLength {
    [_received appendBytes:dataPointer length:dataLength];
    _lastDataAt = [NSDate date];
}
@end

@implementation NKRFCOMMTransport {
    NSString *_address;
    BluetoothRFCOMMChannelID _channelID;
}
- (instancetype)initWithAddress:(NSString *)address channelID:(uint8_t)channelID {
    if ((self = [super init])) { _address = [address copy]; _channelID = channelID; }
    return self;
}
- (NSError *)error:(NKRFCOMMErrorCode)code operation:(NSString *)operation result:(IOReturn)result {
    return [NSError errorWithDomain:NKRFCOMMErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: operation, @"ioReturn": @(result)}];
}
- (nullable NSData *)request:(NSData *)command timeout:(NSTimeInterval)timeout error:(NSError **)error {
    IOBluetoothDevice *device = [IOBluetoothDevice deviceWithAddressString:_address];
    if (!device) { if (error) *error = [self error:NKRFCOMMErrorOpenFailed operation:@"P21 Bluetooth device was not found." result:kIOReturnNotFound]; return nil; }
    NKRFCOMMDelegate *delegate = [NKRFCOMMDelegate new];
    IOBluetoothRFCOMMChannel *channel = nil;
    IOReturn result = [device openRFCOMMChannelSync:&channel withChannelID:_channelID delegate:delegate];
    if (result != kIOReturnSuccess || !channel || !channel.isOpen) { if (error) *error = [self error:NKRFCOMMErrorOpenFailed operation:@"Could not open direct RFCOMM channel 1." result:result]; return nil; }
    NSError *requestError = nil;
    NSData *response = nil;
    @try {
        UInt16 mtu = [channel getMTU];
        if (mtu == 0) { requestError = [self error:NKRFCOMMErrorInvalidMTU operation:@"RFCOMM channel reported an invalid MTU." result:kIOReturnBadArgument]; }
        const uint8_t *bytes = command.bytes;
        for (NSUInteger sent = 0; !requestError && sent < command.length; ) {
            UInt16 length = (UInt16)MIN((NSUInteger)mtu, command.length - sent);
            result = [channel writeSync:(void *)(bytes + sent) length:length];
            if (result != kIOReturnSuccess) requestError = [self error:NKRFCOMMErrorWriteFailed operation:@"RFCOMM write failed." result:result];
            else sent += length;
        }
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
        while (!requestError && [deadline timeIntervalSinceNow] > 0) {
            NSDate *until = [NSDate dateWithTimeIntervalSinceNow:0.02];
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:until];
            if (delegate.received.length && delegate.lastDataAt && -[delegate.lastDataAt timeIntervalSinceNow] >= 0.05) break;
        }
        if (!requestError && !delegate.received.length) requestError = [self error:NKRFCOMMErrorResponseTimedOut operation:@"Timed out waiting for printer response." result:kIOReturnTimeout];
        if (!requestError) response = [delegate.received copy];
    } @finally {
        IOReturn closeResult = [channel closeChannel];
        if (!requestError && closeResult != kIOReturnSuccess) requestError = [self error:NKRFCOMMErrorCloseFailed operation:@"RFCOMM channel close failed." result:closeResult];
    }
    if (requestError) { if (error) *error = requestError; return nil; }
    return response;
}
@end
