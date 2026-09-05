# External TestFlight preparation

This guide prepares Dayvera for external beta testing. It does not automate signing or submission and does not indicate that a TestFlight build has been uploaded.

## Identity and prerequisites

Dayvera currently retains the bundle identifier `com.momoai.personalassistant.sleepcoach` so existing installations, HealthKit workout sync identifiers, Calendar ownership receipts, alarm ownership, and local app-container data remain continuous. Changing that identifier creates a different app identity and requires a separate migration and App Store Connect record.

The checked-in candidate is marketing version **1.0**, build **2**. Increase the build number before every later upload.

Before archiving, the release owner needs:

- active Apple Developer Program membership;
- access to the matching identifier and signing team in Certificates, Identifiers & Profiles;
- an App Store Connect app record named Dayvera using the retained bundle identifier;
- an App Store distribution certificate and App Store provisioning profile, or working Xcode automatic signing;
- App Store Connect access to upload builds, plus Account Holder, Admin, or App Manager access to create and manage external testing groups;
- Xcode 27 with the iOS 27 SDK;
- unique marketing version and build numbers for every upload.

The public project intentionally leaves `DEVELOPMENT_TEAM` empty. Select the correct team locally or in secured CI. Never commit certificates, private keys, provisioning profiles, App Store Connect API keys, team IDs, device IDs, or account credentials.

## Continuous integration boundary

The repository workflow at `.github/workflows/ios.yml` uses GitHub's official `xcode-27` arm64 runner image to build and test the unsigned simulator app. That runner is currently published as a public preview, so availability and installed image details should be checked before treating it as a release gate: [Xcode 27 runner announcement](https://github.blog/changelog/2026-07-16-xcode-27-runner-image-now-in-public-preview/) and [current runner image](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md).

CI intentionally has no signing identity and cannot archive, upload, submit for beta review, or invite testers. Those steps require the Apple Developer and App Store Connect prerequisites above.

## Release acceptance before archive

1. Run the complete unit/integration suite with production source and Xcode 27.
2. Build the unsigned Release configuration to catch configuration-only failures.
3. Install a signed Release candidate on a supported iPhone.
4. Verify first launch and upgrade from the existing retained-bundle-ID installation.
5. Exercise real HealthKit authorization and source attribution, Calendar destination review/write/Undo, and an approved AlarmKit wake alarm.
6. Verify camera permission, photo-library selection, Apple Intelligence availability states, real food suggestions, catalog matching, portion editing, meal save, and manual fallback.
7. Review Plan manual editing, optional request-scoped suggestion, before/after review, final Apply confirmation, and external-deletion receipt reconciliation.
8. Review all four workout modalities, equipment filtering, beginner/intermediate/advanced levels, active-draft recovery, completion, and Progress history.
9. Inspect Light and Dark Mode, Accessibility Extra Large, VoiceOver, Increase Contrast, and Reduce Motion on representative screens.
10. Confirm screenshots, privacy copy, support contact, nutrition evidence, acknowledgements, and third-party notices are current.

Simulator fixtures do not certify wearable data accuracy, system permission sheets, alarm delivery, camera behavior, or on-device model quality.

## App Store Connect preparation

Complete these items before inviting external testers:

- app description, category, support URL, privacy-policy URL, copyright, and age rating;
- App Privacy answers that match `PRIVACY.md` and the privacy manifest;
- export-compliance answers based on the shipped binary and Apple's current questions;
- Test Information with a concise description of the beta's purpose, a feedback email, and focused testing notes;
- beta App Review contact information and any review instructions needed to reach deterministic/demo states;
- an external tester group with intentional invitation scope.

Apple's current references: [distribution from Xcode](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases), [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview), [registering an App ID](https://developer.apple.com/help/account/identifiers/register-an-app-id), and [inviting external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers).

Dayvera has no account or app-managed backend. Do not provide fictional credentials. Explain that Health, Calendar, Alarm, camera, and Apple Intelligence behavior depends on device capability and user permission, and that manual nutrition entry remains available.

## Archive and upload

1. In Xcode 27, select **Any iOS Device (arm64)** and the Dayvera scheme.
2. Confirm Release signing, retained bundle identifier, version, build number, entitlements, app icon, and launch screen.
3. Choose **Product → Archive**.
4. In Organizer, run **Validate App** and resolve every signing, entitlement, privacy, or asset issue.
5. Choose **Distribute App → App Store Connect → Upload**.
6. Wait for App Store Connect processing, then review the processed build for missing compliance or metadata prompts.
7. Create an internal group if the app does not already have one, add the build, and complete a short smoke test. App Store Connect requires an internal group before the first external group.
8. Attach the build to the external group, complete Beta App Review information, and submit it for beta review.

External TestFlight testing requires Apple's beta review. Processing and review status must be confirmed in App Store Connect before invitations are treated as active.

## Suggested external beta scope

Ask testers to report the device model, iOS version, enabled data sources, and the exact screen/action involved without sending screenshots that expose private health data unless they intentionally redact it.

Prioritize feedback on:

- whether Today makes the next decision obvious;
- whether Plan makes every future system change clear before Apply;
- whether workout type, level, equipment, and draft recovery behave predictably;
- whether photo suggestions reduce logging effort without appearing authoritative;
- whether quantities and meal history match how testers think about portions;
- whether Progress explains missing data, estimates, and source provenance;
- whether accessibility layouts remain readable and operable.

## Stop-ship conditions

Do not invite external testers if the Release build fails, the full suite is red, signing or entitlements differ from the reviewed archive, an app-owned Calendar/Alarm item cannot be safely reconciled or undone, meal edits can corrupt totals, active workout drafts can be overwritten, or production photo recognition bypasses catalog matching and review.
