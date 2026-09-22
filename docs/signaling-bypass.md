# Signaling Server Local Testing Bypass

**Date Modified:** September 22, 2026

## The Problem
By default, MUSIXQUARE relies on the official Cloudflare WebRTC signaling servers (`wss://signal.musixquare.com`) for room creation and peer-to-peer discovery when deployed to a live production website. 

However, if you deploy the frontend to a custom domain without also deploying your own signaling backend, the official production signaling server will reject your custom domain's requests due to strict CORS (Cross-Origin Resource Sharing) security policies. This would result in a "Couldn't create session" error for your users.

## The Temporary Solution
To allow you to deploy the frontend to a custom live domain (like Vercel or GitHub Pages) without needing a backend, we have disabled the official Cloudflare signaling fallback. 

By forcing the public signaling URLs to return `undefined`, the application will safely and permanently fall back to using **PeerJS** (a free, open-source peer-to-peer network) for all WebRTC signaling, regardless of whether you are testing locally or deploying on the internet.

### Modified File
[`src/network/transport/config.ts`](../src/network/transport/config.ts)

### Current Hardcoded Bypass
```typescript
export function getPublicSignalingUrlForHost(hostname = location.hostname): string | undefined {
  return undefined; // original: isLocalTransportHost(hostname) ? undefined : PUBLIC_SIGNALING_URL;
}

function getPublicSignalingFallbackUrlForHost(hostname = location.hostname): string | undefined {
  return undefined; // original: isLocalTransportHost(hostname) ? undefined : PUBLIC_SIGNALING_FALLBACK_URL;
}
```

## How to Revert
Once you are ready to host the Cloudflare backend yourself and want to utilize premium signaling and TURN servers for better strict-network traversal, **you must revert this hack back to its original ternary logic**.

```typescript
export function getPublicSignalingUrlForHost(hostname = location.hostname): string | undefined {
  return isLocalTransportHost(hostname) ? undefined : PUBLIC_SIGNALING_URL;
}

function getPublicSignalingFallbackUrlForHost(hostname = location.hostname): string | undefined {
  return isLocalTransportHost(hostname) ? undefined : PUBLIC_SIGNALING_FALLBACK_URL;
}
```
