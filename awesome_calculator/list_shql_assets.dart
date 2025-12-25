import 'dart:io';

void main() {
  final dir = Directory('assets');
  final shqlFiles = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.shql'))
      .map((f) => f.path.replaceFirst('assets\\shql\\', ''))
      .toList();

  print('final assetFiles = [');
  for (var file in shqlFiles) {
    print("  '$file',");
  }
  print('];');
}
