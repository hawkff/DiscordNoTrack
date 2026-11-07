#import <Foundation/Foundation.h>
#import <assert.h>
#import "DNTRules.h"

static BOOL DNTIsTrackerURL(NSString *url) {
    return DNTIsTrackerHost([NSURL URLWithString:url]);
}

int main(void) {
    @autoreleasepool {
        assert(DNTIsDiscordTelemetryPath(@"/api/v9/science"));
        assert(DNTIsDiscordTelemetryPath(@"/api/science"));
        assert(DNTIsDiscordTelemetryPath(@"/api/v10/metrics"));
        assert(DNTIsDiscordTelemetryPath(@"/api/v9/metrics/v2"));
        assert(DNTIsDiscordTelemetryPath(@"/api/v9/beaker"));
        assert(!DNTIsDiscordTelemetryPath(@"/api/v9/users/@me"));
        assert(!DNTIsDiscordTelemetryPath(@"/api/v9/channels/1/messages"));
        assert(!DNTIsDiscordTelemetryPath(@"/api/v9"));
        assert(!DNTIsDiscordTelemetryPath(@"/api/vx/science"));
        assert(!DNTIsDiscordTelemetryPath(@"/science"));
        assert(!DNTIsDiscordTelemetryPath(@"api/v9/science"));
        assert(!DNTIsDiscordTelemetryPath(nil));

        assert(DNTIsTrackerURL(@"https://launches.appsflyersdk.com/api/v6.17/iosevent?app_id=1"));
        assert(DNTIsTrackerURL(@"https://o64374.ingest.sentry.io/api/230973/envelope/"));
        assert(DNTIsTrackerURL(@"https://SENTRY.IO/"));
        assert(!DNTIsTrackerURL(@"https://notsentry.io/"));
        assert(!DNTIsTrackerURL(@"https://discord.com/api/v9/science"));
        assert(!DNTIsTrackerURL(@"https://codeberg.org/raincord/rain/releases/download/latest/rain.98.hbc"));
        assert(!DNTIsTrackerURL(@"data:application/json,%7B%7D"));

        assert(DNTIsTelemetryHeaderName(@"Sentry-Trace"));
        assert(DNTIsTelemetryHeaderName(@"baggage"));
        assert(!DNTIsTelemetryHeaderName(@"Authorization"));
        NSDictionary<NSString *, NSString *> *headers = @{@"Authorization": @"token", @"sentry-trace": @"1", @"Baggage": @"2"};
        assert([DNTWithoutTelemetryHeaders(headers) isEqualToDictionary:@{@"Authorization": @"token"}]);
        NSDictionary<NSString *, NSString *> *clean = @{@"Accept": @"*/*"};
        assert(DNTWithoutTelemetryHeaders(clean) == clean);

        // RCTNetworking turns a non-HTTP response into status 200; Discord's HTTP layer then parses the {} body.
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        [[NSURLSession.sharedSession dataTaskWithURL:[NSURL URLWithString:DNTEmptyJSONURL] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            assert(!error);
            assert(![response isKindOfClass:NSHTTPURLResponse.class]);
            assert([response.MIMEType isEqualToString:@"application/json"]);
            assert([data isEqualToData:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]]);
            dispatch_semaphore_signal(done);
        }] resume];
        long timedOut = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
        assert(!timedOut);
    }
    puts("rules ok");
    return 0;
}
