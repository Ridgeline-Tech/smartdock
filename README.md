<div align="center">
  <h1>Smart Dock</h1>
  A user-friendly desktop mode launcher that offers a modern and customizable user interface
</div>

> **Ridgeline-Tech fork notice (2026-11-17):** This GPL-3.0 fork is based on
> [axel358/smartdock 1.15.0](https://github.com/axel358/smartdock/tree/517604a72745a1c440068b89b3f42c8248abab36).
> Its Android application ID is `construction.ridgeline.smartdock`, separate from
> the upstream F-Droid app. The user-facing name remains Smart Dock. See
> [NOTICE.md](NOTICE.md) for attribution and the dated Ridgeline changes.
> Signing custody and the unpublished CI candidate path are in [RELEASE.md](RELEASE.md).

![Screenshot](fastlane/metadata/android/en-US/images/phoneScreenshots/1.png)

## Main features
- Very customizable, icons, colors, shapes, sounds
- Multi window support
- Keyboard shortcuts
- Support for both desktop and tablet layouts
- Compatible with Android 11 and above (minSdk 30); root is not required for normal use

## Upstream installation

[<img src="https://fdroid.gitlab.io/artwork/badge/get-it-on.png"
    alt="Get it on F-Droid"
    height="80">](https://f-droid.org/packages/cu.axel.smartdock)

This F-Droid link installs the upstream `cu.axel.smartdock` edition, not the
Ridgeline fork. No Ridgeline APK release has been published yet. The two package
IDs can coexist, but each has its own settings and permission grants.

Some privileged features require system-app access or
[Shizuku](https://shizuku.rikka.app). These are optional advanced paths;
ordinary app use and selection as the default
HOME app remain user controlled. The Ridgeline fork does not switch HOME or
grant privileged permissions during installation. In Advanced Preferences,
granting secure-settings access with root requires an explicit confirmation.

## Usage

### Grant restricted permissions: 
On some devices Accessibility and Notification permissions might not be available. To solve this go to:  System Settings > Apps > Smartdock > 3 Dot menu (Top right corner) > Allow restricted permissions

### Secure settings
To grant secure settings permissions run the following command on an adb or root shell:
```
pm grant construction.ridgeline.smartdock android.permission.WRITE_SECURE_SETTINGS
```

### Hide navigation bar
You might also want to hide the Android navigation bar.
[See hiding navigation bar](HideNav.md)

## Get help and ask questions 

Telegram support group: https://t.me/smartdock358

## Support the project

If you find this project useful or it has helped you in any way, consider showing your appreciation and supporting its ongoing development. 

Bitcoin Address:
```
bc1qzc0jnpzk4g838t56jshvt4j5a2a5dgfx5w9k5a
```

Thank you for your support!

## Contributors

[See contributors](Contributors.md)
