# auth — spec delta

> Architecture-independent auth requirements. The chosen auth model (WP login / Caddy basic auth / OAuth-to-self / OS-only) lands during `/opsx:apply` after design.md Q3.

## ADDED Requirements

### Requirement: Single-identity gate

JakeOS SHALL recognize exactly one authorized identity (Jake Hallman, `jake.hallman@gmail.com`). Any successful authentication that does not resolve to that identity MUST be denied access to dashboard content and connected-source data.

#### Scenario: A correctly-credentialed but wrong-identity OAuth grant

- **WHEN** an OAuth flow returns a valid token for a non-Jake account
- **THEN** the dashboard MUST refuse the session
- **AND** an audit-log entry MUST record the rejected identity for review

### Requirement: Secret storage

Credentials, OAuth tokens, and any session secrets SHALL be stored in OS-appropriate secure storage (macOS Keychain on the Helper, server-side secret store on the web surface). Plain-text secrets MUST NOT appear in repo files, environment variables exposed in logs, or browser local storage.

#### Scenario: A token is needed by the dashboard

- **WHEN** the dashboard needs a Gmail or Calendar OAuth token
- **THEN** it MUST fetch the token from secure storage at request time
- **AND** the token MUST NOT be persisted in the browser

### Requirement: Session expiry and revocation

Sessions SHALL expire automatically after a defined idle period. Jake SHALL be able to revoke any active session from the dashboard without re-deploying.

#### Scenario: Jake clicks "log out everywhere"

- **WHEN** Jake initiates global revocation
- **THEN** all active sessions across surfaces MUST be invalidated within one sync cycle
- **AND** the next request from any of those sessions MUST require re-authentication

### Requirement: Network exposure

Any authentication endpoint exposed to the public internet SHALL require TLS. No JakeOS surface SHALL accept credentials over plain HTTP.

#### Scenario: A request arrives at an auth endpoint over HTTP

- **WHEN** a credential-bearing request is received without TLS
- **THEN** the surface MUST reject it
- **AND** MUST redirect to the HTTPS equivalent

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
- **AND** the rejected email MUST be recorded in the audit log
- **AND** the response MUST be a generic "access denied" — not a confirmation that the wrong account was used

### Requirement: Reuse OAuth grant for Gmail and Calendar scopes

The same OAuth grant that authenticates the user SHALL also carry the Gmail and Calendar scopes that JakeOS needs for capabilities #4 and #6. There MUST be only one consent flow, not two.

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

## Locked decisions (from design.md)

- Q3 = iii (Google OAuth-to-self). All requirements above implement this choice.
