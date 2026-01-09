import "dart:collection";
import "dart:typed_data";

import "package:nyxx/nyxx.dart";
import "package:nyxx/src/models/emoji.dart";

import "image_generators.dart";

abstract class ReplyCache<T> {
  final NyxxGateway _client;
  final ImageGenerator _imageGenerator;
  final int _cacheSizeLimit;

  final Map<String, T> _cacheDict = HashMap<String, T>();

  ReplyCache({
    required NyxxGateway client,
    required ImageGenerator imageGenerator,
    required int cacheSizeLimit,
  }) : _client = client,
       _imageGenerator = imageGenerator,
       _cacheSizeLimit = cacheSizeLimit;

  Future<void> init();

  String _hexColourToKey(String hexColour) {
    final String key = hexColour.replaceFirst("#", "").toUpperCase();

    //if the provided alpha is 255, we omit it from the key, to encourage cache hits
    //if the same colour without alpha channel was already in the cache
    if (key.length == 8 && key.endsWith("FF")) {
      return key.substring(0, key.length - 2);
    }

    return key;
  }

  Future<T?> getReplyForColour(String hexColour) async {
    final String key = _hexColourToKey(hexColour);

    //check if we have a reply for this colour already
    {
      final T? potentialReplyFromCache = _cacheDict[key];
      if (potentialReplyFromCache != null) return potentialReplyFromCache;
    }

    //we didn't have this colour reply yet, so we make it
    final Uint8List? imageData = await _imageGenerator.generateImageForColour(hexColour);
    if (imageData == null) return null;

    //a while loop in case the length ended up way larger than the limit
    //e.g. if the limit was lowered recently
    while (_cacheDict.length >= _cacheSizeLimit) {
      //delete an old reply to make space for this one
      //TODO: can we make it delete the least-often used emoji..?

      //technically, this hashmap does not guarantee order,
      //but often enough the map is sorted from old at the front to new at the end,
      //that getting the first one generally results in an old emoji.
      //and even if it overwrites a new-ish emoji, the worst thing that happens is that it's a little bit slower. oh well!
      await _deleteItem(_cacheDict.entries.first);
    }

    final T newEmoji = await _createReply(key, imageData);

    return _cacheDict[key] = newEmoji;
  }

  Future<void> _deleteItem(MapEntry<String, T> toDelete) async {
    _cacheDict.remove(toDelete.key);
  }

  Future<T> _createReply(String replyName, Uint8List imageData);
}

class EmojiReplyCache extends ReplyCache<ApplicationEmoji> {
  EmojiReplyCache({required super.client})
    : super(
        imageGenerator: EmojiImageGenerator(),
        //could technically be 2000, but added a 50 buffer Just In Case™
        cacheSizeLimit: 1950,
      );

  @override
  Future<void> init() async {
    final List<ApplicationEmoji> emojiList = await _client.application.emojis.list();
    for (final ApplicationEmoji emoji in emojiList) {
      _cacheDict[emoji.name] = emoji;
    }
  }

  @override
  Future<void> _deleteItem(MapEntry<String, ApplicationEmoji> toDelete) async {
    await super._deleteItem(toDelete);
    await _client.application.emojis.delete(toDelete.value.id);
  }

  bool isOurs(Emoji emoji) {
    return _cacheDict.containsValue(emoji);
  }

  @override
  Future<ApplicationEmoji> _createReply(String replyName, Uint8List imageData) async {
    return _client.application.emojis.create(
      ApplicationEmojiBuilder(
        name: replyName,
        image: ImageBuilder.png(imageData),
      ),
    );
  }
}

class AttachmentReplyCache extends ReplyCache<AttachmentBuilder> {
  AttachmentReplyCache({required super.client})
    : super(
        imageGenerator: AttachmentImageGenerator(),
        cacheSizeLimit: 200,
      );

  @override
  Future<void> init() async {}

  @override
  Future<AttachmentBuilder> _createReply(String replyName, Uint8List imageData) async {
    return AttachmentBuilder(
      data: imageData,
      fileName: "$replyName.png",
    );
  }
}
