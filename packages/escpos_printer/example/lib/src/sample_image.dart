import 'dart:convert';
import 'dart:typed_data';

final class SampleRasterImage {
  const SampleRasterImage({
    required this.rasterData,
    required this.widthBytes,
    required this.heightDots,
  });

  final Uint8List rasterData;
  final int widthBytes;
  final int heightDots;

  String get base64Data => base64Encode(rasterData);
}

SampleRasterImage buildSampleRasterImage({
  int widthBytes = 48,
  int heightDots = 48,
}) {
  final data = Uint8List(widthBytes * heightDots);

  for (var y = 0; y < heightDots; y++) {
    for (var xb = 0; xb < widthBytes; xb++) {
      var value = 0;
      for (var bit = 0; bit < 8; bit++) {
        final x = (xb * 8) + bit;
        final checker = ((x ~/ 8) + (y ~/ 8)) % 2 == 0;
        final diagonal = x == y || x == (heightDots - 1 - y);
        if (checker || diagonal) {
          value |= (0x80 >> bit);
        }
      }
      data[(y * widthBytes) + xb] = value;
    }
  }

  return SampleRasterImage(
    rasterData: data,
    widthBytes: widthBytes,
    heightDots: heightDots,
  );
}
