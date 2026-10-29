/// A known BLE printer: device id (MAC on Android, UUID on iOS) and the
/// service/characteristic UUIDs on which printing was confirmed.
class SavedBlePrinter {
  final String remoteId;
  final String serviceUuid;
  final String characteristicUuid;

  const SavedBlePrinter({
    required this.remoteId,
    required this.serviceUuid,
    required this.characteristicUuid,
  });

  Map<String, dynamic> toJson() => {
        'remoteId': remoteId,
        'serviceUuid': serviceUuid,
        'characteristicUuid': characteristicUuid,
      };

  factory SavedBlePrinter.fromJson(Map<String, dynamic> json) =>
      SavedBlePrinter(
        remoteId: json['remoteId'] as String,
        serviceUuid: json['serviceUuid'] as String,
        characteristicUuid: json['characteristicUuid'] as String,
      );
}
