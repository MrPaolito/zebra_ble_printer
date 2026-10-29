import 'dart:async';
import 'dart:convert';

import 'package:universal_ble/universal_ble.dart';

import 'chunked_write.dart';
import 'printer_store.dart';
import 'saved_printer.dart';
import 'serial_queue.dart';
import 'zebra_ble.dart';
import 'zpl.dart';

/// Asks the user whether the test print on [characteristicUuid] came out.
typedef ConfirmTestPrint = Future<bool> Function(String characteristicUuid);

/// No print characteristic was found or confirmed.
class NoPrintCharacteristicException implements Exception {
  final String remoteId;
  const NoPrintCharacteristicException(this.remoteId);

  @override
  String toString() => 'No print characteristic found for $remoteId';
}

/// Asks the user whether it's OK to send test prints to [device] while looking
/// for the print characteristic.
typedef ConfirmProbe = Future<bool> Function(BleDevice device);

/// The user declined to send test prints to the device.
class ProbeDeclinedException implements Exception {
  final String remoteId;
  const ProbeDeclinedException(this.remoteId);

  @override
  String toString() => 'Test print declined for $remoteId';
}

/// Whether [uuid] is a Bluetooth SIG standard service/characteristic (16-bit
/// UUID on the Bluetooth base UUID): never a print channel.
bool isStandardGattUuid(String uuid) =>
    uuid.toLowerCase().endsWith('-0000-1000-8000-00805f9b34fb');

/// Handles a Zebra BLE printer.
///
/// Bluetooth/location permissions and turning the adapter on are up to the app.
class ZebraBlePrinter {
  ZebraBlePrinter(this.store);

  final BlePrinterStore store;

  static const testLabel = Zpl.testText;

  /// Minimum ATT MTU, used when the negotiation fails.
  static const _defaultMtu = 23;

  BleDevice? _device;
  ({String service, String characteristic})? _target;
  int _mtu = _defaultMtu;

  final _printQueue = SerialQueue();
  final _lost = StreamController<BleDevice>.broadcast();
  StreamSubscription<bool>? _connectionSub;

  BleDevice? get device => _device;
  bool get isReady => _device != null && _target != null;

  /// Emits the printer when the connection drops by itself (switched off, out
  /// of range). It is not emitted by [disconnect]. After it, [isReady] is false.
  Stream<BleDevice> get onDisconnected => _lost.stream;

  /// Scans for BLE devices for [timeout] and returns the ones found.
  Future<List<BleDevice>> scan(
      {Duration timeout = const Duration(seconds: 5)}) async {
    final found = <String, BleDevice>{};
    final sub = UniversalBle.scanStream.listen((d) => found[d.deviceId] = d);
    try {
      await UniversalBle.startScan();
      await Future<void>.delayed(timeout);
    } finally {
      // a failing stopScan must not hide the error that got us here
      try {
        await UniversalBle.stopScan();
      } catch (_) {}
      await sub.cancel();
    }
    return found.values.toList();
  }

  /// Connects [device] and finds the print characteristic.
  ///
  /// Looks for the print characteristic in this order:
  /// 1. the one saved in the store for this printer;
  /// 2. Zebra's documented [ZebraBle.toPrinterData], which is then saved;
  /// 3. only if both [confirmProbe] and [confirm] are given: asks
  ///    [confirmProbe] for permission, sends a test print to every writable
  ///    vendor characteristic (standard Bluetooth services are skipped) and
  ///    asks [confirm]; the first confirmed one is saved.
  ///
  /// Nothing is ever written to the device without a confirmed step 3.
  /// Throws [ProbeDeclinedException] if [confirmProbe] says no, and
  /// [NoPrintCharacteristicException] if no characteristic is found.
  Future<void> connect(
    BleDevice device, {
    ConfirmProbe? confirmProbe,
    ConfirmTestPrint? confirm,
    Duration connectTimeout = const Duration(seconds: 10),
    bool autoConnect = false,
  }) async {
    await disconnect();

    final id = device.deviceId;
    await UniversalBle.connect(
      id,
      timeout: connectTimeout,
      autoConnect: autoConnect,
    );

    try {
      final mtu = await _negotiateMtu(id);
      final services = await UniversalBle.discoverServices(id);
      final saved =
          (await store.getAll()).where((p) => p.remoteId == id).firstOrNull;

      var target = saved == null
          ? null
          : _findWritable(
              services, saved.serviceUuid, saved.characteristicUuid);
      if (target == null) {
        target = ZebraBle.findPrintTarget(services);
        if (target != null) {
          await store.save(SavedBlePrinter(
            remoteId: id,
            serviceUuid: target.service,
            characteristicUuid: target.characteristic,
          ));
        }
      }
      if (target == null && confirmProbe != null && confirm != null) {
        if (!await confirmProbe(device)) throw ProbeDeclinedException(id);
        target = await _probe(id, mtu, services, confirm);
      }
      if (target == null) throw NoPrintCharacteristicException(id);

      _device = device;
      _target = target;
      _mtu = mtu;
      _connectionSub = UniversalBle.connectionStream(id).listen((connected) {
        if (!connected) _onConnectionLost(device);
      });
    } catch (_) {
      // the original error is the useful one, not a failed cleanup
      try {
        await UniversalBle.disconnect(id);
      } catch (_) {}
      rethrow;
    }
  }

