import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop_client/core/storage/database.dart';

void main() {
  test('stores, favorites, and removes repository metadata', () {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    database.upsertRepository(
      RecentRepository(
        path: '/tmp/repository',
        name: 'repository',
        currentBranch: 'main',
        lastOpenedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      ),
    );

    expect(database.listRecentRepositories().single.currentBranch, 'main');
    database.setFavorite('/tmp/repository', isFavorite: true);
    expect(database.listRecentRepositories().single.isFavorite, isTrue);
    database.removeRepository('/tmp/repository');
    expect(database.listRecentRepositories(), isEmpty);
  });
}
