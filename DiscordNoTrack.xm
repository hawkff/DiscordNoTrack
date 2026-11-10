#import <Foundation/Foundation.h>
#import "DNTRules.h"
%config(generator=internal);

#ifndef DNT_DEBUG
#define DNT_DEBUG 0
#endif

#define DNTLog(fmt, ...) do { if (DNT_DEBUG) NSLog((@"[DiscordNoTrack] " fmt), ##__VA_ARGS__); } while (0)

@interface AppsFlyerLib : NSObject
- (void)setIsStopped:(BOOL)stopped;
@end

// RCTNetworking reports a non-HTTP response as status 200, so Discord treats the batch as sent and drops it.
static NSURLRequest *DNTEmptyJSONRequest(void) {
    static NSURLRequest *request;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        request = [NSURLRequest requestWithURL:[NSURL URLWithString:DNTEmptyJSONURL]];
    });
    return request;
}

// SDK callers may cast the response to NSHTTPURLResponse, so native requests fail instead of faking success.
static NSURLRequest *DNTUnroutableRequest(void) {
    static NSURLRequest *request;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://0.0.0.0/"]];
    });
    return request;
}

static NSURLRequest *DNTFiltered(NSURLRequest *request) {
    if (!DNTIsTrackerHost(request.URL)) { return request; }
    DNTLog(@"blocking tracker host: %@", request.URL.host);
    return DNTUnroutableRequest();
}

static NSURL *DNTFilteredURL(NSURL *url) {
    if (!DNTIsTrackerHost(url)) { return url; }
    DNTLog(@"blocking tracker host: %@", url.host);
    return DNTUnroutableRequest().URL;
}

static BOOL DNTClassExists(NSString *className) {
    BOOL exists = NSClassFromString(className) != Nil;
    DNTLog(@"%@ %@", exists ? @"installing hooks for" : @"class not found:", className);
    return exists;
}

// main discord endpoints
%group DNTDiscordNetworking
%hook RCTHTTPRequestHandler
- (id)sendRequest:(NSURLRequest *)request withDelegate:(id)delegate {
    if (!DNTIsDiscordTelemetryPath(request.URL.path)) { return %orig; }
    DNTLog(@"faking success for Discord telemetry path: %@", request.URL.path);
    return %orig(DNTEmptyJSONRequest(), delegate);
}
%end
%end

%group DNTRequestHeaderMutation
%hook NSMutableURLRequest
- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if (value && DNTIsTelemetryHeaderName(field)) {
        DNTLog(@"dropping telemetry header: %@", field);
        return;
    }
    %orig;
}

- (void)addValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if (DNTIsTelemetryHeaderName(field)) {
        DNTLog(@"dropping telemetry header: %@", field);
        return;
    }
    %orig;
}

- (void)setAllHTTPHeaderFields:(NSDictionary<NSString *, NSString *> *)headerFields {
    %orig(DNTWithoutTelemetryHeaders(headerFields));
}
%end
%end

// tracker hosts, for SDK paths the class hooks below miss
%group DNTURLSession
%hook NSURLSession
- (id)dataTaskWithRequest:(NSURLRequest *)request {
    return %orig(DNTFiltered(request));
}

- (id)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(id)handler {
    return %orig(DNTFiltered(request), handler);
}

- (id)dataTaskWithURL:(NSURL *)url completionHandler:(id)handler {
    return %orig(DNTFilteredURL(url), handler);
}

// AppsFlyer's HTTP client sends its requests as download tasks
- (id)downloadTaskWithRequest:(NSURLRequest *)request {
    return %orig(DNTFiltered(request));
}

- (id)uploadTaskWithRequest:(NSURLRequest *)request fromData:(id)data {
    return %orig(DNTFiltered(request), data);
}

- (id)uploadTaskWithRequest:(NSURLRequest *)request fromData:(id)data completionHandler:(id)handler {
    return %orig(DNTFiltered(request), data, handler);
}

- (id)uploadTaskWithRequest:(NSURLRequest *)request fromFile:(id)fileURL {
    return %orig(DNTFiltered(request), fileURL);
}

- (id)uploadTaskWithRequest:(NSURLRequest *)request fromFile:(id)fileURL completionHandler:(id)handler {
    return %orig(DNTFiltered(request), fileURL, handler);
}

- (id)uploadTaskWithStreamedRequest:(NSURLRequest *)request {
    return %orig(DNTFiltered(request));
}
%end
%end

// appsflyer: isStopped is the SDK's documented opt-out
%group DNTAppsFlyer
%hook AppsFlyerLib
- (BOOL)isStopped { return YES; }
- (void)setIsStopped:(BOOL)stopped { %orig(YES); }

- (void)start {
    [self setIsStopped:YES];
    %orig;
}

- (void)startWithCompletionHandler:(id)handler {
    [self setIsStopped:YES];
    %orig;
}
%end
%end

// sentry: Discord reads SentrySDK.crashedLastRun at launch, so the SDK starts with only its crash handler and drops every event.
%group DNTSentry
%hook SentryOptions
- (BOOL)enabled { return NO; }
- (void)setEnabled:(BOOL)a { %orig(NO); }
- (BOOL)isTracingEnabled { return NO; }
- (NSArray *)integrations { return @[@"SentryCrashIntegration"]; }
%end
%end

%ctor {
    @autoreleasepool {
        %init(DNTRequestHeaderMutation);
        %init(DNTURLSession);

        if (DNTClassExists(@"RCTHTTPRequestHandler")) {
            %init(DNTDiscordNetworking);
        }
        if (DNTClassExists(@"AppsFlyerLib")) {
            %init(DNTAppsFlyer);
        }
        if (DNTClassExists(@"SentryOptions")) {
            %init(DNTSentry);
        }
    }
}
