#import <Foundation/Foundation.h>
#import <assert.h>
#import <dlfcn.h>
#import "DNTRules.h"

// Loads the tweak, built for macOS from the same Logos output, and checks its hooks.
// The SDK classes are stand-ins with the selectors the tweak hooks. No task is resumed.

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

static BOOL DNTIsBlocked(NSURLSessionTask *task) {
    return [task.currentRequest.URL.host isEqualToString:@"0.0.0.0"];
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
    }
    puts("hooks ok");
    return 0;
}
