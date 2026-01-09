import "dart:async";

import "package:nyxx/nyxx.dart";

import "reply_caches.dart";

abstract class ReplyMechanism {
  late final User _botUser;

  Future<void> init({required User botUser}) async {
    _botUser = botUser;
  }

  Future<void> doTheReply(MessageCreateEvent event, Set<String> colours);

  Future<void> handleReactionAdd(MessageReactionAddEvent event);
}

class EmojiReplyMechanism extends ReplyMechanism {
  final EmojiReplyCache _emojiCache;

  EmojiReplyMechanism({required NyxxGateway client})
    : _emojiCache = EmojiReplyCache(client: client);

  @override
  Future<void> init({required User botUser}) async {
    await super.init(botUser: botUser);
    await _emojiCache.init();
  }

  @override
  Future<void> doTheReply(MessageCreateEvent event, Set<String> colours) async {
    //20 is the maximum amount of reactions
    for (final String colour in colours.take(20)) {
      final Emoji? colourEmoji = await _emojiCache.getReplyForColour(colour);
      if (colourEmoji == null) continue;
      await event.message.react(ReactionBuilder.fromEmoji(colourEmoji));
    }
  }

  @override
  Future<void> handleReactionAdd(MessageReactionAddEvent event) async {
    //check if message author reacted
    if (event.userId != event.messageAuthorId) return;

    //ensure we don't handle the bot's own reactions
    //e.g. the AttachmentReplyMechanism's deleteEmoji
    if (event.userId == _botUser.id) return;

    //ensure that the reacted emoji is ours
    if (!_emojiCache.isOurs(event.emoji)) return;

    await event.message.deleteReaction(ReactionBuilder.fromEmoji(event.emoji));
  }
}

class AttachmentReplyMechanism extends ReplyMechanism {
  static const String deleteEmoji = "❌";

  final AttachmentReplyCache _attachmentCache;

  AttachmentReplyMechanism({required NyxxGateway client})
    : _attachmentCache = AttachmentReplyCache(client: client);

  @override
  Future<void> init({required User botUser}) async {
    await super.init(botUser: botUser);
    await _attachmentCache.init();
  }

  @override
  Future<void> doTheReply(MessageCreateEvent event, Set<String> colours) async {
    final List<AttachmentBuilder> attachments = <AttachmentBuilder>[];
    for (final String colour in colours.take(9)) {
      final AttachmentBuilder? attachment = await _attachmentCache.getReplyForColour(colour);
      if (attachment == null) return;
      attachments.add(attachment);
    }

    //don't reply if there ended up being no attachments generated
    if (attachments.isEmpty) return;

    final Message sentMessage = await event.message.channel.sendMessage(
      MessageBuilder(
        content:
            "This is what${colours.length > 9 ? " (the first nine of)" : ""} ${attachments.length > 1 ? "those colours" : "that colour"} look${attachments.length > 1 ? "" : "s"} like:",
        referencedMessage: MessageReferenceBuilder.reply(messageId: event.message.id),
        flags: MessageFlags.suppressNotifications,
        //no message sound (if you're in the channel)
        allowedMentions: AllowedMentions(),
        //no mention (ping)
        attachments: attachments,
      ),
    );

    await sentMessage.react(ReactionBuilder(name: deleteEmoji, id: null));
  }

  @override
  Future<void> handleReactionAdd(MessageReactionAddEvent event) async {
    //only delete on delete emoji
    if (event.emoji.name != deleteEmoji) return;

    //only delete own messages
    final Message colourBotMessage = await event.message.get();
    if (colourBotMessage.author.id != _botUser.id) return;

    //not a reply
    final MessageReference? replyTo = colourBotMessage.reference;
    if (replyTo == null) return;
    final PartialMessage? replyMessage = replyTo.message;
    if (replyMessage == null) return;

    //only allow the original author delete the bot message
    final Message originalMessage = await replyMessage.get();
    if (event.userId != originalMessage.author.id) return;

    await event.message.delete();
  }
}
