import 'saved_printer.dart';

/// Persistence of known printers. The app implements it however it likes
/// (SharedPreferences, database, server...).
abstract class BlePrinterStore {
  Future<List<SavedBlePrinter>> getAll();

  /// Saves the printer, replacing the one with the same [SavedBlePrinter.remoteId].
  Future<void> save(SavedBlePrinter printer);

  Future<void> remove(String remoteId);
}

/// In-memory implementation, useful for tests or usage without persistence.
class InMemoryBlePrinterStore implements BlePrinterStore {
  final Map<String, SavedBlePrinter> _items = {};

  @override
  Future<List<SavedBlePrinter>> getAll() async => _items.values.toList();

  @override
  Future<void> save(SavedBlePrinter printer) async =>
      _items[printer.remoteId] = printer;

  @override
  Future<void> remove(String remoteId) async => _items.remove(remoteId);
}
