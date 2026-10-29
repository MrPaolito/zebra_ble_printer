## 0.1.0

- First release: scan, connect, `reconnect`, MTU-safe chunked writes,
  `BlePrinterStore`.
- Uses Zebra's documented BLE parser service (`38eb4a82-...`); falls back to a
  user-confirmed test print if it isn't exposed.
- `Zpl` helpers: escaping, text label, test labels.
- Print calls are queued; `onDisconnected` reports a lost connection;
  `dispose()` releases resources.
