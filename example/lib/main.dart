import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:zebra_ble_printer/zebra_ble_printer.dart';

import 'prefs_store.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Zebra BLE Printer',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const SetupWizard(),
      );
}

/// Wizard steps: permissions, scan, connect (+ fallback test), print.
enum _Step { permissions, scan, connect, print }

class SetupWizard extends StatefulWidget {
  const SetupWizard({super.key});

  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  final _printer = ZebraBlePrinter(PrefsPrinterStore());
  final _zpl = TextEditingController(text: ZebraBlePrinter.testLabel);

  /// Ready-made test labels: they check the channel, margins, print quality
  /// and accented characters.
  static const _testLabels = {
    'Text': Zpl.testText,
    'Box': Zpl.testBox,
    'Barcode': Zpl.testBarcode,
    'Accents': Zpl.testAccents,
  };

  _Step _step = _Step.permissions;
  bool _busy = false;
  String? _error;

  List<BleDevice> _devices = [];
  BleDevice? _selected;

  /// Advanced mode: shows every BLE device, not only the ones that look like
  /// a Zebra.
  bool _advanced = false;

  /// Set while the package waits for consent to the fallback test print.
  Completer<bool>? _probeConsent;

  /// Set while the package waits for confirmation of the test print.
  String? _testUuid;
  Completer<bool>? _confirmation;

  StreamSubscription<BleDevice>? _lostSub;

  @override
  void initState() {
    super.initState();
    // the printer switched off or went out of range: back to the scan
    _lostSub = _printer.onDisconnected.listen((d) {
      if (!mounted) return;
      setState(() {
        _error = '${_name(d)} disconnected';
        _step = _Step.scan;
      });
    });
  }

  @override
  void dispose() {
    _lostSub?.cancel();
    _zpl.dispose();
    _printer.dispose();
    super.dispose();
  }

  /// Runs [action] showing the busy state and any error.
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _goTo(_Step step) => setState(() => _step = step);

  Future<void> _requestPermissions() => _run(() async {
        // iOS doesn't need permission_handler: the system asks for the
        // Bluetooth permission at the first scan.
        if (Platform.isAndroid) {
          final statuses = await [
            Permission.bluetoothScan,
            Permission.bluetoothConnect,
            Permission.locationWhenInUse,
          ].request();
          // On Android < 12 bluetoothScan/Connect come back denied but aren't
          // needed: only location and the adapter being on matter.
          final ok = statuses[Permission.bluetoothScan]!.isGranted ||
              statuses[Permission.locationWhenInUse]!.isGranted;
          if (!ok) throw 'Bluetooth permissions denied';
        }
        if (await _tryReconnect()) {
          _goTo(_Step.print);
          return;
        }
        _goTo(_Step.scan);
        await _scan();
      });

  /// Reconnects the saved printer, if there is one and it is nearby.
  Future<bool> _tryReconnect() async {
    try {
      return await _printer.reconnect();
    } catch (_) {
      // the saved characteristic is gone: go through the setup again
      return false;
    }
  }

  Future<void> _scan() => _run(() async {
        final found = await _printer.scan();
        found.sort((a, b) => (b.rssi ?? -127).compareTo(a.rssi ?? -127));
        setState(() => _devices = found);
        if (found.isEmpty) {
          throw 'No devices found. Check that Bluetooth is on and that the app '
              'has the permission (Settings).';
        }
      });

  Future<void> _connect(BleDevice device) {
    _selected = device;
    _goTo(_Step.connect);
    return _run(() async {
      try {
        // The two callbacks are only used if the printer doesn't expose
        // Zebra's documented channel: then it falls back to a test print.
        await _printer.connect(
          device,
          confirmProbe: _askProbeConsent,
          confirm: _askConfirm,
        );
        _goTo(_Step.print);
      } catch (_) {
        _goTo(_Step.scan);
        rethrow;
      }
    });
  }

  /// Called by the package before writing to the device: the answer comes
  /// from the buttons of the "Connect" step.
  Future<bool> _askProbeConsent(BleDevice device) {
    final completer = Completer<bool>();
    setState(() => _probeConsent = completer);
    return completer.future.whenComplete(() {
      if (mounted) setState(() => _probeConsent = null);
    });
  }

  /// Called by the package for each characteristic tried: the answer comes
  /// from the Yes/No buttons of the "Connect" step.
  Future<bool> _askConfirm(String uuid) {
    final completer = Completer<bool>();
    setState(() {
      _testUuid = uuid;
      _confirmation = completer;
    });
    return completer.future.whenComplete(() {
      if (mounted) {
        setState(() {
          _testUuid = null;
          _confirmation = null;
        });
      }
    });
  }

  Future<void> _print() => _run(() async {
        try {
          await _printer.printZpl(_zpl.text);
          _snack('Sent to the printer');
        } catch (_) {
          if (!_printer.isReady) _goTo(_Step.scan);
          rethrow;
        }
      });

