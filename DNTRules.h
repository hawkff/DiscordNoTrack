#import <Foundation/Foundation.h>

// URL and header rules, shared by the tweak and tests/rules.m.

static NSString *const DNTEmptyJSONURL = @"data:application/json,%7B%7D";

static inline BOOL DNTStringIsDigits(NSString *string) {
    return string.length && [string rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound;
}

// Discord's own matcher is \/api(\/v\d+)?\/science, so the version segment is optional.
static inline BOOL DNTIsDiscordTelemetryPath(NSString *path) {
    if (![path hasPrefix:@"/api/"]) { return NO; }
    NSArray<NSString *> *parts = [path componentsSeparatedByString:@"/"];
    NSUInteger endpoint = ([parts[2] hasPrefix:@"v"] && DNTStringIsDigits([parts[2] substringFromIndex:1])) ? 3 : 2;
    return parts.count > endpoint && [@[@"science", @"metrics", @"beaker"] containsObject:parts[endpoint]];
}

static inline BOOL DNTIsTrackerHost(NSURL *url) {
    static NSString *const suffixes[] = {
        @".appsflyersdk.com", @".appsflyer.com", @".sentry.io",
        // SDKs that older Discord builds shipped
        @".adjust.com", @".adjust.io", @".adjust.net.in", @".adjust.world",
        @".app-measurement.com", @".firebaselogging.googleapis.com", @".firebaselogging-pa.googleapis.com",
        @".crashlyticsreports-pa.googleapis.com",
    };
    NSString *host = url.host.lowercaseString;
    if (!host.length) { return NO; }
    // A host with a root dot ("sentry.io.") resolves to the same servers.
    if ([host hasSuffix:@"."]) { host = [host substringToIndex:host.length - 1]; }
    // The leading dot lets one suffix test match the domain and its subdomains.
    host = [@"." stringByAppendingString:host];
    for (size_t i = 0; i < sizeof(suffixes) / sizeof(*suffixes); i++) {
        if ([host hasSuffix:suffixes[i]]) { return YES; }
    }
    return NO;
}

static inline BOOL DNTIsTelemetryHeaderName(NSString *name) {
    // Messaging nil returns 0, which is NSOrderedSame.
    return name && ([name caseInsensitiveCompare:@"sentry-trace"] == NSOrderedSame || [name caseInsensitiveCompare:@"baggage"] == NSOrderedSame);
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
