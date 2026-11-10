# DiscordNoTrack

DiscordNoTrack is an iOS tweak that blocks telemetry in the Discord app. It runs inside the app and hooks its networking and analytics SDKs, so it also stops native trackers that JavaScript plugins can't hook.

## What it blocks

- Discord's analytics endpoints `/api/v*/science`, `/api/v*/metrics`, `/api/v*/metrics/v2` and `/api/v*/beaker`. Discord gets an empty success response, so it treats the events as sent and doesn't retry them.
- AppsFlyer. The tweak sets the SDK's `isStopped` switch and blocks `appsflyersdk.com` and `appsflyer.com`. AppsFlyer deferred deep links stop working.
- The native Sentry SDK, which also carries Discord's JavaScript crash reports. Discord reads the SDK's crash flag at launch, so the tweak lets Sentry start with its crash handler alone. Sentry then drops every event, and the tweak blocks `sentry.io`.
- The hosts of SDKs that older Discord builds shipped: Adjust, Firebase Analytics, Firebase logging and Crashlytics.
- `sentry-trace` and `baggage` headers on every other request.

Discord 332, 344.1 and 352.1 ship AppsFlyer 6.17.8 and Sentry Cocoa 8.58.0, the versions these hooks target. On a device running Discord 352.1, an HTTPS proxy recorded no request to any of these endpoints or hosts.

## Install

Download `DiscordNoTrack.dylib` from [Releases](https://github.com/hawkff/DiscordNoTrack/releases) and compare it with the SHA-256 in the release notes.

- To sideload, add the dylib as a tweak when you sign a decrypted Discord IPA, for example in Feather. It needs no CydiaSubstrate or ElleKit.
- With a client mod, inject it next to the mod's loader, such as RainTweak or Unbound. Mods that block tracking do it in JavaScript and can't hook the native AppsFlyer and Sentry SDKs.
- On a jailbroken device, build a rootless package with Theos (`make package`).

## Settings worth changing

- In iOS Settings > Privacy & Security > Tracking, turn off Allow Apps to Request to Track. Discord and AppsFlyer then get an all-zero advertising ID.
- In Discord, open Settings > Data & Privacy and turn off Use data to improve Discord. Discord stores this choice on its servers.
- Add `appsflyersdk.com`, `appsflyer.com` and `sentry.io` to a DNS blocker to catch requests the hooks miss.

iOS sends Apple's ad attribution postbacks (SKAdNetwork and AdAttributionKit) outside the app, so no tweak can block them.

## Build

With [Theos](https://theos.dev) installed, run `make`. `make DNT_DEBUG=1` builds a version that logs which SDK hooks it installs and each request it blocks.

## License

LGPL-3.0, inherited from [asdfzxcvbn/DiscordNoTrack](https://github.com/asdfzxcvbn/DiscordNoTrack).
