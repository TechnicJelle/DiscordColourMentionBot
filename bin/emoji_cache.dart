import "dart:collection";
import "dart:typed_data";

import "package:image/image.dart" as img;
import "package:nyxx/nyxx.dart";
import "package:nyxx/src/models/emoji.dart";

//could technically be 2000, but added a 50 buffer Just In Case™
const int cacheSizeLimit = 1950;

class EmojiCache {
  final NyxxGateway _client;

  final Map<String, ApplicationEmoji> _emojiDict = HashMap<String, ApplicationEmoji>();

  EmojiCache(NyxxGateway client) : _client = client;

  Future<void> init() async {
    final List<ApplicationEmoji> emojiList = await _client.application.emojis.list();
    for (final ApplicationEmoji emoji in emojiList) {
      _emojiDict[emoji.name] = emoji;
    }
  }

  String hexColourToKey(String hexColour) {
    final String key = hexColour.replaceFirst("#", "").toUpperCase();

    //if the provided alpha is 255, we omit it from the key, to encourage cache hits
    //if the same colour without alpha channel was already in the cache
    if (key.length == 8 && key.endsWith("FF")) {
      return key.substring(0, key.length - 2);
    }

    return key;
  }

  Future<Emoji?> getEmojiForColour(String hexColour) async {
    final String key = hexColourToKey(hexColour);

    //check if we have this colour emoji already
    {
      final ApplicationEmoji? potentialEmojiFromCache = _emojiDict[key];
      if (potentialEmojiFromCache != null) return potentialEmojiFromCache;
    }

    //we didn't have this colour emoji yet, so we make it
    final Uint8List? imageData = await generateImageForColour(hexColour);
    if (imageData == null) return null;

    //a while loop in case the length ended up way larger than the limit
    //e.g. if the limit was lowered recently
    while (_emojiDict.length >= cacheSizeLimit) {
      //delete an old emoji to make space for this one
      //TODO: can we make it delete the least-often used emoji..?

      //technically, this hashmap does not guarantee order,
      //but often enough the map is sorted from old at the front to new at the end,
      //that getting the first one generally results in an old emoji.
      //and even if it overwrites a new-ish emoji, the worst thing that happens is that it's a little bit slower. oh well!
      await deleteEmoji(_emojiDict.entries.first);
    }

    final ApplicationEmoji newEmoji = await _client.application.emojis.create(
      ApplicationEmojiBuilder(
        name: key,
        image: ImageBuilder.png(imageData),
      ),
    );

    return _emojiDict[key] = newEmoji;
  }

  bool isOurs(Emoji emoji) {
    return _emojiDict.containsValue(emoji);
  }

  /// Deletes an emoji both from the server and the [_emojiDict]
  Future<void> deleteEmoji(MapEntry<String, ApplicationEmoji> toDelete) async {
    await _client.application.emojis.delete(toDelete.value.id);
    _emojiDict.remove(toDelete.key);
  }
}

//that's the size discord wants, but 1×1 technically works too...
const int imageSize = 128;

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
