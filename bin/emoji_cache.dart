import "dart:typed_data";

import "package:image/image.dart" as img;
import "package:nyxx/nyxx.dart";
import "package:nyxx/src/models/emoji.dart";

//could technically be 2000, but added a 50 buffer Just In Case™
const int cacheSizeLimit = 1950;

class EmojiCache {
  final NyxxGateway _client;

  Cache<Emoji> get nyxxCache => _client.application.emojis.cache;

  final Map<String, ApplicationEmoji> _emojiDict = <String, ApplicationEmoji>{};

  EmojiCache(NyxxGateway client) : _client = client;

  Future<void> init() async {
    final List<ApplicationEmoji> emojiList = await _client.application.emojis.list();
    for (final ApplicationEmoji emoji in emojiList) {
      _emojiDict[emoji.name] = emoji;
    }
  }

  String hexColourToKey(String hexColour) {
    final String key = hexColour.replaceFirst("#", "").toUpperCase();

    //if the provided alpha is 255, we omit it from the key
    if (key.length == 8 && key.endsWith("FF")) {
      return key.substring(0, key.length - 2);
    }

    return key;
  }

  Future<Emoji?> getEmojiForColour(String hexColour) async {
    final String key = hexColourToKey(hexColour);

    //check if we have this colour emoji already
    if (_emojiDict.containsKey(key)) {
      return _emojiDict[key];
    }

    //we didn't have this colour emoji yet, so we make it
    final Uint8List? imageData = await generateImageForColour(hexColour);
    if (imageData == null) return null;

    if (nyxxCache.length >= cacheSizeLimit) {
      //delete an old emoji to make space for this one
      //TODO: can we make it delete the least-often used emoji..?
      final List<Snowflake> list = nyxxCache.keys.toList(growable: false)
        ..sort((Snowflake a, Snowflake b) => a.value.compareTo(b.value));
      await _client.application.emojis.delete(list.first);
    }

    final ApplicationEmoji newEmoji = await _client.application.emojis.create(
      ApplicationEmojiBuilder(
        name: key,
        image: ImageBuilder.png(imageData),
      ),
    );

    return _emojiDict[key] = newEmoji;
  }
}

const int imageSize =
    128; //that's the size discord wants, but 1×1 technically works too...

Future<Uint8List?> generateImageForColour(String hexString) async {
  final int? ox = int.tryParse(hexString.replaceFirst("#", "0x"));
  if (ox == null) return null;

  final img.Color colour;
  if (hexString.length == 1 + 6) {
    final int b = ox & 255;
    final int g = (ox >> 8) & 255;
    final int r = (ox >> 16) & 255;
    colour = img.ColorRgb8(r, g, b);
  } else if (hexString.length == 1 + 8) {
    final int a = ox & 255;
    final int b = (ox >> 8) & 255;
    final int g = (ox >> 16) & 255;
    final int r = (ox >> 24) & 255;
    colour = img.ColorRgba8(r, g, b, a);
  } else {
    return null;
  }

  final img.Command command = img.Command()
    ..createImage(width: imageSize, height: imageSize, numChannels: 4)
    ..fill(color: colour)
    ..encodePng();

  return command.getBytes();
}
