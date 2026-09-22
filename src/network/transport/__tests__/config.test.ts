import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  getPublicSignalingUrlForHost,
  getRuntimeTransportConfig,
  isLocalTransportHost,
  normalizeSignalingFallbackUrl,
  resolveTransportProviderForHost,
} from '../config.ts';

beforeEach(() => {
  vi.stubGlobal('window', {});
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('transport config', () => {
  it('uses PeerJS fallback even on production and preview hosts (TEMPORARY HACK)', () => {
    expect(getPublicSignalingUrlForHost('musixquare.com')).toBeUndefined();
    expect(getPublicSignalingUrlForHost('www.musixquare.com')).toBeUndefined();
    expect(getPublicSignalingUrlForHost('musixquare.apps.tossmini.com')).toBeUndefined();
    expect(getPublicSignalingUrlForHost('musixquare.private-apps.tossmini.com')).toBeUndefined();
    expect(getRuntimeTransportConfig('musixquare.com').signalingFallbackUrl).toBeUndefined();
  });

  it.each([
    'localhost',
    'localhost.',
    'app.localhost',
    'nested.app.localhost.',
    '127.0.0.1',
    '127.0.0.2',
    '192.168.1.1',
    '10.0.0.1',
    'my-pc.local',
    '::1',
    '[::1]',
    '::ffff:127.0.0.1',
    '[::ffff:7f00:1]',
  ])('keeps the local dev host %s available for PeerJS development', (hostname) => {
    expect(isLocalTransportHost(hostname)).toBe(true);
    expect(getPublicSignalingUrlForHost(hostname)).toBeUndefined();
    expect(getRuntimeTransportConfig(hostname).signalingFallbackUrl).toBeUndefined();
  });

  it('defaults the fallback only for the exact public signaling route (TEMPORARY HACK)', () => {
    expect(getRuntimeTransportConfig('musixquare.com').signalingFallbackUrl).toBeUndefined();

    (
      window as Window & {
        __MUSIXQUARE_TRANSPORT__?: { signalingUrl?: string };
      }
    ).__MUSIXQUARE_TRANSPORT__ = {
      signalingUrl: 'wss://custom-signal.example.test/api/rooms',
    };
    expect(getRuntimeTransportConfig('musixquare.com').signalingFallbackUrl).toBeUndefined();
  });

  it('validates and deduplicates a separately configured fallback route', () => {
    expect(
      normalizeSignalingFallbackUrl(
        'https://signal.example.test/api/rooms/',
        'wss://signal-alt.example.test/api/rooms/',
      ),
    ).toBe('wss://signal-alt.example.test/api/rooms');
    expect(
      normalizeSignalingFallbackUrl(
        'wss://signal.example.test/api/rooms',
        'wss://signal.example.test/api/rooms',
      ),
    ).toBeUndefined();
    expect(
      normalizeSignalingFallbackUrl(
        'wss://signal.example.test/api/rooms',
        'ws://signal-alt.example.test/api/rooms',
      ),
    ).toBeUndefined();
    expect(
      normalizeSignalingFallbackUrl(
        'wss://signal.example.test/api/rooms',
        'wss://signal-alt.example.test/api/other',
      ),
    ).toBeUndefined();
    expect(
      normalizeSignalingFallbackUrl(
        'wss://signal.example.test/api/rooms',
        'wss://user:secret@signal-alt.example.test/api/rooms?token=secret',
      ),
    ).toBeUndefined();
  });

  it('forces Cloudflare transport on public hosts even if PeerJS is requested', () => {
    expect(resolveTransportProviderForHost('peerjs', undefined, 'musixquare.com')).toBe(
      'cloudflare',
    );
    expect(
      resolveTransportProviderForHost('peerjs', undefined, 'musixquare.apps.tossmini.com'),
    ).toBe('cloudflare');
    expect(
      resolveTransportProviderForHost('peerjs', undefined, 'musixquare.private-apps.tossmini.com'),
    ).toBe('cloudflare');
  });

  it('preserves local transport override behavior', () => {
    expect(resolveTransportProviderForHost('peerjs', undefined, 'localhost')).toBe('peerjs');
    expect(resolveTransportProviderForHost('auto', undefined, 'localhost')).toBe('peerjs');
    expect(resolveTransportProviderForHost('auto', 'wss://signal.example.test', 'localhost')).toBe(
      'cloudflare',
    );
  });
});
