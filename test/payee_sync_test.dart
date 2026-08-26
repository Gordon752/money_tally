import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/user_preferences.dart';

void main() {
  group('payee catalog causal sync', () {
    var operation = 0;

    String nextOperationId() {
      operation += 1;
      return 'device-a-${operation.toString().padLeft(3, '0')}';
    }

    setUp(() => operation = 0);

    test('add archive restore delete and later re-add advance authority', () {
      var preferences = const UserPreferences();

      preferences = reconcilePayeeCatalogMutation(
        current: preferences,
        requested: preferences.copyWith(savedPayeeNames: const ['Acme']),
        newOperationId: nextOperationId,
      );
      expect(preferences.savedPayeeNames, ['Acme']);
      expect(
        preferences.payeeCatalogStates['acme']?.status,
        PayeeCatalogStatus.active,
      );
      expect(preferences.payeeCatalogStates['acme']?.revision, 1);

      preferences = reconcilePayeeCatalogMutation(
        current: preferences,
        requested: preferences.copyWith(archivedPayeeNames: const {'acme'}),
        newOperationId: nextOperationId,
      );
      expect(preferences.archivedPayeeNames, {'acme'});
      expect(
        preferences.payeeCatalogStates['acme']?.status,
        PayeeCatalogStatus.archived,
      );
      expect(preferences.payeeCatalogStates['acme']?.revision, 2);

      preferences = reconcilePayeeCatalogMutation(
        current: preferences,
        requested: preferences.copyWith(archivedPayeeNames: const {}),
        newOperationId: nextOperationId,
      );
      expect(preferences.archivedPayeeNames, isEmpty);
      expect(
        preferences.payeeCatalogStates['acme']?.status,
        PayeeCatalogStatus.active,
      );
      expect(preferences.payeeCatalogStates['acme']?.revision, 3);

      preferences = reconcilePayeeCatalogMutation(
        current: preferences,
        requested: preferences.copyWith(
          savedPayeeNames: const [],
          deletedPayeeNames: const {'acme'},
        ),
        newOperationId: nextOperationId,
      );
      expect(preferences.savedPayeeNames, isEmpty);
      expect(preferences.deletedPayeeNames, {'acme'});
      expect(
        preferences.payeeCatalogStates['acme']?.status,
        PayeeCatalogStatus.deleted,
      );
      expect(preferences.payeeCatalogStates['acme']?.revision, 4);

      preferences = reconcilePayeeCatalogMutation(
        current: preferences,
        requested: preferences.copyWith(
          savedPayeeNames: const ['Acme'],
          deletedPayeeNames: const {},
        ),
        newOperationId: nextOperationId,
      );
      expect(preferences.savedPayeeNames, ['Acme']);
      expect(preferences.deletedPayeeNames, isEmpty);
      expect(
        preferences.payeeCatalogStates['acme']?.status,
        PayeeCatalogStatus.active,
      );
      expect(preferences.payeeCatalogStates['acme']?.revision, 5);
    });

    test('newer delete beats stale active state on every device', () {
      const staleActive = UserPreferences(
        payeeCatalogStates: {
          'acme': PayeeCatalogState(
            displayName: 'Acme',
            status: PayeeCatalogStatus.active,
            revision: 1,
            operationId: 'device-a-001',
          ),
        },
      );
      const newerDelete = UserPreferences(
        payeeCatalogStates: {
          'acme': PayeeCatalogState(
            displayName: 'Acme',
            status: PayeeCatalogStatus.deleted,
            revision: 2,
            operationId: 'device-b-002',
          ),
        },
      );

      final mergedA = mergePayeeCatalogPreferences(
        preferred: staleActive,
        other: newerDelete,
      );
      final mergedB = mergePayeeCatalogPreferences(
        preferred: newerDelete,
        other: staleActive,
      );

      for (final merged in [mergedA, mergedB]) {
        expect(merged.savedPayeeNames, isEmpty);
        expect(merged.deletedPayeeNames, {'acme'});
        expect(
          merged.payeeCatalogStates['acme']?.status,
          PayeeCatalogStatus.deleted,
        );
      }
    });

    test('later legitimate re-add supersedes an older delete', () {
      const olderDelete = UserPreferences(
        payeeCatalogStates: {
          'acme': PayeeCatalogState(
            displayName: 'Acme',
            status: PayeeCatalogStatus.deleted,
            revision: 2,
            operationId: 'device-a-002',
          ),
        },
      );
      const newerReAdd = UserPreferences(
        payeeCatalogStates: {
          'acme': PayeeCatalogState(
            displayName: 'Acme',
            status: PayeeCatalogStatus.active,
            revision: 3,
            operationId: 'device-b-003',
          ),
        },
      );

      final merged = mergePayeeCatalogPreferences(
        preferred: olderDelete,
        other: newerReAdd,
      );

      expect(merged.savedPayeeNames, ['Acme']);
      expect(merged.deletedPayeeNames, isEmpty);
      expect(
        merged.payeeCatalogStates['acme']?.status,
        PayeeCatalogStatus.active,
      );
    });

    test('equal revisions converge by operation id regardless of order', () {
      const archived = UserPreferences(
        payeeCatalogStates: {
          'acme': PayeeCatalogState(
            displayName: 'Acme',
            status: PayeeCatalogStatus.archived,
            revision: 4,
            operationId: 'device-a-operation',
          ),
        },
      );
      const restored = UserPreferences(
        payeeCatalogStates: {
          'acme': PayeeCatalogState(
            displayName: 'Acme',
            status: PayeeCatalogStatus.active,
            revision: 4,
            operationId: 'device-z-operation',
          ),
        },
      );

      final first = mergePayeeCatalogPreferences(
        preferred: archived,
        other: restored,
      );
      final second = mergePayeeCatalogPreferences(
        preferred: restored,
        other: archived,
      );

      expect(first.payeeCatalogStates, second.payeeCatalogStates);
      expect(first.archivedPayeeNames, isEmpty);
      expect(first.savedPayeeNames, ['Acme']);
    });

    test('field merge preserves preferred non-payee settings', () {
      const local = UserPreferences(showRunningBalance: true);
      const remote = UserPreferences(
        showRunningBalance: false,
        payeeCatalogStates: {
          'market': PayeeCatalogState(
            displayName: 'Market',
            status: PayeeCatalogStatus.active,
            revision: 1,
            operationId: 'remote-001',
          ),
        },
      );

      final merged = mergePayeeCatalogPreferences(
        preferred: local,
        other: remote,
      );

      expect(merged.showRunningBalance, isTrue);
      expect(merged.savedPayeeNames, ['Market']);
    });

    test('legacy payee lists participate in causal merge', () {
      const legacy = UserPreferences(
        savedPayeeNames: ['Legacy Cafe'],
        archivedPayeeNames: {'legacy cafe'},
      );
      const modern = UserPreferences(
        payeeCatalogStates: {
          'legacy cafe': PayeeCatalogState(
            displayName: 'Legacy Cafe',
            status: PayeeCatalogStatus.active,
            revision: 1,
            operationId: 'modern-001',
          ),
        },
      );

      final merged = mergePayeeCatalogPreferences(
        preferred: legacy,
        other: modern,
      );

      expect(merged.savedPayeeNames, ['Legacy Cafe']);
      expect(merged.archivedPayeeNames, isEmpty);
      expect(merged.payeeCatalogStates['legacy cafe']?.revision, 1);
    });
  });
}
