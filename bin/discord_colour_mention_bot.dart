import "dart:async";
import "dart:io";

import "package:nyxx/nyxx.dart";
import "package:nyxx_commands/nyxx_commands.dart";

import "preferences.dart";
import "reply_mechanisms.dart";

const String versionDevelopment = "development";
const String version = String.fromEnvironment("version", defaultValue: versionDevelopment);

final RegExp hexColourRegex = RegExp("#[0-9a-fA-F]{6,8}");

Future<void> main(List<String> arguments) async {
  final String? token = Platform.environment["DISCORD_TOKEN"];
  if (token == null) {
    stderr.writeln("No DISCORD_TOKEN environment variable defined! Exiting...");
    return;
  }

  Preferences(); //init the singleton

  final CommandsPlugin commands = CommandsPlugin(
    prefix: mentionOr((_) => "!"),
    options: const CommandsOptions(
      defaultResponseLevel: .hint,
    ),
  )..addCommand(Preferences.instance.changeReplyMechanismCommand);

  final NyxxGateway client = await Nyxx.connectGateway(
    token,
    GatewayIntents.allUnprivileged | GatewayIntents.messageContent,
    options: GatewayClientOptions(
      plugins: <NyxxPlugin<Nyxx>>[
        logging,
        cliIntegration,
        ignoreExceptions,
        commands,
      ],
    ),
  );

  await client.application.manager.updateCurrentApplication(
    ApplicationUpdateBuilder(
      description:
          """
This bot displays colour codes in messages!
Try typing #123456 or any other colour code (#RRGGBB or #RRGGBBAA)

**Bot information:**
https://github.com/TechnicJelle/DiscordColourMentionBot
Version: `$version`
"""
              .trim(),
    ),
  );

  final User botUser = await client.users.fetchCurrentUser();
  await ReplyMechanisms.init(client: client, botUser: botUser);

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

    final ReplyMechanism replyMechanism = ReplyMechanisms.getFor(event);
    await replyMechanism.doTheReply(event, colours);
  });

  //click the reaction to remove the reply
  client.onMessageReactionAdd.listen(
    (MessageReactionAddEvent event) {
      for (final ReplyMechanism replyMechanism in ReplyMechanisms.all()) {
        unawaited(replyMechanism.handleReactionAdd(event));
      }
    },
  );
}
