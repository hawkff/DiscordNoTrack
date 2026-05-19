# DiscordNoTrack
blocks network requests to the following endpoints:
- discord.com/api/v*/science
- discord.com/api/v*/metrics
- discord.com/api/v*/metrics/*
- adjust
- sentry
- crashlytics
- app-measurement
- firebase (analytics)

It also strips `sentry-trace` and `baggage` headers from allowed outgoing requests.

## Build

```sh
make clean package
```

For local diagnostics:

```sh
make clean package DNT_DEBUG=1
```

GitHub Actions builds `DiscordNoTrack.dylib` on macOS and uploads it as a workflow artifact.

The raw `DiscordNoTrack.dylib` can be injected into a decrypted Discord IPA with tools such as Feather. If you co-inject BTLoader, inject BTLoader with its resources and inject DiscordNoTrack as a plain extra dylib.
