import "dart:async";
import "dart:io";
import "dart:math";

import "package:nyxx/nyxx.dart";

import "reply_mechanisms.dart";

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
    ),
  );

  //TODO: Not this
  final ReplyMechanism replyMechanism = Random().nextBool()
      ? AttachmentReplyMechanism(client: client)
      : EmojiReplyMechanism(client: client);
  await replyMechanism.init();

  final User botUser = await client.users.fetchCurrentUser();

  client.onMessageCreate.listen((MessageCreateEvent event) async {
    //don't reply to own messages
    if (event.member?.id == botUser.id) return;

    final List<RegExpMatch> matches = hexColourRegex
        .allMatches(event.message.content)
        .toList(growable: false);

    //don't reply if there are no colours to show
    if (matches.isEmpty) return;

    final Set<String> colours = matches
        .map((RegExpMatch match) => match.group(0))
        .whereType<String>()
        .toSet();

    await replyMechanism.doTheReply(event, colours);
  });

  //click the reaction to remove the reply
  client.onMessageReactionAdd.listen(replyMechanism.handleReactionAdd);
}
