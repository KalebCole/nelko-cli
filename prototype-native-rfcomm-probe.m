// Disposable live-transport probe: P21 only, RFCOMM channel 1, BATTERY? only.
#import <Foundation/Foundation.h>
#import <IOBluetooth/IOBluetooth.h>

@interface ProbeDelegate : NSObject <IOBluetoothRFCOMMChannelDelegate>
@property(nonatomic, strong) NSMutableData *received;
@end

@implementation ProbeDelegate
- (instancetype)init { if ((self = [super init])) _received = [NSMutableData data]; return self; }
- (void)rfcommChannelData:(IOBluetoothRFCOMMChannel *)channel data:(void *)dataPointer length:(size_t)dataLength {
    [_received appendBytes:dataPointer length:dataLength];
    printf("EVENT data length=%zu hex=", dataLength);
    const unsigned char *p = dataPointer;
    for (size_t i = 0; i < dataLength; i++) printf("%02x", p[i]);
    printf("\n"); fflush(stdout);
}
- (void)rfcommChannelClosed:(IOBluetoothRFCOMMChannel *)channel { printf("EVENT channel-closed\n"); fflush(stdout); }
@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        BOOL printTest = argc == 2 && strcmp(argv[1], "--print-test") == 0;
        if (argc != 1 && !printTest) { fprintf(stderr, "usage: %s [--print-test]\n", argv[0]); return 64; }
        const char *address = "FC:50:17:13:FF:8A";
        IOBluetoothDevice *device = [IOBluetoothDevice deviceWithAddressString:@(address)];
        if (!device) { fprintf(stderr, "RESULT device-not-found\n"); return 2; }
        printf("DEVICE name=%s paired=%d connected_before=%d\n", device.name.UTF8String, device.isPaired, device.isConnected);
        ProbeDelegate *delegate = [ProbeDelegate new];
        IOBluetoothRFCOMMChannel *channel = nil;
        IOReturn result = [device openRFCOMMChannelSync:&channel withChannelID:1 delegate:delegate];
        printf("OPEN result=0x%08x channel=%p connected_after=%d\n", result, channel, device.isConnected);
        if (result != kIOReturnSuccess || !channel || !channel.isOpen) return 3;
        printf("CHANNEL id=%u mtu=%u open=%d\n", [channel getChannelID], [channel getMTU], channel.isOpen);
        NSData *payload = nil;
        if (printTest) {
            payload = [NSData dataWithContentsOfFile:@"artifacts/live-p21-test-label.p21"];
            if (!payload) { fprintf(stderr, "RESULT missing-test-job\n"); [channel closeChannel]; return 5; }
        } else {
            const unsigned char battery[] = {'B','A','T','T','E','R','Y','?','\r','\n'};
            payload = [NSData dataWithBytes:battery length:sizeof(battery)];
        }
        const unsigned char *bytes = payload.bytes;
        NSUInteger sent = 0;
        result = kIOReturnSuccess;
        while (sent < payload.length && result == kIOReturnSuccess) {
            UInt16 chunk = (UInt16)MIN((NSUInteger)[channel getMTU], payload.length - sent);
            result = [channel writeSync:(void *)(bytes + sent) length:chunk];
            sent += (result == kIOReturnSuccess) ? chunk : 0;
        }
        printf("WRITE mode=%s result=0x%08x bytes=%lu mtu=%u\n", printTest ? "test-label" : "battery-query", result, (unsigned long)sent, [channel getMTU]);
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
        while ([deadline timeIntervalSinceNow] > 0 && delegate.received.length == 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        printf("READ total_bytes=%lu hex=", (unsigned long)delegate.received.length);
        const unsigned char *p = delegate.received.bytes;
        for (NSUInteger i = 0; i < delegate.received.length; i++) printf("%02x", p[i]);
        printf("\n");
        IOReturn closed = [channel closeChannel];
        printf("CLOSE result=0x%08x\n", closed);
        return (result == kIOReturnSuccess) ? 0 : 4;
    }
}
