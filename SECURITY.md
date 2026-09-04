# Repository security and privacy

Sleep Coach is designed as a local-first iPhone app. It has no account system, analytics SDK, advertising SDK, or application server. Apple Health and workout records are not sent with exercise-catalog requests.

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
```

The two `rg` commands should return no matches. A clean result does not replace provider-side secret scanning or rotation if a real credential is ever committed.

`Scripts/check_repository_hygiene.sh` enforces the same high-confidence checks locally and in GitHub Actions. The workflow uses the official checkout action pinned to the reviewed v7.0.1 commit and checks full reachable history.

## Local-data hardening before production

Workout history, active drafts, and applied schedule status are sandboxed locally. Before an App Store release, explicitly choose and test the iOS Data Protection class and backup behavior for the SwiftData store, its SQLite sidecars, and draft/status persistence. This is a release-hardening requirement, not evidence of a credential leak.

Report a suspected vulnerability privately to the repository owner. Do not open a public issue containing secrets, personal health data, device identifiers, or reproducible user data.
