# Premium Tier (PRO) Status & Configuration

This document explains the current state of the "PRO" tier features in this repository as of our recent refactor, how the app functions without the Cloudflare backend, and how to re-enable it in the future.

## Current State: Mocked PRO Access
To make the application completely free and remove the need for users to create an account, the frontend authentication has been bypassed.

- **Login Removed:** The UI buttons for logging in and creating an account have been removed. User nicknames are managed entirely in the browser's `localStorage` (`src/account/nickname.ts`).
- **Auto-Authenticated:** The core account state (`src/account/state.ts` and `src/account/api.ts`) is permanently mocked to return `authenticated: true` with a dummy account profile. The app treats all anonymous users as "PRO" users internally.

## App Functionality Without the Backend
The MUSIXQUARE repository contains both client-side and server-side code for "PRO" rooms. Currently, the server-side Cloudflare backend is not deployed. 

The application **will still work perfectly fine** without the hosted Cloudflare backend, but only for **Standard P2P Rooms**:
- **Standard Rooms (Working):** Standard rooms are 100% Peer-to-Peer (P2P). They do not use the Cloudflare backend (only standard STUN/TURN). Any room a user creates from the UI right now is automatically a Standard Room. These will work perfectly, for free.
- **PRO Rooms (Dormant):** The PRO rooms utilize a paid server-side backend hosted on Cloudflare (with an SFU WebRTC topology). Since the "Create PRO Room" UI was removed (it used to be inside the account modal), users cannot create new PRO rooms. If a user tries to enter a legacy PRO room code, the app will attempt to connect to the missing Cloudflare backend and fail.

## Re-Enabling the Premium Infrastructure
Because the complete frontend code (`src/pro-room`) and backend code (`cloudflare/` directory containing the Cloudflare Workers and SQL schemas) are completely intact in this repository, you can host the premium infrastructure yourself at any time.

When you are ready to deploy the premium infrastructure:
1. Deploy the backend services located in the `cloudflare/` directory.
2. Re-add a "Create PRO Room" button to the frontend UI so users can generate PRO room codes.
3. The frontend is already wired up (via the mocked `state.ts`) to authorize against the backend as a PRO user, so users will immediately be able to join your self-hosted premium servers without a login wall.
