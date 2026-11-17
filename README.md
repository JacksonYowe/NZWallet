# NZWallet

**Unofficial test prototype. This app does not issue valid government identification, is not an official government app, and is not endorsed by the New Zealand Government.** All bundled licence data is fictional. The portrait and signature contain TEST text. Do not present this app as identification.

`v1.0` is a release of this demonstration, not a production or government-certified release.

NZWallet is a native SwiftUI iPhone prototype exploring a licence wallet, bilingual screens, selective disclosure and experimental mobile driving-licence sharing. It has no connected government database or production issuer.

## Run in the iPhone simulator

Requires a Mac and Xcode. The deployment target is iOS 17.0; this release was built with Xcode 27.2 and the iOS 27.2 SDK. The source uses newer SDK APIs behind availability checks, so an old Xcode installation may not compile it. No Swift package dependencies are required.

1. Clone/download this repository.
2. Open `NZWallet.xcodeproj` in Xcode.
3. Select the **NZWallet** scheme and an iPhone simulator.
4. Build and Run. Complete simulated device authentication when unlocking. The app deliberately denies access when device-owner authentication is unavailable; configure a supported simulator authentication session or use a secured iPhone. There is no demo-unlock argument.

This is an iOS app; it does not run in an Android emulator.

To regenerate the included project after adding/renaming files, install [XcodeGen](https://github.com/yonaskolb/XcodeGen), then run in the repository root:

```sh
xcodegen generate
```

The generated project and shared scheme are included, so regeneration is not necessary for a normal first build.

## Run on an iPhone

Open **Signing & Capabilities**, select your own development team and choose a unique bundle identifier. Connect the iPhone and build/install using Xcode. No signing certificates, provisioning profiles, personal team identifiers or account credentials are supplied.

The phone must support device-owner authentication (Face ID, Touch ID or passcode). The app relocks on app switching and covers the app-switcher snapshot. Authentication alone does not establish government identity.

## Change the fictional data and images

All three editable demo files are in **`TEST FILES CHANGE FOR DEPLOYMENT/`**:

- `TEST_FILE_ONLY.swift`: edit `DemoLicenceData.current` for names, licence/card numbers, DOB, dates, classes and endorsements.
- `demo-portrait.jpg`: bundled fictional portrait, recommended 600 × 800 pixels.
- `demo-signature.png`: bundled TEST signature, recommended 600 × 180 pixels; transparent PNG preferred.

Image size/format requirements are documented above the settings in the Swift file. Keep the current image filenames, rebuild and reinstall after replacement. The loader supports bundled filenames and readable local paths; it does not fetch remote API URLs. Replacement images are not automatically stamped: keep any public demo unmistakably fictional and marked TEST.

The licence age badge compares the fictional DOB with the device's local date. It is a display feature, not independently verified proof of age. The kōwhai foil responds to device tilt; simulator motion is an automatic visual preview. The stars repeat a slow ordered fade and restart on tap. Reduce Motion keeps a gentler opacity/colour response.

## Run the core tests

```sh
./Tests/run.sh
```

Run on macOS with Xcode command-line tools. The script builds in a temporary directory and removes its output. It covers internal protocol/verification behaviour, forged/untrusted credentials, replay, expiry, image loading, age boundaries, lock state, tilt mapping and star timing. These are prototype checks, not certification or a security audit. They do not test the physical motion sensor, Face ID hardware or real-device Bluetooth interoperability.

## Connect an API

See [docs/API_INTEGRATION.md](docs/API_INTEGRATION.md) for the proposed client structure, field contract, authenticated image retrieval and issuer integration.

**Connecting a JSON database endpoint does not turn this demo into an official credential.** Production needs an authorised issuer, verified signed credentials, device binding, trusted issuer configuration, status/revocation handling, protected storage and independent review. Issuer private keys must remain on the server.

## Current limits

- No government login, production API, payment or submission backend.
- Service screens do not submit applications, make bookings or take payments.
- The issuer and trust setup are local test implementations; the device can generate demo credentials.
- Developer/checker/attack-simulation code remains in source even though its UI entry points are hidden.
- Real two-phone Bluetooth and cross-vendor acceptance are not established by the included tests.
- The existing te reo Māori translation is a machine draft requiring fluent review.
- This is not hardened or approved for handling real identity data.

## Licence

Original project source, documentation and original graphics are licensed under **GNU GPL version 3 only** (`GPL-3.0-only`); see [LICENSE](LICENSE). The software is provided without warranty.

The bundled **Public Sans** font files remain under their separately included [SIL Open Font License 1.1](Resources/Fonts/PublicSans-OFL.txt). That font licence is retained and is not replaced by GPLv3. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Names and references to government services do not imply affiliation or endorsement.
