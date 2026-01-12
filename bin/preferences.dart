import "dart:convert";
import "dart:io";

import "package:nyxx/nyxx.dart";
import "package:nyxx_commands/nyxx_commands.dart";

import "reply_mechanisms.dart";

class Preferences {
  ///singleton
  static late final Preferences instance;

  ///the reply-mechanism preference of the "place" to which this snowflake belongs (guild or dm channel)
  late final Map<Snowflake, ReplyMechanisms> _placeReplyMechanismPreference;
  static final File _replyMechanismFile = File("prefs/reply_mechanism.json");

  Preferences() {
    instance = this;
    _deserialize();
  }

  void _serialize() {
    //convert our map to a serializable format
    final Map<String, ReplyMechanisms> data = _placeReplyMechanismPreference.map(
      (Snowflake key, ReplyMechanisms value) => .new(jsonEncode(key.value), value),
    );

    //encode our data to json
    final String json = jsonEncode(data);

    //ensure the file and its directory exist and write to disk
    _replyMechanismFile
      ..createSync(recursive: true)
      ..writeAsStringSync(json);
  }

  void _deserialize() {
    if (!_replyMechanismFile.existsSync()) {
      //if we don't have prefs, we just init as an empty map
      _placeReplyMechanismPreference = <Snowflake, ReplyMechanisms>{};
    } else {
      //we have prefs, so we load it from disk
      final String json = _replyMechanismFile.readAsStringSync();

      //decode the json
      final Map<String, dynamic> data = jsonDecode(json) as Map<String, dynamic>;

      //further decode and save into our map
      _placeReplyMechanismPreference = data.map(
        (String key, dynamic value) => .new(
          Snowflake(jsonDecode(key) as int),
          ReplyMechanisms.fromJson(value.toString()),
        ),
      );
    }
  }

  ReplyMechanisms getReplyMechanismFor(MessageCreateEvent event) {
    final PartialGuild? guild = event.guild;
    //if guild is null, it was in a DM, which we saved the channel.id of in the command just below here, so we can get it
    if (guild == null) {
      final Snowflake channelId = event.message.channelId;
      return _placeReplyMechanismPreference[channelId] ?? defaultReplyMechanism;
    }
    return _placeReplyMechanismPreference[guild.id] ?? defaultReplyMechanism;
  }

  ChatCommand get changeReplyMechanismCommand => ChatCommand(
    "reply-mechanism",
    "Change how the bot should show colours",
    id(
      "reply-mechanism",
      (
        ChatContext context,
        @UseConverter(_replyMechanismsConverter)
        @Description("How should the bot show colours?")
        ReplyMechanisms mechanism,
      ) async {
        //if it's a DM with the bot, guild will be null, so we take the channel ID instead
        final Snowflake guildId = context.guild?.id ?? context.channel.id;

        _placeReplyMechanismPreference[guildId] = mechanism;

        //it's fine to just re-save the whole thing every time it's changed.
        //also helps prevent data loss if the bot gets forcefully shut down
        _serialize();

        await context.respond(MessageBuilder(content: "Set to `${mechanism.name}`"));
      },
    ),
    //only allow admins to run the command
    //server admins can assign specific roles to the command
    checks: <AbstractCheck>[PermissionsCheck.nobody()],
  );
}

String _replyMechanismsToString(ReplyMechanisms type) => type.name;

const SimpleConverter<ReplyMechanisms> _replyMechanismsConverter = .fixed(
  elements: ReplyMechanisms.values,
  stringify: _replyMechanismsToString,
);
