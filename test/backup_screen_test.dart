import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rihla_pos/backup.dart';
import 'package:rihla_pos/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:rihla_pos/store.dart';

class TestFilePicker extends FilePicker {
  Uint8List? savedBytes;
  String? savePath = 'backup.json';
  FilePickerResult? selection;
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    savedBytes = bytes;
    return savePath;
  }

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => selection;
}

void main() {
  sqfliteFfiInit();
  testWidgets('backup file flow previews, cancels and confirms replacement', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final picker = TestFilePicker();
    FilePicker.platform = picker;
    late PosStore store;
    late Directory directory;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('rihla_backup_ui_');
      store = await PosStore.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/db',
      );
      await store.addProduct('Saved item', 'A01', 100, 4, 'shop');
      await tester.pumpWidget(RihlaApp(store: store));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    Future<void> tap(String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() async {
        await tester.tap(find.text(label));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump(const Duration(milliseconds: 400));
    }

    await tester.pumpAndSettle();
    await tap('More');
    await tap('Backup and restore');
    await tap('Save backup');
    expect(PosBackup.decode(picker.savedBytes!).count('products'), 1);
    expect(
      find.text('Backup saved. Keep a copy outside this app.'),
      findsOneWidget,
    );
    final backup = picker.savedBytes!;
    picker.savePath = null;
    await tap('Save backup');
    expect(find.textContaining('Backup cancelled.'), findsOneWidget);
    await tester.runAsync(() async {
      final file = File('${directory.path}/backup.json');
      await file.writeAsBytes(backup);
      picker.selection = FilePickerResult([
        PlatformFile(path: file.path, name: 'backup.json', size: backup.length),
      ]);
      await store.updateProduct(1, 'Current item', 'A01', 200, 0);
    });
    await tap('Restore from file');
    expect(find.text('Restore this backup?'), findsOneWidget);
    await tap('Cancel');
    await tester.runAsync(
      () async =>
          expect((await store.products()).single['name'], 'Current item'),
    );
    await tap('Restore from file');
    await tap('Replace records');
    await tester.runAsync(
      () async => expect((await store.products()).single['name'], 'Saved item'),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await store.db.close();
      await directory.delete(recursive: true);
    });
  });
}
