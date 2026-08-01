import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import '../database/app_database.dart';
import 'connection.dart';

class ConnectionRegistry {
  final AppDatabase _db;
  ConnectionRegistry(this._db);

  Stream<List<Connection>> watchConnections() {
    return (_db.select(_db.connections)..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).watch().asyncMap(
      (rows) async => rows.map(_rowToConnection).whereType<Connection>().toList(),
    );
  }

  Future<List<Connection>> list() async {
    final rows = await (_db.select(_db.connections)..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();
    return rows.map(_rowToConnection).whereType<Connection>().toList();
  }

  Future<Connection?> get(String id) async {
    final row = await (_db.select(_db.connections)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return _rowToConnection(row);
  }

  Future<void> upsert(Connection connection) async {
    final row = ConnectionsCompanion(
      id: Value(connection.id),
      kind: Value(connection.kind.id),
      displayName: Value(connection.displayName),
      configJson: Value(jsonEncode(connection.toConfigJson())),
      isDefault: Value(true),
      createdAt: Value(connection.createdAt.millisecondsSinceEpoch),
      lastAuthenticatedAt: Value(connection.lastAuthenticatedAt?.millisecondsSinceEpoch),
    );
    await _db.into(_db.connections).insertOnConflictUpdate(row);
  }

  Future<void> remove(String id) async {
    await (_db.delete(_db.connections)..where((t) => t.id.equals(id))).go();
  }

  Connection? _rowToConnection(ConnectionRow row) {
    final config = jsonDecode(row.configJson) as Map<String, dynamic>;
    final kind = ConnectionKind.fromId(row.kind);
    final status = ConnectionStatus.unknown;
    final createdAt = DateTime.fromMillisecondsSinceEpoch(row.createdAt);
    final lastAuth = row.lastAuthenticatedAt != null ? DateTime.fromMillisecondsSinceEpoch(row.lastAuthenticatedAt!) : null;

    return switch (kind) {
      ConnectionKind.plex => PlexAccountConnection.fromConfigJson(
          row.id,
          config,
          status: status,
          createdAt: createdAt,
          lastAuthenticatedAt: lastAuth,
        ),
      ConnectionKind.jellyfin => JellyfinConnection.fromConfigJson(
          row.id,
          config,
          status: status,
          createdAt: createdAt,
          lastAuthenticatedAt: lastAuth,
        ),
    };
  }
}
