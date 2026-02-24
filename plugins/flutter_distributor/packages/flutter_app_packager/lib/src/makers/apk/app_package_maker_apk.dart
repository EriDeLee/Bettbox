import 'package:flutter_app_packager/src/api/app_package_maker.dart';

class AppPackageMakerApk extends AppPackageMaker {
  @override
  String get name => 'apk';

  @override
  String get platform => 'android';

  @override
  String get packageFormat => 'apk';

  @override
  Future<MakeResult> make(MakeConfig config) {
    for (final file in config.buildOutputFiles) {
      final splits = file.uri.pathSegments.last.split('-');
      final outputPath = config.outputFile.path;
      if (splits.length > 2) {
        final sublist = splits.sublist(1, splits.length - 1);
        final lastDotIndex = outputPath.lastIndexOf('.');
        final firstPart = outputPath.substring(0, lastDotIndex);
        final lastPart = outputPath.substring(lastDotIndex + 1);
        final output = '$firstPart-${sublist.join('-')}.${lastPart}';
        file.copySync(output);
      } else {
        file.copySync(outputPath);
      }
    }
    return Future.value(resultResolver.resolve(config));
  }
}