  Future<void> _restart() => _run(() async {
        await _printer.disconnect();
        setState(() => _selected = null);
        _goTo(_Step.scan);
      });

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _name(BleDevice d) =>
      (d.name?.isNotEmpty ?? false) ? d.name! : d.deviceId;

  StepState _state(_Step s) => s.index < _step.index
      ? StepState.complete
      : s == _step
          ? StepState.indexed
          : StepState.disabled;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up Zebra printer')),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: Stepper(
              type: StepperType.vertical,
              currentStep: _step.index,
              controlsBuilder: (_, _) => const SizedBox.shrink(),
              steps: [
                Step(
                  title: const Text('Permissions'),
                  state: _state(_Step.permissions),
                  isActive: _step == _Step.permissions,
                  content: _permissionsStep(),
                ),
                Step(
                  title: const Text('Find the printer'),
                  state: _state(_Step.scan),
                  isActive: _step == _Step.scan,
                  content: _scanStep(),
                ),
                Step(
                  title: const Text('Connect'),
                  state: _state(_Step.connect),
                  isActive: _step == _Step.connect,
                  content: _connectStep(),
                ),
                Step(
                  title: const Text('Print'),
                  state: _state(_Step.print),
                  isActive: _step == _Step.print,
                  content: _printStep(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorText() => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        );

  Widget _permissionsStep() => _stepBody([
        const Text('Bluetooth permissions (and location on Android) are '
            'needed to find the printer.'),
        FilledButton(
          onPressed: _busy ? null : _requestPermissions,
          child: const Text('Grant permissions'),
        ),
      ]);

  Widget _scanStep() {
    final shown =
        _advanced ? _devices : _devices.where(ZebraBle.looksLikeZebra).toList();
    final hidden = _devices.length - shown.length;
    return _stepBody([
      const Text('Switch the printer on and pick it from the list.'),
      OutlinedButton.icon(
        onPressed: _busy ? null : _scan,
        icon: const Icon(Icons.refresh),
        label: const Text('Scan again'),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Advanced: show all devices'),
        subtitle: !_advanced && hidden > 0
            ? Text('$hidden devices hidden')
            : null,
        value: _advanced,
        onChanged: (v) => setState(() => _advanced = v),
      ),
      if (_advanced)
        Text(
          'Warning: the test print writes to the device you pick. '
          'Only pick it if you are sure it is the printer.',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (shown.isEmpty && _devices.isNotEmpty)
        const Text('No Zebra printer found. '
            'Turn on "Advanced" to see all devices.'),
      for (final d in shown)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.bluetooth),
          title: Text(_name(d)),
          subtitle: Text(_advanced
              ? 'RSSI ${d.rssi ?? '-'} · ${d.deviceId}'
                  '${d.services.isEmpty ? '' : '\nServices: ${d.services.join(', ')}'}'
              : 'RSSI ${d.rssi ?? '-'}'),
          isThreeLine: _advanced && d.services.isNotEmpty,
          onTap: _busy ? null : () => _connect(d),
        ),
    ]);
  }

  Widget _connectStep() {
    final uuid = _testUuid;
    final consent = _probeConsent;
    return _stepBody([
      Text(_selected == null
          ? 'Waiting...'
          : 'Connecting to ${_name(_selected!)}...'),
      if (consent != null) ...[
        Text('I am about to send a test label to '
            '${_selected == null ? 'this device' : _name(_selected!)}. '
            'Continue?'),
        Row(children: [
          FilledButton(
            onPressed: () => consent.complete(true),
            child: const Text('Continue'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => consent.complete(false),
            child: const Text('Cancel'),
          ),
        ]),
      ],
      if (uuid != null) ...[
        Text('I sent a test label on the channel:\n$uuid',
            style: Theme.of(context).textTheme.bodySmall),
        const Text('Did it print?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        Row(children: [
          FilledButton(
            onPressed: () => _confirmation?.complete(true),
            child: const Text('Yes'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => _confirmation?.complete(false),
            child: const Text('No, try the next one'),
          ),
        ]),
      ],
    ]);
  }

  Widget _printStep() => _stepBody([
        Text('Connected to ${_printer.device == null ? '' : _name(_printer.device!)}',
            style: Theme.of(context).textTheme.titleMedium),
        Wrap(spacing: 8, children: [
          for (final t in _testLabels.entries)
            ActionChip(
              label: Text(t.key),
              onPressed: () => setState(() => _zpl.text = t.value),
            ),
        ]),
        TextField(
          controller: _zpl,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'ZPL',
            border: OutlineInputBorder(),
          ),
        ),
        Row(children: [
          FilledButton.icon(
            onPressed: _busy ? null : _print,
            icon: const Icon(Icons.print),
            label: const Text('Print'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _busy ? null : _restart,
            child: const Text('Change printer'),
          ),
        ]),
      ]);

  Widget _stepBody(List<Widget> children) => Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _errorText(),
            for (final c in children)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: c),
          ],
        ),
      );
}
