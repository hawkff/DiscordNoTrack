#import <Foundation/Foundation.h>
#import "dummyDelegate.h"
%config(generator=internal);

#ifndef DNT_DEBUG
#define DNT_DEBUG 0
#endif

#define DNTLog(fmt, ...) do { if (DNT_DEBUG) NSLog((@"[DiscordNoTrack] " fmt), ##__VA_ARGS__); } while (0)

static NSURLRequest *DNTBlockedRequest(void) {
    static NSURLRequest *request;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://0.0.0.0/"]];
    });
    return request;
}

static dummyDelegate *DNTDummyDelegate(void) {
    static dummyDelegate *delegate;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        delegate = [[dummyDelegate alloc] init];
    });
    return delegate;
}

static BOOL DNTStringIsDigits(NSString *string) {
    if (!string.length) { return NO; }
    return [string rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound;
}

static BOOL DNTIsDiscordTelemetryPath(NSString *path) {
    NSArray<NSString *> *parts = [path componentsSeparatedByString:@"/"];
    if (parts.count < 4) { return NO; }
    if (![parts[0] isEqualToString:@""] || ![parts[1] isEqualToString:@"api"]) { return NO; }

    NSString *version = parts[2];
    if (![version hasPrefix:@"v"] || !DNTStringIsDigits([version substringFromIndex:1])) { return NO; }

    NSString *endpoint = parts[3];
    return [endpoint isEqualToString:@"science"] || [endpoint isEqualToString:@"metrics"];
}

static BOOL DNTIsTelemetryHeaderName(NSString *headerName) {
    NSString *lowercaseHeaderName = headerName.lowercaseString;
    return [lowercaseHeaderName isEqualToString:@"sentry-trace"] || [lowercaseHeaderName isEqualToString:@"baggage"];
}

static NSDictionary<NSString *, NSString *> *DNTSanitizedHeaderFields(NSDictionary<NSString *, NSString *> *headers, BOOL *removedHeaders) {
    BOOL removed = NO;
    NSMutableDictionary<NSString *, NSString *> *sanitizedHeaders;

    for (NSString *headerName in headers) {
        if (DNTIsTelemetryHeaderName(headerName)) {
            if (!sanitizedHeaders) {
                sanitizedHeaders = [headers mutableCopy];
            }
            [sanitizedHeaders removeObjectForKey:headerName];
            removed = YES;
        }
    }

    if (removedHeaders) {
        *removedHeaders = removed;
    }
    return sanitizedHeaders ?: headers;
}

static NSURLRequest *DNTSanitizedRequest(NSURLRequest *request) {
    NSDictionary<NSString *, NSString *> *headers = request.allHTTPHeaderFields;
    if (!headers.count) { return request; }

    BOOL removedHeaders = NO;
    NSDictionary<NSString *, NSString *> *sanitizedHeaders = DNTSanitizedHeaderFields(headers, &removedHeaders);
    if (!removedHeaders) { return request; }

    NSMutableURLRequest *sanitizedRequest = [request mutableCopy];
    sanitizedRequest.allHTTPHeaderFields = sanitizedHeaders;
    [sanitizedRequest setValue:nil forHTTPHeaderField:@"sentry-trace"];
    [sanitizedRequest setValue:nil forHTTPHeaderField:@"baggage"];
    DNTLog(@"stripped telemetry headers from request: %@", request.URL.absoluteString);
    return sanitizedRequest;
}

static NSString *DNTLowercaseHost(NSURL *url) {
    return url.host.lowercaseString;
}

static BOOL DNTIsFirebaseLoggingURL(NSURL *url) {
    return [DNTLowercaseHost(url) containsString:@"firebaselogging"];
}

static BOOL DNTIsAdjustURL(NSURL *url) {
    NSString *host = DNTLowercaseHost(url);
    return [host isEqualToString:@"adjust.com"] || [host hasPrefix:@"adjust."] || [host containsString:@".adjust."];
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
    if (DNTIsDiscordTelemetryPath(request.URL.path)) {
        DNTLog(@"blocking Discord telemetry path: %@", request.URL.path);
        return %orig(DNTBlockedRequest(), DNTDummyDelegate());
    }
    return %orig(DNTSanitizedRequest(request), delegate);
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
    %orig(value, field);
}

- (void)addValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if (DNTIsTelemetryHeaderName(field)) {
        DNTLog(@"dropping telemetry header: %@", field);
        return;
    }
    %orig(value, field);
}

