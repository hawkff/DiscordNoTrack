#import <Foundation/Foundation.h>

// URL and header rules, shared by the tweak and tests/rules.m.

static NSString *const DNTEmptyJSONURL = @"data:application/json,%7B%7D";

static inline BOOL DNTStringIsDigits(NSString *string) {
    return string.length && [string rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound;
}

// Discord's own matcher is \/api(\/v\d+)?\/science, so the version segment is optional.
static inline BOOL DNTIsDiscordTelemetryPath(NSString *path) {
    NSArray<NSString *> *parts = [path componentsSeparatedByString:@"/"];
    if (parts.count < 3 || parts[0].length || ![parts[1] isEqualToString:@"api"]) { return NO; }
    NSUInteger endpoint = ([parts[2] hasPrefix:@"v"] && DNTStringIsDigits([parts[2] substringFromIndex:1])) ? 3 : 2;
    return parts.count > endpoint && [@[@"science", @"metrics", @"beaker"] containsObject:parts[endpoint]];
}

static inline BOOL DNTIsTrackerHost(NSURL *url) {
    NSString *host = url.host.lowercaseString;
    NSArray<NSString *> *domains = @[
        @"appsflyersdk.com", @"appsflyer.com", @"sentry.io",
        // SDKs that older Discord builds shipped
        @"adjust.com", @"adjust.io", @"adjust.net.in", @"adjust.world",
        @"app-measurement.com", @"firebaselogging.googleapis.com", @"firebaselogging-pa.googleapis.com",
        @"crashlyticsreports-pa.googleapis.com",
    ];
    for (NSString *domain in domains) {
        if ([host isEqualToString:domain] || [host hasSuffix:[@"." stringByAppendingString:domain]]) { return YES; }
    }
    return NO;
}

static inline BOOL DNTIsTelemetryHeaderName(NSString *name) {
    NSString *lowercaseName = name.lowercaseString;
    return [lowercaseName isEqualToString:@"sentry-trace"] || [lowercaseName isEqualToString:@"baggage"];
}

static inline NSDictionary<NSString *, NSString *> *DNTWithoutTelemetryHeaders(NSDictionary<NSString *, NSString *> *headers) {
    NSMutableDictionary<NSString *, NSString *> *clean;
    for (NSString *name in headers) {
        if (!DNTIsTelemetryHeaderName(name)) { continue; }
        if (!clean) { clean = [headers mutableCopy]; }
        [clean removeObjectForKey:name];
    }
    return clean ?: headers;
}
