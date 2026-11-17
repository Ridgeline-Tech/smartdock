# Smart Dock signing and CI candidate

This fork's package is `construction.ridgeline.smartdock`, starting at
versionName `1.15.0-ridgeline.1` and versionCode `1151`. The user-facing name
remains Smart Dock. The `cu.axel.smartdock` Kotlin/Java namespace is retained.

## Dedicated identity: Zac's interactive step

On Zac's trusted Windows account, with JDK 17 and PowerShell 7 available, run
these commands from the fork repository after reviewing the source and PR:

```powershell
pwsh -NoProfile -File .\scripts\Initialize-ReleaseIdentity.ps1
pwsh -NoProfile -File .\scripts\Upload-CISecrets.ps1
```

The first command prompts Zac twice for a recovery passphrase of at least 16
characters. Only Zac enters it; never paste it into chat, GitHub, CI, a command
argument or a file. The script refuses to overwrite an existing identity,
generates random operational passwords and a dedicated 4096-bit RSA PKCS12
key, and creates the permanent keystore, encrypted recovery, public certificate
and identity record under Zac's OneDrive `ZacsApps/Release Identity/SmartDock`
directory. It protects the private files with owner-only ACLs. A separate
DPAPI CurrentUser record is stored under `%LOCALAPPDATA%/SmartDock/signing`.
The passphrase is needed for later recovery, not routine builds.

The second command, run by the same Windows user, reads only that protected
record and sends five values through GitHub CLI standard input to this fork's
repository-level Actions secrets. It does not print secret values or put them
in command arguments. The secrets are:

- `SMART_DOCK_RELEASE_KEYSTORE_BASE64`
- `SMART_DOCK_RELEASE_STORE_PASSWORD`
- `SMART_DOCK_RELEASE_KEY_ALIAS`
- `SMART_DOCK_RELEASE_KEY_PASSWORD`
- `SMART_DOCK_RELEASE_CERT_SHA256`

GitHub then holds a copy of the dedicated key and passwords. No Zac's Apps
Store key, upstream key, or debug key is reused. Keep the recovery passphrase
outside the repository and GitHub. Before using the signed candidate, compare
the public certificate SHA-256 printed by the initializer with the CI
verification output.

## CI behavior

Pull requests run a release-signing exercise using a one-day throwaway key
generated on the runner. It is never committed, pinned or uploaded. This checks
the wiring but is not a production identity.

The `Signed APK candidate` workflow's manual `workflow_dispatch` job uses the
five dedicated secrets. Missing secrets fail before building; Gradle has no
debug or unsigned release fallback. CI independently verifies the APK with
`apksigner` and `aapt2`: one expected signer, package, versionCode,
versionName and minSdk 30. It prints the APK SHA-256 and retains only the APK
and its `.sha256` file as a seven-day workflow artifact. The runner deletes
its temporary keystore even when the job fails.

No workflow creates a GitHub Release, release tag, Zac's Apps catalog row,
deployment or device installation. Publishing a signed release requires a
separate decision. For each eventual distributed APK, pair the exact source
revision and Ridgeline changes with the binary under [GPL-3.0](LICENSE).