- (void)setAllHTTPHeaderFields:(NSDictionary<NSString *, NSString *> *)headerFields {
    BOOL removedHeaders = NO;
    NSDictionary<NSString *, NSString *> *sanitizedHeaders = DNTSanitizedHeaderFields(headerFields, &removedHeaders);
    if (removedHeaders) {
        DNTLog(@"stripped telemetry headers from header dictionary");
    }
    %orig(sanitizedHeaders);
}
%end
%end

// firebase logging + adjust network blocking
%group DNTURLSession
%hook NSURLSession
- (id)dataTaskWithRequest:(NSURLRequest *)request {
    if (DNTIsAdjustURL(request.URL)) {
        DNTLog(@"blocking Adjust URL: %@", request.URL.absoluteString);
        return %orig(DNTBlockedRequest());
    }
    return %orig(DNTSanitizedRequest(request));
}

- (id)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(id)handler {
    if (DNTIsAdjustURL(request.URL)) {
        DNTLog(@"blocking Adjust URL: %@", request.URL.absoluteString);
        return %orig(DNTBlockedRequest(), handler);
    }
    return %orig(DNTSanitizedRequest(request), handler);
}

- (id)uploadTaskWithRequest:(NSURLRequest *)request fromData:(id)data {
    if (DNTIsFirebaseLoggingURL(request.URL)) {
        DNTLog(@"blocking Firebase logging URL: %@", request.URL.absoluteString);
        return %orig(DNTBlockedRequest(), data);
    }
    return %orig(DNTSanitizedRequest(request), data);
}

- (id)uploadTaskWithRequest:(NSURLRequest *)request fromData:(id)data completionHandler:(id)handler {
    if (DNTIsFirebaseLoggingURL(request.URL)) {
        DNTLog(@"blocking Firebase logging URL: %@", request.URL.absoluteString);
        return %orig(DNTBlockedRequest(), data, handler);
    }
    return %orig(DNTSanitizedRequest(request), data, handler);
}

- (id)uploadTaskWithRequest:(NSURLRequest *)request fromFile:(id)fileURL {
    if (DNTIsFirebaseLoggingURL(request.URL)) {
        DNTLog(@"blocking Firebase logging URL: %@", request.URL.absoluteString);
        return %orig(DNTBlockedRequest(), fileURL);
    }
    return %orig(DNTSanitizedRequest(request), fileURL);
}

- (id)uploadTaskWithRequest:(NSURLRequest *)request fromFile:(id)fileURL completionHandler:(id)handler {
    if (DNTIsFirebaseLoggingURL(request.URL)) {
        DNTLog(@"blocking Firebase logging URL: %@", request.URL.absoluteString);
        return %orig(DNTBlockedRequest(), fileURL, handler);
    }
    return %orig(DNTSanitizedRequest(request), fileURL, handler);
}

- (id)uploadTaskWithStreamedRequest:(NSURLRequest *)request {
    if (DNTIsFirebaseLoggingURL(request.URL)) {
        DNTLog(@"blocking Firebase logging URL: %@", request.URL.absoluteString);
        return %orig(DNTBlockedRequest());
    }
    return %orig(DNTSanitizedRequest(request));
}

- (id)downloadTaskWithRequest:(NSURLRequest *)request {
    return %orig(DNTSanitizedRequest(request));
}

- (id)downloadTaskWithRequest:(NSURLRequest *)request completionHandler:(id)handler {
    return %orig(DNTSanitizedRequest(request), handler);
}
%end
%end

