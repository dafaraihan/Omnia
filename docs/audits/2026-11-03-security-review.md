# Security review — 2026-11-03

Dafa's round of Nov 3, item 11: credentials, account and user data. This is a source review plus client changes. It is not a penetration test. No Supabase function, RLS rule, secret or deploy was changed. The client changes built on all platforms, and none were exercised signed in, because I can't sign in to the account.

## Fixed

| Finding | Risk | Change |
|---|---|---|
| Sign Out used the SDK's global scope, `OmniaAccount.swift` | One device signing out ended the session on every other device | Local scope only |
| `omnia://addon-install` installed an add-on with no prompt, `OmniaApp.swift` | Any web page or message could add an add-on, which then sees what you browse and supplies what plays | Asks first and names the host |
| Sign-in session used the SDK's `AfterFirstUnlock` class, `Keychain.swift` in supabase-swift | An encrypted device backup could carry the session to another device | Device-only Keychain items, with existing sessions moved across so nobody is signed out |
| Add-on links copied to the general clipboard, `AddonsSettingsView.swift`, `AddonDetailView.swift` | These links can hold tokens; Universal Clipboard sends them to other devices | iOS: this device only, gone after 2 minutes. Mac: marked concealed for clipboard managers |
| `URLSession.shared` for a TMDB call with `api_key` in the URL, plus plugin downloads, badge imports, Live TV DNS and subtitle fetches | The URL could stay in the on-disk cache, and cookies were stored | New no-store session, no cookies, TLS 1.2 or later |
| Animated covers fetched any scheme at any size, `CollectionViews.swift` | Untrusted collection files controlled the URL | HTTPS only, 32 MB limit, no cookies |
| Plugin log text at `privacy: .public`, `PluginRuntime.swift` | Plugin messages can contain URLs and keys, visible in device logs | Private |
| Stream links in preferences, `StreamLinkCache.swift` | A link can hold a provider token in its path, and preferences go into backups | Protected file excluded from backups; old entries move across |
| Scene frames and the failure log survived Sign Out | Shows what was watched to the next person on the device | Cleared at sign-out |
| PIN lockout reset when the app was quit, `ProfileStore.swift` | Unlimited guesses at a 4-digit PIN by relaunching | Lockout now survives a relaunch |
| Auth callback accepted any `omnia://` address, `OmniaAccount.swift` | Unrelated links reached the auth code | Only `omnia://auth-callback` |
| A session ending by itself cleared credentials and said nothing | Silent loss, and account data looked synced | See commit `7dccdea` |

## Checked and fine

- ATS: only local networking is excepted. Live TV's plain HTTP is a deliberate, scoped path (`LiveTVModels.swift:159-168`).
- Login CSRF: the app uses the PKCE flow, and the SDK refuses a callback without a matching code verifier.
- AniList sign-in: the token is only accepted while a connect is waiting, and it is validated first (`TrackerAccountStore.swift:131`).
- Credential vault: AES-GCM per account, key in Keychain, excluded from backup, `0600` files, no redirects, no cache (`CredentialVaultDiskStore.swift`, `CredentialVaultClient.swift`).
- Keychain items on iOS are device-only (`KeychainStore.swift:31`).
- Failure log strips URLs down to hosts (`PlaybackFailureLog.swift`).
- Mac: App Sandbox and Hardened Runtime are on, with only network client and user-selected read-only files (`Omnia.entitlements`).
- No secrets in the repo tree: `Config/Secrets.xcconfig` and `NativePlayback.xcconfig` are git-ignored.

## Left, with reasons

| Item | Why not done now |
|---|---|
| Plugins fetch with cookies on (`PluginRuntime.swift:144`) | Ephemeral per run, and scrapers need them |
| 4-digit PIN hashed with salted SHA-256 | Changing the hash changes the vault format; it needs a migration. The lockout is the main defence |
| Add-on manifest URLs stored in profile sync | Needed to sync add-ons; protected by RLS. Worth moving to the vault later |

## Needs your decision (server side, nothing changed)

- Supabase Auth settings aren't visible from this repo: refresh token reuse interval and session timebox. Worth checking, since they affect how often sessions end on their own.
- Mac builds are development signed and not notarized, so Gatekeeper warns on other Macs.
