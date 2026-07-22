// plurisim — Pluricode's simulator live-stream helper.
//
// dlopens Apple's CoreSimulator private framework, attaches the booted simulator's live
// framebuffer IOSurface, and streams it as JPEG frames. Runs as a separate process to keep the
// private-framework dependency (and any faults in it) out of Pluricode's own binary — if this
// crashes, the app just falls back to simctl screenshot polling.
//
// The framebuffer sits behind a per-display "ROCK" remote proxy; only the active display's port
// vends a non-nil `framebufferSurface`, so we pick the port whose surface is live rather than the
// first display port. That surface is a live in-place GPU buffer, so we render it on our own
// 60Hz timer and only re-encode when its seed changes.
//
// Protocol:
//   argv[1]   booted device UDID (or "booted" for the first booted simulator)
//   stdout    length-prefixed frames: <4-byte big-endian uint32 length><JPEG bytes>
//   stdin     "tap <fx> <fy>\n" — a tap at normalized (0..1) coordinates from the top-left.
//             EOF closes the stream (clean shutdown when the parent goes away).
//   stderr    human-readable logs
//   env       DEVELOPER_DIR selects the Xcode whose CoreSimulator service to attach
//
// Taps need an Indigo touch struct, which only idb's FBSimulatorIndigoHID knows how to pack. We
// dlopen it at runtime (so streaming keeps working without idb installed) and send the struct via
// SimulatorKit's own SimDeviceLegacyHIDClient — idb's HID *connect* asserts on recent Xcodes, but
// its struct *builder* and our send path do not.

#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>
#import <IOSurface/IOSurface.h>
#import <ImageIO/ImageIO.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <unistd.h>
#import <stdatomic.h>

static id msg0(id t, const char *s) { return ((id(*)(id, SEL))objc_msgSend)(t, sel_getUid(s)); }

// Touch injection, set up lazily from idb's builder + SimulatorKit's HID client.
static id gHID;                 // SimDeviceLegacyHIDClient
static id gIndigo;              // FBSimulatorIndigoHID
static dispatch_queue_t gSendQueue;
static atomic_uint gScreenW, gScreenH;

static void setupTaps(id device) {
    if (!dlopen("/Applications/Xcode.app/Contents/Developer/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit", RTLD_NOW))
        return;
    NSString *idb = @"/opt/homebrew/opt/idb-companion/Frameworks";
    dlopen([idb stringByAppendingString:@"/FBControlCore.framework/FBControlCore"].fileSystemRepresentation, RTLD_NOW);
    if (!dlopen([idb stringByAppendingString:@"/FBSimulatorControl.framework/FBSimulatorControl"].fileSystemRepresentation, RTLD_NOW)) {
        fprintf(stderr, "plurisim: idb not available; taps disabled\n");
        return;
    }
    NSError *e = nil;
    gHID = ((id(*)(id, SEL, id, NSError **))objc_msgSend)(
        [NSClassFromString(@"_TtC12SimulatorKit24SimDeviceLegacyHIDClient") alloc],
        sel_getUid("initWithDevice:error:"), device, &e);
    gIndigo = ((id(*)(Class, SEL, NSError **))objc_msgSend)(
        NSClassFromString(@"FBSimulatorIndigoHID"), sel_getUid("simulatorKitHIDWithError:"), &e);
    if (!gHID || !gIndigo) { gHID = gIndigo = nil; fprintf(stderr, "plurisim: taps disabled\n"); return; }
    gSendQueue = dispatch_queue_create("plurisim.hid", DISPATCH_QUEUE_SERIAL);
}

static void sendTouch(int direction, CGSize screen, double x, double y) {
    NSData *msg = ((NSData *(*)(id, SEL, CGSize, int, double, double))objc_msgSend)(
        gIndigo, sel_getUid("touchScreenSize:direction:x:y:"), screen, direction, x, y);
    ((void(*)(id, SEL, void *, BOOL, dispatch_queue_t, void (^)(void)))objc_msgSend)(
        gHID, sel_getUid("sendWithMessage:freeWhenDone:completionQueue:completion:"),
        (void *)msg.bytes, NO, gSendQueue, ^{ (void)msg; });  // keep msg alive until sent
}

static void tap(double fx, double fy) {
    unsigned w = atomic_load(&gScreenW), h = atomic_load(&gScreenH);
    if (!gHID || !gIndigo || !w || !h) return;
    CGSize screen = CGSizeMake(w, h);
    double px = fx * w, py = fy * h;
    sendTouch(1, screen, px, py);  // down
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), gSendQueue, ^{
        sendTouch(2, screen, px, py);  // up
    });
}

static NSString *developerDir(void) {
    char *env = getenv("DEVELOPER_DIR");
    return env ? [NSString stringWithUTF8String:env] : @"/Applications/Xcode.app/Contents/Developer";
}

