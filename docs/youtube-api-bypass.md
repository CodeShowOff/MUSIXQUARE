# YouTube API Local Testing Bypass

**Date Modified:** September 22, 2026

## The Problem
When running the frontend locally via `npm run dev`, the app expects a local Cloudflare worker backend to be running to securely proxy requests to the YouTube Data API. Without the backend running, the frontend receives a `404` or `index.html` fallback when attempting to fetch `/api/youtube-search`, causing the UI to break and display "YouTube search is unavailable".

## The Temporary Solution
To allow UI testing without needing to configure and run the Wrangler backend locally, we have temporarily hardcoded the YouTube endpoints in `src/youtube/search.ts` to point directly to the live `musixquare.com` production server.

### Modified File
[`src/youtube/search.ts`](../src/youtube/search.ts)

### Current Hardcoded Endpoints
```typescript
const YOUTUBE_SEARCH_ENDPOINT = 'https://musixquare.com/api/youtube-search';
const YOUTUBE_PLAYLIST_ENTRY_ENDPOINT = 'https://musixquare.com/api/youtube-playlist-entry';
const YOUTUBE_PLAYLIST_MANIFEST_ENDPOINT = 'https://musixquare.com/api/youtube-playlist-manifest';
```

## How to Revert
Once you are ready to host the Cloudflare backend locally or deploy the full application, **you must revert these variables back to relative paths**.

```typescript
const YOUTUBE_SEARCH_ENDPOINT = '/api/youtube-search';
const YOUTUBE_PLAYLIST_ENTRY_ENDPOINT = '/api/youtube-playlist-entry';
const YOUTUBE_PLAYLIST_MANIFEST_ENDPOINT = '/api/youtube-playlist-manifest';
```

Failing to revert these paths will cause your deployed application to always hit the `musixquare.com` domain instead of your own hosted backend, which may result in CORS errors or rate-limiting blockades.
