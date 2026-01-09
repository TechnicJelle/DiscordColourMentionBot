import "dart:async";
import "dart:io";

import "package:nyxx/nyxx.dart";

import "emoji_cache.dart";

final RegExp hexColourRegex = RegExp("#[0-9a-fA-F]{6,8}");

Future<void> main(List<String> arguments) async {
  final String? token = Platform.environment["DISCORD_TOKEN"];
  if (token == null) {
    stderr.writeln("No DISCORD_TOKEN environment variable defined! Exiting...");
    return;
  }

  final NyxxGateway client = await Nyxx.connectGateway(
    token,
    GatewayIntents.allUnprivileged | GatewayIntents.messageContent,
    options: GatewayClientOptions(
      plugins: <NyxxPlugin<Nyxx>>[
        logging,
        cliIntegration,
        ignoreExceptions,
      ],
      emojiCacheConfig: const .new(maxSize: cacheSizeLimit),
    ),
  );

  final EmojiCache emojiCache = EmojiCache(client);
  await emojiCache.init();

  final User botUser = await client.users.fetchCurrentUser();

  client.onMessageCreate.listen((MessageCreateEvent event) async {
    //don't reply to own messages
    if (event.member?.id == botUser.id) return;

    final List<RegExpMatch> matches = hexColourRegex
        .allMatches(event.message.content)
        .toList(growable: false);

    //don't reply if there are no colours to render
    if (matches.isEmpty) return;

    final Set<String> colours = matches
        .map((RegExpMatch match) => match.group(0))
        .whereType<String>()
        .toSet();

    //20 is the maximum amount of reactions
    for (final String colour in colours.take(20)) {
      final Emoji? colourEmoji = await emojiCache.getEmojiForColour(colour);
      if (colourEmoji == null) continue;
      await event.message.react(ReactionBuilder.fromEmoji(colourEmoji));
    }
  });

  //click the reaction to remove it
  client.onMessageReactionAdd.listen((MessageReactionAddEvent event) {
    //check if message author reacted
    if (event.userId != event.messageAuthorId) return;

    //ensure that the reacted emoji is ours
    if (!emojiCache.isOurs(event.emoji)) return;

    unawaited(event.message.deleteReaction(ReactionBuilder.fromEmoji(event.emoji)));
  });
}
