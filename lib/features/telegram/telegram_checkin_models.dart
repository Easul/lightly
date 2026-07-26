class TelegramCheckinTarget {
  const TelegramCheckinTarget({
    required this.id,
    required this.username,
    required this.command,
    this.enabled = true,
  });

  final String id;
  final String username;
  final String command;
  final bool enabled;

  TelegramCheckinTarget copyWith({
    String? username,
    String? command,
    bool? enabled,
  }) {
    return TelegramCheckinTarget(
      id: id,
      username: username ?? this.username,
      command: command ?? this.command,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'username': username,
    'command': command,
    'enabled': enabled,
  };

  factory TelegramCheckinTarget.fromJson(Map<String, dynamic> json) {
    return TelegramCheckinTarget(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      command: json['command'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

class TelegramCheckinConfig {
  const TelegramCheckinConfig({
    this.apiId = 0,
    this.apiHash = '',
    this.phoneNumber = '',
    this.targets = const <TelegramCheckinTarget>[],
  });

  final int apiId;
  final String apiHash;
  final String phoneNumber;
  final List<TelegramCheckinTarget> targets;

  bool get hasApiCredentials => apiId > 0 && apiHash.trim().isNotEmpty;

  TelegramCheckinConfig copyWith({
    int? apiId,
    String? apiHash,
    String? phoneNumber,
    List<TelegramCheckinTarget>? targets,
  }) {
    return TelegramCheckinConfig(
      apiId: apiId ?? this.apiId,
      apiHash: apiHash ?? this.apiHash,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      targets: targets ?? this.targets,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'apiId': apiId,
    'apiHash': apiHash,
    'phoneNumber': phoneNumber,
    'targets': targets.map((target) => target.toJson()).toList(),
  };

  factory TelegramCheckinConfig.fromJson(Map<String, dynamic> json) {
    return TelegramCheckinConfig(
      apiId: (json['apiId'] as num?)?.toInt() ?? 0,
      apiHash: json['apiHash'] as String? ?? '',
      phoneNumber: json['phoneNumber'] as String? ?? '',
      targets: (json['targets'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (item) => TelegramCheckinTarget.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
    );
  }
}

class TelegramChatSummary {
  const TelegramChatSummary({
    required this.id,
    required this.title,
    required this.lastMessage,
    required this.date,
    required this.unreadCount,
  });

  final int id;
  final String title;
  final String lastMessage;
  final DateTime? date;
  final int unreadCount;
}

class TelegramMessagePreview {
  const TelegramMessagePreview({
    required this.id,
    required this.text,
    required this.date,
    this.isOutgoing = false,
  });

  final int id;
  final String text;
  final DateTime date;
  final bool isOutgoing;
}
