#import <Foundation/Foundation.h>
#import <assert.h>
#import <dlfcn.h>
#import "DNTRules.h"

// Loads the tweak, built for macOS from the same Logos output, and checks its hooks and its URL protocol.
// The SDK classes are stand-ins with the selectors the tweak hooks. No load leaves this machine.

@interface RCTHTTPRequestHandler : NSObject
- (NSURLRequest *)sendRequest:(NSURLRequest *)request withDelegate:(id)delegate;
@end
@implementation RCTHTTPRequestHandler
- (NSURLRequest *)sendRequest:(NSURLRequest *)request withDelegate:(id)delegate { return request; }
@end

@interface AppsFlyerLib : NSObject
@property (nonatomic) BOOL isStopped;
@property (nonatomic) BOOL startedWhileStopped;
- (void)start;
- (void)startWithCompletionHandler:(id)handler;
@end
@implementation AppsFlyerLib
// AppsFlyer reads the ivar, not the getter.
- (void)start { _startedWhileStopped = _isStopped; }
- (void)startWithCompletionHandler:(id)handler { _startedWhileStopped = _isStopped; }
@end

@interface SentryOptions : NSObject
@property (nonatomic) BOOL enabled;
@property (nonatomic, copy) NSArray<NSString *> *integrations;
- (BOOL)isTracingEnabled;
@end
@implementation SentryOptions
- (BOOL)isTracingEnabled { return YES; }
@end

@interface SentryReachability : NSObject
@property (nonatomic) BOOL observed;
- (void)addObserver:(id)observer;
@end
@implementation SentryReachability
- (void)addObserver:(id)observer { _observed = YES; }
@end

static BOOL DNTIsBlocked(NSURLSessionTask *task) {
    return [task.currentRequest.URL.host isEqualToString:@"0.0.0.0"];
}

