import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:bett_box/common/common.dart';
import 'package:path/path.dart';

class UiManager {
  static UiManager? _instance;

  UiManager._internal();

  factory UiManager() {
    _instance ??= UiManager._internal();
    return _instance!;
  }

  /// 初始化 UI 文件
  /// 从 assets/data/zash.zip 解压到 UI 目录
  Future<void> initializeUI() async {
    try {
      final uiPath = await appPath.uiPath;
      final uiDir = Directory(uiPath);

      // 检查 UI 目录是否已存在且有文件
      if (await uiDir.exists()) {
        final files = await uiDir.list().toList();
        if (files.isNotEmpty) {
          commonPrint.log('UI already exists, skip extraction');
          return;
        }
      }

      commonPrint.log('Extracting UI from assets...');

      // 创建 UI 目录
      await uiDir.create(recursive: true);

      // 从 assets 读取 zip 文件
      final zipData = await rootBundle.load('assets/data/zash.zip');
      final bytes = zipData.buffer.asUint8List();

      // 解压到临时目录
      final tempPath = await appPath.tempPath;
      final tempExtractPath = join(
        tempPath,
        'ui_extract_${DateTime.now().millisecondsSinceEpoch}',
      );
      final tempExtractDir = Directory(tempExtractPath);
      await tempExtractDir.create(recursive: true);

      try {
        // 解压 zip 文件
        final archive = ZipDecoder().decodeBytes(bytes);

        for (final file in archive) {
          final filename = file.name;
          final filePath = join(tempExtractPath, filename);

          if (file.isFile) {
            final outFile = File(filePath);
            await outFile.create(recursive: true);
            await outFile.writeAsBytes(file.content as List<int>);
          } else {
            await Directory(filePath).create(recursive: true);
          }
        }

        // 移动文件到目标目录
        // 检查是否有单一根目录
        final extractedFiles = await tempExtractDir.list().toList();
        String sourceDir = tempExtractPath;

        if (extractedFiles.length == 1 && extractedFiles.first is Directory) {
          // 如果只有一个目录，使用该目录作为源
          sourceDir = extractedFiles.first.path;
        }

        // 复制文件到目标目录
        await _copyDirectory(Directory(sourceDir), uiDir);

        commonPrint.log('UI extracted successfully to: $uiPath');
      } finally {
        // 清理临时目录
        if (await tempExtractDir.exists()) {
          await tempExtractDir.delete(recursive: true);
        }
      }
    } catch (e) {
      commonPrint.log('Error extracting UI: $e');
      rethrow;
    }
  }

  /// 递归复制目录
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await for (final entity in source.list(recursive: false)) {
      if (entity is Directory) {
        final newDirectory = Directory(
          join(destination.path, basename(entity.path)),
        );
        await newDirectory.create(recursive: true);
        await _copyDirectory(entity, newDirectory);
      } else if (entity is File) {
        final newFile = File(join(destination.path, basename(entity.path)));
        await entity.copy(newFile.path);
      }
    }
  }

  /// 清理 UI 文件
  Future<void> clearUI() async {
    try {
      final uiPath = await appPath.uiPath;
      final uiDir = Directory(uiPath);

      if (await uiDir.exists()) {
        await uiDir.delete(recursive: true);
        commonPrint.log('UI cleared successfully');
      }
    } catch (e) {
      commonPrint.log('Error clearing UI: $e');
    }
  }
}

final uiManager = UiManager();
