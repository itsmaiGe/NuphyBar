# Security policy

## Supported version

Security fixes are applied to the latest NuphyBar Release.

## Reporting

Do not post private Agent configuration, local paths, session identifiers, or crash logs containing personal data in a public issue. Contact the maintainer through [X](https://x.com/unflwMaige) first and provide only the minimum reproduction details.

## Data boundary

NuphyBar is local-only:

- it does not read or store keystrokes;
- it does not send prompts or responses to another service;
- Agent hooks record only provider, coarse lifecycle status, local session identifier, and timestamp;
- the app sends a two-byte HID output report to a locally connected NuPhy BLE keyboard;
- no analytics or telemetry service is bundled.

macOS labels the required HID capability as Input Monitoring even though NuphyBar only writes an output report. Permission can be removed at any time in System Settings → Privacy & Security → Input Monitoring.

## Firmware safety

Firmware is hardware-specific. The current binary supports only NuPhy Air60 V2 ANSI. Confirm the exact model, export VIA configuration, keep the official recovery image, verify SHA-256, and use a stable USB connection before flashing.

The Air60 V2 builder rejects an unexpected official baseline and the verifier rejects any change outside the audited call site and appended hook. Never disable these checks to make a new firmware version build.
