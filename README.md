# DiscordNoTrack

DiscordNoTrack is an iOS tweak that blocks telemetry in the Discord app.

## What it does

- Blocks Discord's analytics endpoints `/api/v*/science`, `/api/v*/metrics`, `/api/v*/metrics/v2` and `/api/v*/beaker`. Discord gets an empty success response, so it treats the events as sent and doesn't retry them.
- Stops AppsFlyer through the SDK's `isStopped` switch and blocks `appsflyersdk.com` and `appsflyer.com`. AppsFlyer deferred deep links stop working.
- Turns off the native Sentry SDK, which also carries Discord's JavaScript crash reports, and blocks `sentry.io`.
- Blocks the hosts of SDKs that older Discord builds shipped: Adjust, Firebase Analytics, Firebase logging and Crashlytics.
- Strips `sentry-trace` and `baggage` headers from every other request.

## Settings worth changing

- In iOS Settings > Privacy & Security > Tracking, turn off Allow Apps to Request to Track. Discord and AppsFlyer then get an all-zero advertising ID.
- In Discord, open Settings > Data & Privacy and turn off Use data to improve Discord. Discord stores this choice on its servers.
- Add `appsflyersdk.com`, `appsflyer.com` and `sentry.io` to a DNS blocker to catch requests the hooks miss.

iOS sends Apple's ad attribution postbacks (SKAdNetwork and AdAttributionKit) outside the app, so no tweak can block them.
