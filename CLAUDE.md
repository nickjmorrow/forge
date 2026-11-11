# Forge

This repo is public: tests, fixtures, sample data, docs and comments must be generic, with no personal data (real names, personal media or reading lists, calendars, health, money, machine names).


- Installing the iPhone app on a device:

  ```bash
  cd App && xcodebuild -project Forge.xcodeproj -scheme ForgeiOS -configuration Release -destination 'generic/platform=iOS' -derivedDataPath ../build-device.noindex build
  xcrun devicectl device install app --device <iphone-id> ../build-device.noindex/Build/Products/Release-iphoneos/Forge.app
  ```
- Build, test and hub setup: `README.md` and `docs/hub.md`.
- Machine-specific and personal details (device ids, hosts, deploy habits) live in the gitignored `CLAUDE.local.md`.
