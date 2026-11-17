# Smart Dock: attribution and Ridgeline changes

This repository is a fork of [Smart Dock by Axel358](https://github.com/axel358/smartdock)
at tag `1.15.0`, commit `517604a72745a1c440068b89b3f42c8248abab36`.
The original project, contributors and copyright notices remain attributed in
the source tree and [Contributors.md](Contributors.md). The complete
[GNU GPL version 3 license](LICENSE) remains in force for this fork.

## Ridgeline-Tech changes, 2026-11-17

- Keep the Smart Dock display name and `cu.axel.smartdock` code namespace while
  using the distinct Android application ID `construction.ridgeline.smartdock`.
- Start fork versions at `1.15.0-ridgeline.1` / versionCode `1151`.
- Use the installed package for accessibility-service and root/ADB permission
  handling; preserve other enabled accessibility services when toggling this one.
- Require a user action and confirmation before a root grant of
  `WRITE_SECURE_SETTINGS` instead of attempting that grant on opening settings.
- Add a dedicated release-signing and CI verification path. No release APK or
  signing certificate is published by this source change.

Every future distributed APK must be paired with its exact corresponding source
revision and any later changes, under GPL-3.0.
