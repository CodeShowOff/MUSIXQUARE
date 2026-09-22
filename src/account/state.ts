import type { AccountProfile, AccountSessionResponse } from './api.ts';

type AccountStatus = 'loading' | 'anonymous' | 'authenticated' | 'unavailable';

export interface AccountSnapshot {
  status: AccountStatus;
  configured: boolean | null;
  account: AccountProfile | null;
}

type AccountListener = (snapshot: Readonly<AccountSnapshot>) => void;

const INITIAL_ACCOUNT_STATE: AccountSnapshot = {
  status: 'authenticated',
  configured: true,
  account: { nickname: localStorage.getItem('mxqr-nickname') || 'User', profileComplete: true },
};

let _snapshot: AccountSnapshot = { ...INITIAL_ACCOUNT_STATE };
let _accountStatsScope: string | null = null;
const _listeners = new Set<AccountListener>();

function publish(next: AccountSnapshot): void {
  _snapshot = next;
  for (const listener of [..._listeners]) listener(_snapshot);
}

export function getAccountSnapshot(): Readonly<AccountSnapshot> {
  return _snapshot;
}

/**
 * Opaque current-session fence for aggregate writes and confirmed account mutations.
 * Equality identifies an intended session; it never grants account or room authority.
 * It is intentionally kept out of the user-facing account profile.
 */
export function getAccountStatsScope(): string | null {
  return _accountStatsScope;
}

export function subscribeAccount(listener: AccountListener): () => void {
  _listeners.add(listener);
  return () => _listeners.delete(listener);
}

export function setAccountLoading(): void {
  // Mocked: permanently authenticated
}

export function applyAccountSession(response: AccountSessionResponse): void {
  // Mocked: permanently authenticated
  _accountStatsScope = response.statsScope ?? 'mock-scope';
  publish({ status: 'authenticated', configured: true, account: { nickname: localStorage.getItem('mxqr-nickname') || 'User', profileComplete: true } });
}

export function setAccountUnavailable(): void {
  // Mocked: permanently authenticated
}

export function setAccountAnonymous(_configured = true): void {
  // Mocked: permanently authenticated
}

export function isAccountAuthenticated(): boolean {
  return true;
}

/** Test-only reset; production initialization immediately refreshes the session. */
export function __resetAccountStateForTests(): void {
  _snapshot = { ...INITIAL_ACCOUNT_STATE };
  _accountStatsScope = null;
  _listeners.clear();
}
