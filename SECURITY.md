# Repository security and privacy

Dayvera is designed as a local-first iPhone app. It has no account system, analytics SDK, advertising SDK, or app-managed server. Apple Health and workout records are not sent with exercise-catalog requests.

## Never commit

- Apple signing certificates, private keys, provisioning profiles, App Store Connect keys, or local signing configuration
- `.env` files, tokens, passwords, API keys, or credential-bearing URLs
- Apple Health exports, local app databases, workout exports, crash logs, or Xcode result bundles
- `.zvec-grep`, DerivedData, archives, IPAs, dSYMs, simulator identifiers, or device-specific diagnostics
- Screenshots containing real Health, Calendar, device, account, or notification data

The root `.gitignore` covers the expected forms of these artifacts. Before each public milestone, inspect the staged diff and reachable Git objects rather than relying on ignore rules alone.

## Release checks

```sh
git status --short
git diff --cached --check
git ls-files | rg '(\.env|\.p8|\.p12|\.pem|\.mobileprovision|\.xcresult|HealthExport|export\.xml|\.zvec-grep)'
git rev-list --objects --all | rg ' \.zvec-grep/'
rg -n --hidden -g '!.git/**' -g '!.zvec-grep/**' '(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|Bearer [A-Za-z0-9._-]+|AKIA[0-9A-Z]{16})' .
rg -a -l '/Users/' /path/to/Dayvera.xcarchive/Products/Applications/Dayvera.app/Dayvera
```

The repository scans and final archive scan should return no matches. A clean result does not replace provider-side secret scanning or rotation if a real credential is ever committed. Keep the archive and its dSYM outside the repository; the dSYM is expected to retain source information for crash symbolication.

`Scripts/check_repository_hygiene.sh` enforces the same high-confidence checks locally and in GitHub Actions. The workflow uses the official checkout action pinned to the reviewed v7.0.1 commit and scans both the current tree and reachable commit history.

## Local-data protection

Workout history, health-source preferences, Health setup state, active drafts, and applied schedule status are sandboxed locally in backup-excluded Application Support. Core Data uses complete-until-first-authentication protection by default; Dayvera also requests that protection explicitly for its private-state JSON so background launches can read app state after the first device unlock following a reboot. The active-workout draft file separately uses complete file protection. Only nonsensitive interface setup flags and opaque app-owned Calendar/Alarm identifiers normally remain in UserDefaults; legacy health-adjacent payloads are removed only after their protected migration succeeds. The app does not configure SwiftData cloud sync. `PrivacyInfo.xcprivacy` is bundled with the app and declares no tracking or developer-collected data plus the required reasons for UserDefaults and file-timestamp access. Signed file protection, backup exclusion, locked-device behavior, privacy declarations, and migration behavior must be reverified on a physical device for each production release.

Report a suspected vulnerability privately to the repository owner. Do not open a public issue containing secrets, personal health data, device identifiers, or reproducible user data.