static void DNTLoad(NSURLSession *session, NSString *url, void (^check)(NSData *data, NSURLResponse *response, NSError *error)) {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[session dataTaskWithURL:[NSURL URLWithString:url] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        check(data, response, error);
        dispatch_semaphore_signal(done);
    }] resume];
    long timedOut = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    assert(!timedOut);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        assert(argc == 2);
        assert(dlopen(argv[1], RTLD_NOW));

        NSURLSession *session = NSURLSession.sharedSession;
        NSURL *tracker = [NSURL URLWithString:@"https://o64374.ingest.sentry.io/api/230973/envelope/"];
        NSURLRequest *request = [NSURLRequest requestWithURL:tracker];
        NSURL *file = [NSURL fileURLWithPath:@"/dev/null"];
        void (^handler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {};
        assert(DNTIsBlocked([session dataTaskWithRequest:request]));
        assert(DNTIsBlocked([session dataTaskWithRequest:request completionHandler:handler]));
        assert(DNTIsBlocked([session dataTaskWithURL:tracker completionHandler:handler]));
        assert(DNTIsBlocked([session downloadTaskWithRequest:request]));
        assert(DNTIsBlocked([session uploadTaskWithRequest:request fromData:NSData.data]));
        assert(DNTIsBlocked([session uploadTaskWithRequest:request fromData:NSData.data completionHandler:handler]));
        assert(DNTIsBlocked([session uploadTaskWithRequest:request fromFile:file]));
        assert(DNTIsBlocked([session uploadTaskWithRequest:request fromFile:file completionHandler:handler]));
        assert(DNTIsBlocked([session uploadTaskWithStreamedRequest:request]));

        NSURLRequest *api = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://discord.com/api/v9/users/@me"]];
        NSURLRequest *science = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://discord.com/api/v9/science"]];
        assert(!DNTIsBlocked([session dataTaskWithRequest:api]));
        RCTHTTPRequestHandler *http = [RCTHTTPRequestHandler new];
        assert([http sendRequest:api withDelegate:nil] == api);
        assert([[http sendRequest:science withDelegate:nil].URL.absoluteString isEqualToString:DNTEmptyJSONURL]);

        NSMutableURLRequest *mutable = [api mutableCopy];
        mutable.allHTTPHeaderFields = @{@"Accept": @"*/*", @"baggage": @"1"};
        [mutable setValue:@"2" forHTTPHeaderField:@"sentry-trace"];
        [mutable addValue:@"3" forHTTPHeaderField:@"Baggage"];
        assert([mutable.allHTTPHeaderFields isEqualToDictionary:@{@"Accept": @"*/*"}]);

        // KVC with the ivar's name reads and writes it without the hooked accessors, so a getter and a setter can't cover for each other.
        AppsFlyerLib *appsFlyer = [AppsFlyerLib new];
        assert(appsFlyer.isStopped);
        appsFlyer.isStopped = NO;
        assert([[appsFlyer valueForKey:@"_isStopped"] boolValue]);
        appsFlyer = [AppsFlyerLib new];
        [appsFlyer start];
        assert(appsFlyer.startedWhileStopped);
        appsFlyer = [AppsFlyerLib new];
        [appsFlyer startWithCompletionHandler:nil];
        assert(appsFlyer.startedWhileStopped);

        SentryOptions *options = [SentryOptions new];
        [options setValue:@YES forKey:@"_enabled"];
        assert(!options.enabled);
        options.enabled = YES;
        assert(![[options valueForKey:@"_enabled"] boolValue]);
        options.integrations = @[@"SentryCrashIntegration", @"SentryANRTrackingIntegration"];
        assert(![options isTracingEnabled]);
        assert([options.integrations isEqualToArray:@[@"SentryCrashIntegration"]]);
        SentryReachability *reachability = [SentryReachability new];
        [reachability addObserver:options];
        assert(!reachability.observed);

        // The URL protocol answers loads that no hook rewrites. If it misses one, the science URL is local
        // and the tracker load meets a dead local proxy.
        Class protocol = NSClassFromString(@"DNTURLProtocol");
        assert(protocol);
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.defaultSessionConfiguration;
        assert(configuration.protocolClasses.firstObject == protocol);
        assert(NSURLSessionConfiguration.ephemeralSessionConfiguration.protocolClasses.firstObject == protocol);
        assert([protocol canInitWithRequest:request]);
        assert([protocol canInitWithRequest:science]);
        // It must leave alone an ordinary API request and the two requests the hooks substitute.
        assert(![protocol canInitWithRequest:api]);
        assert(![protocol canInitWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:DNTEmptyJSONURL]]]);
        assert(![protocol canInitWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"http://0.0.0.0/"]]]);

        NSData *emptyJSON = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
        DNTLoad(session, @"http://127.0.0.1:9/api/v9/science", ^(NSData *data, NSURLResponse *response, NSError *error) {
            assert([(NSHTTPURLResponse *)response statusCode] == 200);
            assert([data isEqualToData:emptyJSON]);
        });

        configuration.connectionProxyDictionary = @{@"HTTPSEnable": @1, @"HTTPSProxy": @"127.0.0.1", @"HTTPSPort": @9};
        NSURLSession *proxied = [NSURLSession sessionWithConfiguration:configuration];
        // The request RCTHTTPRequestHandler gets for a telemetry path still loads in a session that has the protocol.
        DNTLoad(proxied, DNTEmptyJSONURL, ^(NSData *data, NSURLResponse *response, NSError *error) {
            assert(!error && [data isEqualToData:emptyJSON]);
        });
        // downloadTaskWithURL:completionHandler: has no hook, so only the protocol can stop this load.
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        [[proxied downloadTaskWithURL:tracker completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
            assert([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCannotConnectToHost);
            dispatch_semaphore_signal(done);
        }] resume];
        long timedOut = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
        assert(!timedOut);
    }
    puts("hooks ok");
    return 0;
}
