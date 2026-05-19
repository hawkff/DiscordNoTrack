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
