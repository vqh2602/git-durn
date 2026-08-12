import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

class RecentRepository {
  const RecentRepository({
    required this.path,
    required this.name,
    required this.lastOpenedAt,
    this.remoteUrl,
    this.currentBranch,
    this.isFavorite = false,
  });

  final String path;
  final String name;
  final String? remoteUrl;
  final String? currentBranch;
  final DateTime lastOpenedAt;
  final bool isFavorite;
}

class AppDatabase {
  AppDatabase._(this._database) {
    _migrate();
  }

  final Database _database;

  static Future<AppDatabase> open() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final databaseDirectory = Directory(
      p.join(supportDirectory.path, 'Git Desktop'),
    );
    await databaseDirectory.create(recursive: true);
    return AppDatabase._(
      sqlite3.open(p.join(databaseDirectory.path, 'app.db')),
    );
  }

  static AppDatabase inMemory() => AppDatabase._(sqlite3.openInMemory());

  void _migrate() {
    _database.execute('''
      CREATE TABLE IF NOT EXISTS repositories (
        path TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        remote_url TEXT,
        current_branch TEXT,
        last_opened_at INTEGER NOT NULL,
        is_favorite INTEGER NOT NULL DEFAULT 0
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS app_preferences (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  List<RecentRepository> listRecentRepositories({int limit = 30}) {
    final result = _database.select(
      '''
        SELECT path, name, remote_url, current_branch, last_opened_at, is_favorite
        FROM repositories
        ORDER BY is_favorite DESC, last_opened_at DESC
        LIMIT ?
      ''',
      <Object?>[limit],
    );
    return List<RecentRepository>.unmodifiable(
      result.map(
        (row) => RecentRepository(
          path: row['path'] as String,
          name: row['name'] as String,
          remoteUrl: row['remote_url'] as String?,
          currentBranch: row['current_branch'] as String?,
          lastOpenedAt: DateTime.fromMillisecondsSinceEpoch(
            row['last_opened_at'] as int,
          ),
          isFavorite: (row['is_favorite'] as int) == 1,
        ),
      ),
    );
  }

  void upsertRepository(RecentRepository repository) {
    _database.execute(
      '''
        INSERT INTO repositories (
          path, name, remote_url, current_branch, last_opened_at, is_favorite
        ) VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(path) DO UPDATE SET
          name = excluded.name,
          remote_url = excluded.remote_url,
          current_branch = excluded.current_branch,
          last_opened_at = excluded.last_opened_at
      ''',
      <Object?>[
        repository.path,
        repository.name,
        repository.remoteUrl,
        repository.currentBranch,
        repository.lastOpenedAt.millisecondsSinceEpoch,
        repository.isFavorite ? 1 : 0,
      ],
    );
  }

  void removeRepository(String path) {
    _database.execute('DELETE FROM repositories WHERE path = ?', <Object?>[
      path,
    ]);
  }

  void setFavorite(String path, {required bool isFavorite}) {
    _database.execute(
      'UPDATE repositories SET is_favorite = ? WHERE path = ?',
      <Object?>[isFavorite ? 1 : 0, path],
    );
  }

  String? readPreference(String key) {
    final rows = _database.select(
      'SELECT value FROM app_preferences WHERE key = ?',
      <Object?>[key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void writePreference(String key, String value) {
    _database.execute(
      'INSERT INTO app_preferences (key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      <Object?>[key, value],
    );
  }

  void deletePreference(String key) {
    _database.execute('DELETE FROM app_preferences WHERE key = ?', <Object?>[
      key,
    ]);
  }

  void close() => _database.close();
}