  void _onConnectionLost(BleDevice device) {
    if (_device?.deviceId != device.deviceId) return;
    _device = null;
    _target = null;
    _mtu = _defaultMtu;
    _connectionSub?.cancel();
    _connectionSub = null;
    _lost.add(device);
  }

  /// Reconnects to a printer already known to the [store], without asking the
  /// user anything: scans until it shows up (up to [scanTimeout]) and connects.
  ///
  /// Uses the printer with [remoteId], or the first saved one. Returns true
  /// right away if it is already connected, and false if none is saved or it
  /// wasn't found nearby (off, out of range).
  /// Throws [NoPrintCharacteristicException] if the saved characteristic no
  /// longer exists on the printer: run the setup with [connect] again.
  Future<bool> reconnect({
    String? remoteId,
    Duration scanTimeout = const Duration(seconds: 8),
    Duration connectTimeout = const Duration(seconds: 10),
  }) async {
    // a connected printer stops advertising, so a scan wouldn't find it
    if (isReady && (remoteId == null || _device?.deviceId == remoteId)) {
      return true;
    }

    final saved = (await store.getAll())
        .where((p) => remoteId == null || p.remoteId == remoteId)
        .firstOrNull;
    if (saved == null) return false;

    final device = await _scanFor(saved.remoteId, scanTimeout);
    if (device == null) return false;

    await connect(device, connectTimeout: connectTimeout);
    return true;
  }

  /// Scans until the device with [remoteId] shows up, or [timeout] expires.
  Future<BleDevice?> _scanFor(String remoteId, Duration timeout) async {
    final wanted = remoteId.toLowerCase();
    final found = Completer<BleDevice?>();
    final sub = UniversalBle.scanStream.listen((d) {
      if (d.deviceId.toLowerCase() == wanted && !found.isCompleted) {
        found.complete(d);
      }
    });
    try {
      await UniversalBle.startScan();
      return await found.future.timeout(timeout, onTimeout: () => null);
    } finally {
      try {
        await UniversalBle.stopScan();
      } catch (_) {}
      await sub.cancel();
    }
  }

  /// Sends [zpl] to the printer.
  Future<void> printZpl(String zpl) => printBytes(utf8.encode(zpl));

  /// Sends raw [data] to the printer. Calls are queued, so concurrent prints
  /// never interleave their chunks. Throws [StateError] if not connected.
  Future<void> printBytes(List<int> data) => _printQueue.run(() async {
        final d = _device;
        final t = _target;
        if (d == null || t == null) throw StateError('Printer not connected');
        await chunkedWrite(d.deviceId, t.service, t.characteristic, data,
            mtu: _mtu);
      });

  Future<void> disconnect() async {
    final d = _device;
    _device = null;
    _target = null;
    _mtu = _defaultMtu;
    await _connectionSub?.cancel();
    _connectionSub = null;
    if (d != null) await UniversalBle.disconnect(d.deviceId);
  }

  /// Disconnects and releases resources. Don't use the instance afterwards.
  Future<void> dispose() async {
    await disconnect();
    await _lost.close();
  }

  Future<int> _negotiateMtu(String deviceId) async {
    try {
      return await UniversalBle.requestMtu(deviceId, 512);
    } catch (_) {
      return _defaultMtu;
    }
  }

  Future<({String service, String characteristic})?> _probe(
    String deviceId,
    int mtu,
    List<BleService> services,
    ConfirmTestPrint confirm,
  ) async {
    for (final s in services) {
      if (isStandardGattUuid(s.uuid)) continue;
      for (final c in s.characteristics) {
        if (!c.properties.contains(CharacteristicProperty.write)) continue;
        try {
          await chunkedWrite(deviceId, s.uuid, c.uuid, utf8.encode(testLabel),
              mtu: mtu);
          if (await confirm(c.uuid)) {
            await store.save(SavedBlePrinter(
              remoteId: deviceId,
              serviceUuid: s.uuid,
              characteristicUuid: c.uuid,
            ));
            return (service: s.uuid, characteristic: c.uuid);
          }
        } catch (_) {
          // unusable characteristic, move on to the next one
        }
      }
    }
    return null;
  }

  static ({String service, String characteristic})? _findWritable(
      List<BleService> services, String serviceUuid, String uuid) {
    final wantedService = BleUuidParser.string(serviceUuid);
    final wantedChar = BleUuidParser.string(uuid);
    for (final s in services) {
      if (BleUuidParser.string(s.uuid) != wantedService) continue;
      for (final c in s.characteristics) {
        if (BleUuidParser.string(c.uuid) == wantedChar &&
            c.properties.contains(CharacteristicProperty.write)) {
          return (service: s.uuid, characteristic: c.uuid);
        }
      }
    }
    return null;
  }
}
