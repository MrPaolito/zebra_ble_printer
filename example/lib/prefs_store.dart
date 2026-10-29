import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:zebra_ble_printer/zebra_ble_printer.dart';

/// Example [BlePrinterStore] backed by SharedPreferences.
class PrefsPrinterStore implements BlePrinterStore {
  static const _key = 'saved_ble_printers';

  @override
  Future<List<SavedBlePrinter>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    return (json.decode(raw) as List)
        .map((e) => SavedBlePrinter.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _write(List<SavedBlePrinter> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, json.encode(items));
  }

  @override
  Future<void> save(SavedBlePrinter printer) async {
    final items = await getAll();
    await _write([
      ...items.where((p) => p.remoteId != printer.remoteId),
      printer,
    ]);
  }

  @override
  Future<void> remove(String remoteId) async {
    final items = await getAll();
    await _write(items.where((p) => p.remoteId != remoteId).toList());
  }
}
