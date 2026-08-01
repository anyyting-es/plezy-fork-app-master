enum ConnectionKind {
  plex,
  jellyfin;

  String get id => switch (this) {
    ConnectionKind.plex => 'plex',
    ConnectionKind.jellyfin => 'jellyfin',
  };

  static ConnectionKind fromId(String id) => switch (id) {
    'plex' => ConnectionKind.plex,
    'jellyfin' => ConnectionKind.jellyfin,
    _ => throw ArgumentError('Unknown ConnectionKind id: $id'),
  };
}

enum ConnectionStatus { unknown, online, offline, authError, disabled }

sealed class Connection {
  String get id;
  ConnectionKind get kind;
  String get displayName;
  ConnectionStatus get status;
  DateTime get createdAt;
  DateTime? get lastAuthenticatedAt;

  String get displayLabel;
  String? get displaySubtitle;

  Map<String, Object?> toConfigJson();
}

class PlexAccountConnection extends Connection {
  @override
  final String id;
  @override
  final ConnectionStatus status;
  @override
  final DateTime createdAt;
  @override
  final DateTime? lastAuthenticatedAt;

  final String accountToken;
  final String clientIdentifier;
  final String accountLabel;
  final List<dynamic> servers = const [];

  PlexAccountConnection({
    required this.id,
    required this.status,
    required this.createdAt,
    this.lastAuthenticatedAt,
    required this.accountToken,
    required this.clientIdentifier,
    required this.accountLabel,
  });

  @override
  ConnectionKind get kind => ConnectionKind.plex;

  @override
  String get displayName => accountLabel;

  @override
  String get displayLabel => accountLabel;

  @override
  String? get displaySubtitle => 'Plex';

  @override
  Map<String, Object?> toConfigJson() => {
    'accountToken': accountToken,
    'clientIdentifier': clientIdentifier,
    'accountLabel': accountLabel,
  };

  factory PlexAccountConnection.fromConfigJson(String id, Map<String, dynamic> json, {required ConnectionStatus status, required DateTime createdAt, DateTime? lastAuthenticatedAt}) {
    return PlexAccountConnection(
      id: id,
      status: status,
      createdAt: createdAt,
      lastAuthenticatedAt: lastAuthenticatedAt,
      accountToken: json['accountToken'] as String? ?? '',
      clientIdentifier: json['clientIdentifier'] as String? ?? '',
      accountLabel: json['accountLabel'] as String? ?? '',
    );
  }
}

class JellyfinConnection extends Connection {
  @override
  final String id;
  @override
  final ConnectionStatus status;
  @override
  final DateTime createdAt;
  @override
  final DateTime? lastAuthenticatedAt;

  final String serverName;
  final String serverMachineId;
  final String baseUrl;
  final String username;
  final String accessToken;

  JellyfinConnection({
    required this.id,
    required this.status,
    required this.createdAt,
    this.lastAuthenticatedAt,
    required this.serverName,
    required this.serverMachineId,
    required this.baseUrl,
    required this.username,
    required this.accessToken,
  });

  @override
  ConnectionKind get kind => ConnectionKind.jellyfin;

  @override
  String get displayName => serverName;

  @override
  String get displayLabel => serverName;

  @override
  String? get displaySubtitle => username;

  @override
  Map<String, Object?> toConfigJson() => {
    'serverName': serverName,
    'serverMachineId': serverMachineId,
    'baseUrl': baseUrl,
    'username': username,
    'accessToken': accessToken,
  };

  factory JellyfinConnection.fromConfigJson(String id, Map<String, dynamic> json, {required ConnectionStatus status, required DateTime createdAt, DateTime? lastAuthenticatedAt}) {
    return JellyfinConnection(
      id: id,
      status: status,
      createdAt: createdAt,
      lastAuthenticatedAt: lastAuthenticatedAt,
      serverName: json['serverName'] as String? ?? '',
      serverMachineId: json['serverMachineId'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? '',
      username: json['username'] as String? ?? '',
      accessToken: json['accessToken'] as String? ?? '',
    );
  }
}
