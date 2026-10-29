import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart'
    show BleCharacteristic, BleService, CharacteristicProperty;
import 'package:zebra_ble_printer/zebra_ble_printer.dart';

void main() {
  test('splitIntoChunks splits and reassembles the data', () {
    final data = List.generate(50, (i) => i);
    final chunks = splitIntoChunks(data, 20);
    expect(chunks.map((c) => c.length), [20, 20, 10]);
    expect(chunks.expand((c) => c).toList(), data);
  });

  test('InMemoryBlePrinterStore replaces the same remoteId', () async {
    final store = InMemoryBlePrinterStore();
    await store.save(const SavedBlePrinter(
        remoteId: 'a', serviceUuid: 's', characteristicUuid: '1'));
    await store.save(const SavedBlePrinter(
        remoteId: 'a', serviceUuid: 's', characteristicUuid: '2'));
    final all = await store.getAll();
    expect(all.length, 1);
    expect(all.single.characteristicUuid, '2');
  });

  test('isStandardGattUuid recognizes only Bluetooth SIG UUIDs', () {
    expect(isStandardGattUuid('00001800-0000-1000-8000-00805f9b34fb'), isTrue);
    expect(isStandardGattUuid('0000180A-0000-1000-8000-00805F9B34FB'), isTrue);
    expect(isStandardGattUuid('38eb4a80-c570-11e3-9507-0002a5d5c51b'), isFalse);
  });

  test('Zpl.escape neutralizes ZPL command characters', () {
    final escaped = Zpl.escape('a^b~c_d');
    expect(escaped, 'a_5Eb_7Ec_5Fd');
    expect(escaped.contains('^'), isFalse);
    expect(escaped.contains('~'), isFalse);
  });

  test('Zpl.textLabel escapes the text and enables hex escapes', () {
    final zpl = Zpl.textLabel('x^FS');
    expect(zpl, contains('^FH_^FDx_5EFS^FS'));
    expect(zpl.startsWith('^XA'), isTrue);
    expect(zpl.endsWith('^XZ'), isTrue);
  });

  group('ZebraBle', () {
    BleService svc(String uuid, Map<String, List<CharacteristicProperty>> cs) =>
        BleService(uuid, [
          for (final e in cs.entries) BleCharacteristic(e.key, e.value, []),
        ]);

    test('findPrintTarget finds the writable To Printer Data', () {
      final target = ZebraBle.findPrintTarget([
        svc('1800', {'2a00': [CharacteristicProperty.read]}),
        svc(ZebraBle.parserService, {
          ZebraBle.fromPrinterData: [CharacteristicProperty.indicate],
          ZebraBle.toPrinterData: [CharacteristicProperty.write],
        }),
      ]);
      expect(target?.service, ZebraBle.parserService);
      expect(target?.characteristic, ZebraBle.toPrinterData);
    });

    test('findPrintTarget ignores it when it is not writable or absent', () {
      expect(
          ZebraBle.findPrintTarget([
            svc(ZebraBle.parserService,
                {ZebraBle.toPrinterData: [CharacteristicProperty.read]}),
          ]),
          isNull);
      expect(ZebraBle.findPrintTarget([]), isNull);
    });

    test('looksLikeZebra uses advertised services and name', () {
      expect(
          ZebraBle.looksLikeZebra(BleDevice(
              deviceId: 'a', name: null, services: [ZebraBle.parserService])),
          isTrue);
      expect(
          ZebraBle.looksLikeZebra(BleDevice(deviceId: 'a', name: 'ZD410-203')),
          isTrue);
      expect(
          ZebraBle.looksLikeZebra(BleDevice(deviceId: 'a', name: 'Lamp')),
          isFalse);
    });
  });

  test('SavedBlePrinter survives a JSON round trip', () {
    const printer = SavedBlePrinter(
        remoteId: 'a', serviceUuid: 's', characteristicUuid: 'c');
    final copy = SavedBlePrinter.fromJson(printer.toJson());
    expect(copy.remoteId, 'a');
    expect(copy.serviceUuid, 's');
    expect(copy.characteristicUuid, 'c');
  });
}
