import 'dart:math';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

/// Splits [data] into blocks of [size] bytes (the last one may be shorter).
List<List<int>> splitIntoChunks(List<int> data, int size) {
  assert(size > 0);
  return [
    for (var i = 0; i < data.length; i += size)
      data.sublist(i, min(i + size, data.length)),
  ];
}

/// Writes [value] to a characteristic in blocks that fit the negotiated [mtu]
/// (3 ATT header bytes, 512 max), always with response so the printer
/// doesn't overflow.
Future<void> chunkedWrite(
  String deviceId,
  String serviceUuid,
  String characteristicUuid,
  List<int> value, {
  required int mtu,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final size = max(1, min(mtu - 3, 512));
  for (final chunk in splitIntoChunks(value, size)) {
    await UniversalBle.write(
      deviceId,
      serviceUuid,
      characteristicUuid,
      Uint8List.fromList(chunk),
      withoutResponse: false,
      timeout: timeout,
    );
  }
}
