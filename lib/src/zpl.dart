/// Helpers to build safe ZPL and ready-made test labels.
///
/// The test labels stay inside the first 400 dots (the ZD410 print head is
/// about 56 mm, 448 dots at 203 dpi), so they fit narrower media too.
class Zpl {
  Zpl._();

  /// Escapes [text] for use inside `^FD` when `^FH_` is active, so that user
  /// input can't inject ZPL commands (`^` and `~` start commands).
  static String escape(String text) => text
      .replaceAll('_', '_5F')
      .replaceAll('^', '_5E')
      .replaceAll('~', '_7E');

  /// A one-line label with [text] at ([x], [y]). The text is escaped and sent
  /// as UTF-8 (`^CI28`), so accents and `€` work on firmware that supports it.
  static String textLabel(String text,
          {int x = 50, int y = 50, int height = 40}) =>
      '^XA^CI28^FO$x,$y^A0N,$height,$height^FH_^FD${escape(text)}^FS^XZ';

  /// Plain ASCII text: the smallest label that proves the channel works.
  static const testText = '^XA^FO50,50^A0N,40,40^FDHELLO ZEBRA^FS^XZ';

  /// A framed box with text: shows the print area and the margins.
  static const testBox =
      '^XA^FO20,20^GB360,160,4^FS^FO40,70^A0N,40,40^FDBOX TEST^FS^XZ';

  /// A Code 128 barcode: shows print darkness and resolution.
  static const testBarcode =
      '^XA^FO50,40^BY3^BCN,100,Y,N,N^FD123456789^FS^XZ';

  /// Accented characters and the euro sign: checks UTF-8 (`^CI28`) support.
  /// If they come out wrong, the firmware doesn't support `^CI28`.
  static const testAccents =
      '^XA^CI28^FO50,50^A0N,40,40^FDàèéìòù €^FS^XZ';
}
