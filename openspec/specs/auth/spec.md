# auth — Specification

## Purpose

Defines how JakeOS authenticates users. JakeOS is a single-user system. Authentication uses Google OAuth 2.0 ("Sign in with Google"), gated to exactly one account (`jake.hallman@gmail.com`). The same OAuth grant that authenticates the user also carries the Gmail and Calendar read scopes that downstream capabilities depend on, so there is one consent flow rather than two parallel auth systems. Multi-factor authentication is inherited from the user's Google account; JakeOS never bypasses or weakens it.

**Status:** Active.
**Introduced by:** `jakeos-dashboard-v1` (2026-05-01).
**Owner:** Jake Hallman.
**Provider:** Google OAuth 2.0.
**Allowed identity:** `jake.hallman@gmail.com` (single account).

## Requirements

### Requirement: Google OAuth as the sign-in mechanism

The dashboard SHALL authenticate users via Google OAuth 2.0 (Sign in with Google). No password-based sign-in path SHALL be exposed.

#### Scenario: Jake hits `jakeos.jakehallman.com` while unauthenticated

- **WHEN** an unauthenticated request reaches `https://jakeos.jakehallman.com`
- **THEN** the request MUST be redirected to Google's OAuth consent flow
- **AND** the OAuth `client_id` and callback URL MUST be configured for `https://jakeos.jakehallman.com/oauth2/callback`

### Requirement: Single-allowed-account guard

The OAuth callback handler SHALL enforce that the authenticated email is exactly `jake.hallman@gmail.com`. Any other authenticated email MUST be rejected, regardless of OAuth grant validity.

#### Scenario: A different Google account completes the OAuth flow

- **WHEN** the callback receives a valid token resolving to any email other than `jake.hallman@gmail.com`
- **THEN** the session MUST be denied
- **AND** the rejected email MUST be recorded in the audit log per [data-contract](../data-contract/spec.md)
- **AND** the response MUST be a generic "access denied" — not a confirmation that the wrong account was used

### Requirement: Reuse OAuth grant for Gmail and Calendar scopes

The same OAuth grant that authenticates the user SHALL also carry the Gmail and Calendar read scopes that JakeOS needs for capabilities #4 (important email surface) and #6 (calendar surface). There MUST be only one consent flow.

#### Scenario: Jake authenticates for the first time

- **WHEN** the OAuth consent screen appears
- **THEN** it MUST request the read scopes for Gmail and Calendar in the same prompt as sign-in
- **AND** if Jake declines any required scope, the dashboard MUST refuse the session and explain which scope was missing

### Requirement: MFA inheritance

JakeOS SHALL inherit whatever multi-factor authentication policy Jake has configured on his Google account. JakeOS itself MUST NOT bypass or weaken Google's MFA requirements.

#### Scenario: Google requires a 2-step prompt

- **WHEN** Google's auth flow demands a second factor (push, code, hardware key)
- **THEN** the JakeOS auth flow MUST wait for that factor to complete
- **AND** MUST NOT cache or shortcut subsequent sign-ins past Google's session lifetime

### Requirement: Session expiry

Sessions SHALL expire after 30 days of inactivity, OR when Google revokes the OAuth grant, whichever comes first.

#### Scenario: Jake doesn't open the dashboard for 31 days

- **WHEN** the next request arrives
- **THEN** the session MUST be invalid
- **AND** Jake MUST be redirected through the OAuth flow again
- **AND** if Google's grant is still valid, the re-auth MUST be silent (no consent screen re-prompt)

### Requirement: Session revocation control

The dashboard SHALL expose a "log out everywhere" control. When invoked, all active JakeOS sessions across surfaces MUST be invalidated within one sync cycle.

#### Scenario: Jake clicks "log out everywhere" after losing a device

- **WHEN** the revocation is initiated
- **THEN** the next request from any active session MUST require re-authentication
- **AND** the revocation event MUST be recorded in the audit log

### Requirement: Secret storage

OAuth tokens, refresh tokens, and any session secrets SHALL be stored in OS-appropriate secure storage. On the macOS side (sidecar), this means the macOS Keychain. On the server side (the standalone web app behind Caddy), this means a server-side secret store (file with restricted permissions, environment variable injected at runtime, or a dedicated secret manager). Plain-text secrets MUST NOT appear in repo files, logs, or browser local storage.

#### Scenario: A token is needed by the dashboard

- **WHEN** the dashboard needs a Gmail or Calendar OAuth token
- **THEN** it MUST fetch the token from secure storage at request time
- **AND** the token MUST NOT be persisted in the browser

### Requirement: Network exposure

Any authentication endpoint exposed to the public internet SHALL require TLS. No JakeOS surface SHALL accept credentials over plain HTTP.

#### Scenario: A request arrives at an auth endpoint over HTTP

- **WHEN** a credential-bearing request is received without TLS
- **THEN** the surface MUST reject it
- **AND** MUST redirect to the HTTPS equivalent

### Requirement: Capture surface auth

The Helper.app's drop target (per [capture](../capture/spec.md)) MUST NOT require any JakeOS-specific authentication. Trust is delegated to the macOS user account and Keychain. The drop target SHALL only function while the user is logged into the Mac.

#### Scenario: A different user is logged into the Mac

- **WHEN** any user other than Jake's macOS account is active
- **THEN** the drop target MUST refuse captures
- **AND** the sidecar MUST refuse to bind to localhost endpoints
