// Saving / picking / sharing files on the device (Android + Windows).
// Each entry point is a variable so tests can replace the platform dialogs.
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'session_log.dart';

/// A file chosen on the device: a readable path, or its bytes when the
/// platform only gives bytes.
class PickedFile {
  const PickedFile(this.name, {this.path, this.bytes});
  final String name;
  final String? path;
  final Uint8List? bytes;
}

/// Asks where to save [bytes] (Android: system "save as" screen, so the file
/// lands where the user can reach it, e.g. Downloads; Windows: Save dialog).
/// Returns where it went, or null when cancelled. If the dialog is not
/// available it falls back to the app's documents/Downloads folder.
Future<String?> Function(String name, Uint8List bytes) saveToDevice = _save;

Future<String?> _save(String name, Uint8List bytes) async {
  try {
    final r = await FilePicker.saveFile(fileName: name, bytes: bytes);
    return r;
  } catch (_) {
    final d = Directory('${(await appDocsDir()).path}${Platform.pathSeparator}Downloads');
    await d.create(recursive: true);
    final f = File('${d.path}${Platform.pathSeparator}$name');
    await f.writeAsBytes(bytes);
    return f.path;
  }
}

/// Lets the user pick one file. Null when cancelled.
Future<PickedFile?> Function() pickFromDevice = _pick;

Future<PickedFile?> _pick() async {
  final r = await FilePicker.pickFiles(withData: false);
  final f = r?.files.single;
  if (f == null) return null;
  if (f.path != null) return PickedFile(f.name, path: f.path);
  return PickedFile(f.name, bytes: f.bytes);
}

/// Whether the system share sheet can send files here.
bool get canShareFiles => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

/// Opens the share sheet for a local file (Android: send to Telegram, Drive…).
Future<void> Function(String path) shareFile = (path) async {
  await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
};
