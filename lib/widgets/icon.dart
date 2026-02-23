import 'dart:io';
import 'dart:ui' as ui;
import 'package:bett_box/common/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_svg/svg.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:path/path.dart' as path;

class CommonTargetIcon extends StatefulWidget {
  final String src;
  final double size;

  const CommonTargetIcon({super.key, required this.src, required this.size});

  @override
  State<CommonTargetIcon> createState() => _CommonTargetIconState();
}

class _CommonTargetIconState extends State<CommonTargetIcon> {
  File? _file;
  String? _cachedSrc; // Cached src
  int? _cachedSize; // Cached size

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant CommonTargetIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final cacheSize = (widget.size * devicePixelRatio).ceil();

    // Reinit when src or size changes
    if (oldWidget.src != widget.src || _cachedSize != cacheSize) {
      _file = null;
      _cachedSrc = null;
      _cachedSize = null;
      _init();
    }
  }

  /// Generate resized cache path
  Future<String> _getResizedCachePath(String originalPath, int size) async {
    final hash = md5.convert(utf8.encode('${originalPath}_$size')).toString();
    final tempDir = await appPath.tempPath;
    return path.join(tempDir, 'resized_icons', '$hash.png');
  }

  /// Decode, resize and cache image to disk
  Future<File?> _resizeAndCacheImage(File originalFile, int targetSize) async {
    try {
      final cachePath = await _getResizedCachePath(
        originalFile.path,
        targetSize,
      );
      final cacheFile = File(cachePath);

      // Return cached file if exists
      if (await cacheFile.exists()) {
        return cacheFile;
      }

      // Read original image
      final bytes = await originalFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetSize,
        targetHeight: targetSize,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;

      // Convert to PNG bytes
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        return null;
      }

      // Save to disk
      await cacheFile.parent.create(recursive: true);
      await cacheFile.writeAsBytes(byteData.buffer.asUint8List());

      return cacheFile;
    } catch (e) {
      // Resize failed, return original
      return originalFile;
    }
  }

  Future<void> _init() async {
    if (widget.src.isEmpty) {
      return;
    }
    if (widget.src.getBase64 != null) {
      return;
    }

    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final cacheSize = (widget.size * devicePixelRatio).ceil();

    // If cached with same src and size, return directly
    if (_cachedSrc == widget.src && _cachedSize == cacheSize && _file != null) {
      return;
    }

    // Get from cache first, no network check
    final fileInfo = await DefaultCacheManager().getFileFromCache(widget.src);
    if (fileInfo != null && mounted && widget.src.isNotEmpty) {
      // Resize non-SVG images
      File? displayFile = fileInfo.file;
      if (!widget.src.isSvg) {
        displayFile = await _resizeAndCacheImage(fileInfo.file, cacheSize);
      }

      if (mounted) {
        setState(() {
          _file = displayFile;
          _cachedSrc = widget.src; // Mark cached
          _cachedSize = cacheSize; // Mark cached size
        });
      }
      return;
    }

    // Download if cache not exists
    try {
      final file = await DefaultCacheManager().getSingleFile(widget.src);
      if (mounted && widget.src.isNotEmpty) {
        // Resize non-SVG images
        File? displayFile = file;
        if (!widget.src.isSvg) {
          displayFile = await _resizeAndCacheImage(file, cacheSize);
        }

        if (mounted) {
          setState(() {
            _file = displayFile;
            _cachedSrc = widget.src; // Mark cached
            _cachedSize = cacheSize; // Mark cached size
          });
        }
      }
    } catch (e) {
      // Handle download error
    }
  }

  Widget _defaultIcon() {
    return Icon(IconsExt.target, size: widget.size);
  }

  Widget _buildIcon() {
    if (widget.src.isEmpty) {
      return _defaultIcon();
    }
    final base64 = widget.src.getBase64;
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final cacheSize = (widget.size * devicePixelRatio).ceil();

    if (base64 != null) {
      return Image.memory(
        base64,
        gaplessPlayback: true,
        cacheWidth: cacheSize,
        cacheHeight: cacheSize,
        errorBuilder: (_, error, _) {
          return _defaultIcon();
        },
      );
    }
    if (_file != null) {
      return widget.src.isSvg
          ? SvgPicture.file(
              _file!,
              width: widget.size,
              height: widget.size,
              errorBuilder: (_, _, _) => _defaultIcon(),
            )
          : Image.file(
              _file!,
              gaplessPlayback: true,
              // Don't use cacheWidth/cacheHeight
              // File is already resized
              errorBuilder: (_, _, _) => _defaultIcon(),
            );
    }
    return _defaultIcon();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(
          key: ValueKey<String>('${widget.src}_${_file?.path}'),
          child: _buildIcon(),
        ),
      ),
    );
  }
}
