import 'package:flutter_test/flutter_test.dart';
import 'package:zebra_ble_printer/src/serial_queue.dart';

void main() {
  test('SerialQueue runs tasks one at a time, in order', () async {
    final queue = SerialQueue();
    final log = <String>[];

    Future<void> task(String name, int ms) async {
      log.add('start $name');
      await Future<void>.delayed(Duration(milliseconds: ms));
      log.add('end $name');
    }

    await Future.wait([
      queue.run(() => task('a', 30)),
      queue.run(() => task('b', 1)),
      queue.run(() => task('c', 1)),
    ]);

    expect(log, [
      'start a', 'end a', //
      'start b', 'end b',
      'start c', 'end c',
    ]);
  });

  test('SerialQueue keeps going after a failing task', () async {
    final queue = SerialQueue();
    final failing = queue.run<void>(() async => throw StateError('boom'));
    final next = queue.run(() async => 42);

    await expectLater(failing, throwsStateError);
    expect(await next, 42);
  });
}
