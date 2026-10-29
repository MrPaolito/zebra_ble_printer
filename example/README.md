# zebra_ble_printer example

A setup wizard for the `zebra_ble_printer` package: permissions, scan, connect,
print.

1. **Permissions**: asks for the Bluetooth permissions (Android only; iOS asks
   when scanning starts). If a printer is already saved it reconnects and jumps
   to the last step.
2. **Find the printer**: lists nearby printers. The *Advanced* switch shows
   every BLE device, with their advertised services.
3. **Connect**: connects. Normally instant: the package finds Zebra's
   documented characteristic. Only if it isn't there, it asks for consent and
   runs a confirmed test print.
4. **Print**: edit the ZPL or pick a test label (text, box, barcode, accents).

## Run on Android

```
flutter pub get
flutter run
```

## Run on iPhone (needs a Mac with Xcode)

The iOS Simulator has **no Bluetooth**: use a real iPhone.

1. `flutter pub get`
2. Open `ios/Runner.xcworkspace` in Xcode (after the first `flutter run` or
   `flutter build ios --config-only`, so that CocoaPods is installed).
3. Runner target → *Signing & Capabilities*: pick your team and change the
   bundle identifier to something unique (the default is
   `com.example.zebraBlePrinterExample`).
4. On the iPhone: enable *Settings → Privacy & Security → Developer Mode*, and
   after the first install trust your developer certificate in *Settings →
   General → VPN & Device Management*.
5. `flutter run -d <your iPhone>`, then accept the Bluetooth prompt.

The minimum iOS version is 14.0 (`universal_ble` needs 13.1 or later).

## Before trying

- Switch the printer on and make sure Bluetooth LE is enabled
  (`bluetooth.le.controller_mode` = `le` or `both`).
- Close any other app connected to the printer (for instance Zebra's setup
  app): a BLE printer accepts one connection at a time.
- Put the phone close to the printer.

## What to report when you try on iOS

The compatibility table in the main README needs: printer model and firmware,
iOS version, and whether each of these worked: scan finds the printer,
connect, print, `reconnect` after closing the app, accents (*Accents* label),
and what happens when you switch the printer off during use.
