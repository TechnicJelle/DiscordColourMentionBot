import "dart:io";
import "dart:typed_data";

import "package:image/image.dart" as img;

abstract class ImageGenerator {
  final int _imageSize;

  ImageGenerator({required int imageSize}) : _imageSize = imageSize;

  Future<Uint8List?> generateImageForColour(String hexString);

  img.Command _createImageWithColour(img.Color colour) {
    return img.Command()
      ..createImage(width: _imageSize, height: _imageSize, numChannels: 4)
      ..fill(color: colour);
  }

  static img.Color? _colorFromHexColour(String hexString) {
    final int? ox = int.tryParse(hexString.replaceFirst("#", "0x")); //heehee
    if (ox == null) return null;

    if (hexString.length == 1 + 6) {
      final int b = ox & 255;
      final int g = (ox >> 8) & 255;
      final int r = (ox >> 16) & 255;
      return img.ColorRgb8(r, g, b);
    } else if (hexString.length == 1 + 8) {
      final int a = ox & 255;
      final int b = (ox >> 8) & 255;
      final int g = (ox >> 16) & 255;
      final int r = (ox >> 24) & 255;
      return img.ColorRgba8(r, g, b, a);
    }

    return null;
  }
}

class EmojiImageGenerator extends ImageGenerator {
  //that's the size discord wants, but 1×1 technically works too...
  EmojiImageGenerator() : super(imageSize: 128);

  @override
  Future<Uint8List?> generateImageForColour(String hexString) async {
    final img.Color? colour = ImageGenerator._colorFromHexColour(hexString);
    if (colour == null) return null;

    final img.Command command = _createImageWithColour(colour)..encodePng();
    return command.getBytes();
  }
}

class AttachmentImageGenerator extends ImageGenerator {
  AttachmentImageGenerator() : super(imageSize: 512);

  static final img.BitmapFont font = img.readFontZip(
    File("JBMono.zip").readAsBytesSync(),
  );

  //the font is actually 40, but we add a little more for the extra spacing between the lines
  static const int textHeight = 48;

  @override
  Future<Uint8List?> generateImageForColour(String hexString) async {
    final img.Color? colour = ImageGenerator._colorFromHexColour(hexString);
    if (colour == null) return null;

    final double luminance = (0.299 * colour.r + 0.587 * colour.g + 0.114 * colour.b) / 255;
    final img.Color textColour = luminance > 0.5
        ? img.ColorRgb8(0, 0, 0)
        : img.ColorRgb8(255, 255, 255);

    final String? rgbString = switch (colour) {
      img.ColorRgb8() => "rgb(${colour.r},${colour.g},${colour.b})",
      img.ColorRgba8() => "rgba(${colour.r},${colour.g},${colour.b},${colour.a})",
      _ => null,
    };
    if (rgbString == null) return null;

    final img.Command command = _createImageWithColour(colour)
      ..drawString(
        hexString,
        font: font,
        color: textColour,
        y: _imageSize ~/ 2 - textHeight,
      )
      ..drawString(
        rgbString,
        font: font,
        color: textColour,
        y: _imageSize ~/ 2,
      )
      ..encodePng();

    return command.getBytes();
  }
}
