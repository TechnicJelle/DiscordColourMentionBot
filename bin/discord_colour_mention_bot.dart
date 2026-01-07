import "dart:io";
import "dart:typed_data";

import "package:image/image.dart" as img;
import "package:nyxx/nyxx.dart";

final img.BitmapFont font = img.readFontZip(File("JBMono.zip").readAsBytesSync());
//the font is actually 40, but we add a little more for the extra spacing between the lines
const int textHeight = 48;

const int imageSize = 512;

const String deleteEmoji = "❌";

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
    options: GatewayClientOptions(plugins: <NyxxPlugin<Nyxx>>[logging, cliIntegration]),
  );

  final User botUser = await client.users.fetchCurrentUser();

  client.onMessageCreate.listen((MessageCreateEvent event) async {
    //don't reply to own messages
    if (event.member?.id == botUser.id) return;

    final List<RegExpMatch> matches = hexColourRegex
        .allMatches(event.message.content)
        .toList(growable: false);

    //don't reply if there are no colours to render
    if (matches.isEmpty) return;

    final List<AttachmentBuilder> attachments = <AttachmentBuilder>[];
    for (final RegExpMatch match in matches.take(9)) {
      final String? colour = match.group(0);
      if (colour == null) continue;
      final Uint8List? imageData = await generateImageForColour(colour);
      if (imageData == null) continue;
      final AttachmentBuilder attachment = AttachmentBuilder(
        data: imageData,
        fileName: "$colour.png",
      );
      attachments.add(attachment);
    }

    //don't reply if there ended up being no attachments generates
    if (attachments.isEmpty) return;

    final Message sentMessage = await event.message.channel.sendMessage(
      MessageBuilder(
        content:
            "This is what ${attachments.length > 1 ? "those colours" : "that colour"} look${attachments.length > 1 ? "" : "s"} like:",
        referencedMessage: MessageReferenceBuilder.reply(messageId: event.message.id),
        flags: MessageFlags.suppressNotifications,
        //no message sound (if you're in the channel)
        allowedMentions: AllowedMentions(),
        //no mention (ping)
        attachments: attachments,
      ),
    );

    await sentMessage.react(ReactionBuilder(name: deleteEmoji, id: null));
  });

  client.onMessageReactionAdd.listen((MessageReactionAddEvent event) async {
    //only delete on delete emoji
    if (event.emoji.name != deleteEmoji) return;

    //only delete own messages
    final Message colourBotMessage = await event.message.get();
    if (colourBotMessage.author.id != botUser.id) return;

    //not a reply
    final MessageReference? replyTo = colourBotMessage.reference;
    if (replyTo == null) return;
    final PartialMessage? replyMessage = replyTo.message;
    if (replyMessage == null) return;

    //only allow the original author delete the bot message
    final Message originalMessage = await replyMessage.get();
    if (event.userId != originalMessage.author.id) return;

    await event.message.delete();
  });
}

Future<Uint8List?> generateImageForColour(String hexString) async {
  final int? ox = int.tryParse(hexString.replaceFirst("#", "0x"));
  if (ox == null) return null;

  final img.Color colour;
  final String rgbString;
  if (hexString.length == 1 + 6) {
    final int b = ox & 255;
    final int g = (ox >> 8) & 255;
    final int r = (ox >> 16) & 255;
    colour = img.ColorRgb8(r, g, b);
    rgbString = "rgb($r,$g,$b)";
  } else if (hexString.length == 1 + 8) {
    final int a = ox & 255;
    final int b = (ox >> 8) & 255;
    final int g = (ox >> 16) & 255;
    final int r = (ox >> 24) & 255;
    colour = img.ColorRgba8(r, g, b, a);
    rgbString = "rgba($r,$g,$b,$a)";
  } else {
    return null;
  }

  final double luminance =
      (0.299 * colour.r + 0.587 * colour.g + 0.114 * colour.b) / 255;
  final img.Color textColour = luminance > 0.5
      ? img.ColorRgb8(0, 0, 0)
      : img.ColorRgb8(255, 255, 255);

  final img.Command command = img.Command()
    ..createImage(width: imageSize, height: imageSize, numChannels: 4)
    ..fill(color: colour)
    ..drawString(
      hexString,
      font: font,
      color: textColour,
      y: imageSize ~/ 2 - textHeight,
    )
    ..drawString(
      rgbString,
      font: font,
      color: textColour,
      y: imageSize ~/ 2,
    )
    ..encodePng();

  return command.getBytes();
}
