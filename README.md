# zebra_ble_printer

Print ZPL over Bluetooth LE on Zebra printers from Flutter (Android and iOS),
**without the Zebra SDK**. Tested on a **ZD410**.

> Unofficial. Not affiliated with, endorsed by or supported by Zebra
> Technologies. "Zebra" and "ZD410" are trademarks of their owners.

## How it works

Zebra's application note
[Link-OS Environment Bluetooth Low Energy](https://www.zebra.com/content/dam/support-dam/en/documentation/unrestricted/application-notes/AppNote-BlueToothLE-v4.pdf)
describes the *Zebra Bluetooth LE Parser Service*, a small GATT service that
works like a serial port towards the printer's parser:

| UUID | Role |
|---|---|
| `38eb4a80-c570-11e3-9507-0002a5d5c51b` | Service |
| `38eb4a82-c570-11e3-9507-0002a5d5c51b` | "To Printer Data": write ZPL/SGD here |
| `38eb4a81-c570-11e3-9507-0002a5d5c51b` | "From Printer Data": replies via indications |

Zebra has no SDK for BLE on iOS and points to a CoreBluetooth sample instead,
so a plain BLE library is the way to go. This package does that in a few
hundred lines on top of [`universal_ble`](https://pub.dev/packages/universal_ble):
scan, connect, negotiate the MTU, find `38eb4a82` and write to it in chunks
that fit the MTU, always with response.

On the author's ZD410 the writable characteristic that prints is exactly
`38eb4a82-c570-11e3-9507-0002a5d5c51b`. The application note was written for
the ZQ500 series; for other models, check the table below.

If a printer doesn't expose that characteristic, the package can fall back to
a user-confirmed test print on each writable vendor characteristic (see
"Fallback" below).

## Compatibility

| Printer | Platform | Status |
|---|---|---|
| ZD410 | Android | Printing works (author's test) |
| ZD410 | iOS | Not tested with this package yet |
| Other models | any | Unknown. Reports welcome |

Tried it on your printer? Please open a *Printer compatibility report* issue.

## Usage

You need a `BlePrinterStore` to remember the printer between launches.
`InMemoryBlePrinterStore` is provided for tests; the `example/` app shows a
`SharedPreferences`-backed one.

```dart
final printer = ZebraBlePrinter(MyStore()); // implements BlePrinterStore

// First time: pick the printer
final devices = await printer.scan();
final zebra = devices.firstWhere(ZebraBle.looksLikeZebra);
await printer.connect(zebra);
await printer.printZpl(Zpl.textLabel('Hello'));

// Every other launch
if (await printer.reconnect()) {
  await printer.printZpl(Zpl.textLabel('Hello again'));
}
```

`reconnect` scans until the saved printer shows up (up to 8 s) and returns
`false` if none is saved or it isn't nearby.

`printZpl` calls are queued, so printing from several places at once is safe.
Listen to `printer.onDisconnected` to react when the printer switches off or
goes out of range, and call `printer.dispose()` when you are done with it.

The `example/` app is a ready-made setup wizard you can copy; its README also
explains how to run it on an iPhone.

### Fallback: unknown characteristic

```dart
await printer.connect(
  device,
  confirmProbe: (d) async => await askUser('Send a test label to ${d.name}?'),
  confirm: (uuid) async => await askUser('Did a label print? ($uuid)'),
);
```

Used only when the documented characteristic isn't there. Nothing is written
to the device unless `confirmProbe` returns true; standard Bluetooth services
are skipped; the first characteristic you confirm is saved. If you don't pass
the callbacks, `connect` never probes and throws
`NoPrintCharacteristicException`.

### Building labels

- `Zpl.textLabel(text)`: one-line label; text is escaped and sent as UTF-8.
- `Zpl.escape(text)`: escapes user input for a `^FD` field preceded by `^FH_`.
- Test labels: `Zpl.testText`, `Zpl.testBox` (print area and margins),
  `Zpl.testBarcode` (darkness), `Zpl.testAccents` (UTF-8: if accents come out
  wrong, your firmware doesn't support `^CI28`).

## Setup

The app handles permissions and turning the Bluetooth adapter on.

- **iOS** (14.0 or later): add `NSBluetoothAlwaysUsageDescription` to
  `Info.plist`. The system asks for the permission at the first scan. The
  simulator has no Bluetooth: test on a real device.
- **Android** (API 21 or later, as required by `universal_ble`; the example is
  built for API 24): `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` on Android 12+,
  plus location (and the legacy `BLUETOOTH` / `BLUETOOTH_ADMIN`) below that.
- **Printer**: Bluetooth LE must be enabled (`bluetooth.le.controller_mode`
  `le` or `both`).

## Known limitations

- **No printer status.** It doesn't read the printer's replies (paper out,
  errors). Zebra's note describes how, via indications on `38eb4a81`; not
  implemented yet.
- **No automatic reconnection.** If the printer switches off, `isReady`
  becomes false and `onDisconnected` emits; call `reconnect()` to get back.
  Zebra also reports some newer iOS devices disconnecting from newer printers
  after about 60 seconds.
- **Slow.** BLE is slow; Zebra's note benchmarks about 80 bytes per second
  (2014 figure). Avoid big graphics.
- **ZPL text only**, Android and iOS only.

## Security notes

- **BLE is not encrypted by default.** `bluetooth.le.minimum_security`
  defaults to `none` on the printer, so label contents may travel in clear.
  Set it higher on the printer if that matters. On Android a saved printer is
  recognized by its MAC address only.
- **Escape user text.** `^` and `~` start ZPL commands, which can change
  printer settings. Use `Zpl.textLabel` / `Zpl.escape`.
- **The fallback writes to the device you pick.** That's why `confirmProbe`
  exists: show the device name and let the user decide.

## Dependencies

The only runtime dependency is
[`universal_ble`](https://pub.dev/packages/universal_ble) (BSD-3-Clause).

## License

MIT, see [LICENSE](LICENSE).