static id bootedDevice(NSString *wantUDID) {
    NSError *e = nil;
    id ctx = ((id(*)(Class, SEL, NSString *, NSError **))objc_msgSend)(
        NSClassFromString(@"SimServiceContext"),
        sel_getUid("sharedServiceContextForDeveloperDir:error:"), developerDir(), &e);
    id set = ((id(*)(id, SEL, NSError **))objc_msgSend)(ctx, sel_getUid("defaultDeviceSetWithError:"), &e);
    for (id d in msg0(set, "devices")) {
        if (((NSUInteger(*)(id, SEL))objc_msgSend)(d, sel_getUid("state")) != 3) continue;  // 3 == Booted
        NSString *udid = [msg0(d, "UDID") UUIDString];
        if ([wantUDID isEqualToString:@"booted"] || [udid caseInsensitiveCompare:wantUDID] == NSOrderedSame)
            return d;
    }
    return nil;
}

// The active display's framebuffer surface, found across the device's IO ports.
static IOSurfaceRef liveSurface(id ioClient) {
    for (id port in msg0(ioClient, "ioPorts")) {
        id desc = [port respondsToSelector:sel_getUid("descriptor")] ? msg0(port, "descriptor") : nil;
        if (!desc || ![desc respondsToSelector:sel_getUid("framebufferSurface")]) continue;
        IOSurfaceRef surf = (IOSurfaceRef)((void *(*)(id, SEL))objc_msgSend)(desc, sel_getUid("framebufferSurface"));
        if (surf) return surf;
    }
    return NULL;
}

static BOOL writeAll(int fd, const void *buf, size_t len) {
    const uint8_t *p = buf;
    while (len > 0) {
        ssize_t n = write(fd, p, len);
        if (n <= 0) return NO;
        p += n; len -= (size_t)n;
    }
    return YES;
}

static BOOL emitFrame(NSData *jpeg) {
    uint32_t len = CFSwapInt32HostToBig((uint32_t)jpeg.length);
    return writeAll(STDOUT_FILENO, &len, 4) && writeAll(STDOUT_FILENO, jpeg.bytes, jpeg.length);
}

int main(int argc, char **argv) { @autoreleasepool {
    signal(SIGPIPE, SIG_IGN);
    NSString *wantUDID = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"booted";

    if (!dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator", RTLD_NOW)) {
        fprintf(stderr, "plurisim: cannot load CoreSimulator\n"); return 1;
    }

    id device = bootedDevice(wantUDID);
    if (!device) { fprintf(stderr, "plurisim: no booted simulator matching %s\n", wantUDID.UTF8String); return 1; }
    fprintf(stderr, "plurisim: streaming %s\n", [msg0(device, "name") UTF8String]);

    NSError *e = nil;
    id io = ((id(*)(id, SEL, id, id, id))objc_msgSend)(
        [NSClassFromString(@"SimDeviceIOClient") alloc],
        sel_getUid("initWithDevice:errorQueue:errorHandler:"), device, dispatch_get_main_queue(), ^(NSError *x){});
    if (!io) { fprintf(stderr, "plurisim: no SimDeviceIOClient: %s\n", e.description.UTF8String); return 1; }

    setupTaps(device);

    // stdin: "tap <fx> <fy>" commands; EOF (parent closed the pipe) shuts us down cleanly.
    NSFileHandle *stdinFH = [NSFileHandle fileHandleWithStandardInput];
    stdinFH.readabilityHandler = ^(NSFileHandle *h) {
        NSData *data = h.availableData;
        if (data.length == 0) exit(0);
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        for (NSString *line in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
            NSArray<NSString *> *parts = [line componentsSeparatedByString:@" "];
            if (parts.count == 3 && [parts[0] isEqualToString:@"tap"])
                tap(parts[1].doubleValue, parts[2].doubleValue);
        }
    };

    CIContext *ci = [CIContext contextWithOptions:@{ kCIContextUseSoftwareRenderer: @NO }];
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    __block uint32_t lastSeed = UINT32_MAX;
    __block int missCount = 0;

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, NSEC_PER_SEC / 60, NSEC_PER_SEC / 240);
    dispatch_source_set_event_handler(timer, ^{
        if (((NSUInteger(*)(id, SEL))objc_msgSend)(device, sel_getUid("state")) != 3) exit(0);  // shut down
        IOSurfaceRef surf = liveSurface(io);
        if (!surf) { if (++missCount > 120) exit(0); return; }  // ~2s without a surface → give up
        missCount = 0;
        atomic_store(&gScreenW, (unsigned)IOSurfaceGetWidth(surf));
        atomic_store(&gScreenH, (unsigned)IOSurfaceGetHeight(surf));
        uint32_t seed = IOSurfaceGetSeed(surf);
        if (seed == lastSeed) return;
        lastSeed = seed;
        CIImage *img = [CIImage imageWithIOSurface:surf];
        NSData *jpeg = [ci JPEGRepresentationOfImage:img colorSpace:cs
            options:@{ (id)kCGImageDestinationLossyCompressionQuality: @0.7 }];
        if (jpeg && !emitFrame(jpeg)) exit(0);  // pipe closed → parent went away
    });
    dispatch_resume(timer);

    CFRunLoopRun();
    return 0;
}}