// sentry
%group DNTSentrySDK
%hook SentrySDK
+ (BOOL)isEnabled { return NO; }
%end
%end

%group DNTSentryOptions
%hook SentryOptions
- (BOOL)enabled { return NO; }
- (BOOL)isTracingEnabled { return NO; }
- (BOOL)isProfilingEnabled { return NO; }
- (void)setEnabled:(BOOL)a { %orig(NO); }
%end
%end

%group DNTSentryClient
%hook SentryClient
- (BOOL)isEnabled { return NO; }
%end
%end

%group DNTSentryNSDataTracker
%hook SentryNSDataTracker
- (BOOL)isEnabled { return NO; }
- (void)setIsEnabled:(BOOL)a { %orig(NO); }
%end
%end

%group DNTSentryNetworkTracker
%hook SentryNetworkTracker
- (BOOL)isNetworkTrackingEnabled { return NO; }
- (BOOL)isNetworkBreadcrumbEnabled { return NO; }
- (void)setIsNetworkTrackingEnabled:(BOOL)a { %orig(NO); }
- (void)setIsNetworkBreadcrumbEnabled:(BOOL)a { %orig(NO); }
%end
%end

// app-measurement
%group DNTAppMeasurement
%hook APMMeasurement
- (void)uploadData {}
- (BOOL)isEnabled { return NO; }
- (BOOL)hasDataToUpload { return NO; }
- (BOOL)isNetworkRequestPending { return NO; }
- (BOOL)isAnalyticsCollectionEnabled { return NO; }
- (BOOL)isAnalyticsCollectionDeactivated { return YES; }
%end
%end

// adjust
%group DNTAdjust
%hook Adjust
+ (BOOL)isEnabled { return NO; }
+ (void)setEnabled:(BOOL)a { %orig(NO); }
+ (void)setOfflineMode:(BOOL)arg1 { %orig(YES); }
- (void)setOfflineMode:(BOOL)arg1 { %orig(YES); }
- (void)setEnabled:(BOOL)a { %orig(NO); }
- (BOOL)isInstanceEnabled { return NO; }
- (BOOL)isEnabled { return NO; }
%end
%end

%group DNTADJActivityHandler
%hook ADJActivityHandler
- (void)setOfflineMode:(BOOL)a { %orig(YES); }
- (void)setOfflineModeI:(id)a offline:(BOOL)b { %orig(a, YES); }
%end
%end

// crashlytics
%group DNTCrashlytics
%hook FIRCrashlytics
+ (void)load {}
- (void)sendUnsentReports {}
- (void)setCrashlyticsCollectionEnabled:(BOOL)a { %orig(NO); }
- (BOOL)isCrashlyticsCollectionEnabled { return NO; }
%end
%end

%ctor {
    @autoreleasepool {
        if (DNTClassExists(@"RCTHTTPRequestHandler")) {
            %init(DNTDiscordNetworking);
        }
        %init(DNTRequestHeaderMutation);
        %init(DNTURLSession);

        if (DNTClassExists(@"SentrySDK")) {
            %init(DNTSentrySDK);
        }
        if (DNTClassExists(@"SentryOptions")) {
            %init(DNTSentryOptions);
        }
        if (DNTClassExists(@"SentryClient")) {
            %init(DNTSentryClient);
        }
        if (DNTClassExists(@"SentryNSDataTracker")) {
            %init(DNTSentryNSDataTracker);
        }
        if (DNTClassExists(@"SentryNetworkTracker")) {
            %init(DNTSentryNetworkTracker);
        }
        if (DNTClassExists(@"APMMeasurement")) {
            %init(DNTAppMeasurement);
        }
        if (DNTClassExists(@"Adjust")) {
            %init(DNTAdjust);
        }
        if (DNTClassExists(@"ADJActivityHandler")) {
            %init(DNTADJActivityHandler);
        }
        if (DNTClassExists(@"FIRCrashlytics")) {
            %init(DNTCrashlytics);
        }
    }
}
