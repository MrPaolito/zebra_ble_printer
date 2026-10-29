import 'package:universal_ble/universal_ble.dart';

/// The Zebra Bluetooth LE Parser Service, as documented in Zebra's application
/// note "Link-OS Environment Bluetooth Low Energy": a minimal GATT service that
/// works like a serial port towards the printer's parser (ZPL and SGD).
class ZebraBle {
  ZebraBle._();

  static const parserService = '38eb4a80-c570-11e3-9507-0002a5d5c51b';

  /// Printer to app (read via indications). Not used for printing.
  static const fromPrinterData = '38eb4a81-c570-11e3-9507-0002a5d5c51b';

  /// App to printer: where ZPL is written.
  static const toPrinterData = '38eb4a82-c570-11e3-9507-0002a5d5c51b';

  /// 16-bit service UUID (0xFE79) that Zebra printers advertise, as used for
  /// the scan filter in a third-party example. Not from Zebra's own docs.
  static const advertisedService = '0000fe79-0000-1000-8000-00805f9b34fb';

  /// Whether an advertisement looks like a Zebra printer: advertises one of the
  /// Zebra services, or has "zebra" / "zd" in its name. Only a hint: the name
  /// defaults to the printer's serial number and can be changed.
  static bool looksLikeZebra(BleDevice device) {
    final services = device.services.map((s) => s.toLowerCase());
    if (services.contains(parserService) ||
        services.contains(advertisedService)) {
      return true;
    }
    final name = (device.name ?? '').toLowerCase();
    return name.contains('zebra') || name.startsWith('zd');
  }

  /// Finds the writable [toPrinterData] characteristic among [services].
  static ({String service, String characteristic})? findPrintTarget(
      List<BleService> services) {
    for (final s in services) {
      for (final c in s.characteristics) {
        if (c.uuid.toLowerCase() == toPrinterData &&
            c.properties.contains(CharacteristicProperty.write)) {
          return (service: s.uuid, characteristic: c.uuid);
        }
      }
    }
    return null;
  }
}
