import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/network/retry_policy.dart';

void main() {
  const RetryPolicy policy = RetryPolicy(delays: [Duration.zero, Duration.zero]);

  test('erreur transitoire puis succès : relancée', () async {
    int attempts = 0;

    final String result = await policy.run('test', () async {
      if (++attempts < 3) throw NetworkFailure.timeout();
      return 'ok';
    });

    expect(result, 'ok');
    expect(attempts, 3);
  });

  test('deux relances au maximum', () async {
    int attempts = 0;

    await expectLater(
      policy.run<void>('test', () async {
        attempts++;
        throw ServerFailure.status(503);
      }),
      throwsA(isA<ServerFailure>()),
    );
    expect(attempts, 3);
  });

  test('identifiants refusés : jamais relancés', () async {
    int attempts = 0;

    await expectLater(
      policy.run<void>('test', () async {
        attempts++;
        throw const InvalidCredentialsFailure('refusé');
      }),
      throwsA(isA<InvalidCredentialsFailure>()),
    );
    expect(attempts, 1);
  });

  test('4xx, session, données illisibles : jamais relancés', () async {
    for (final Failure failure in [
      ServerFailure.status(404),
      const SessionFailure('session'),
      const DataFailure('illisible'),
    ]) {
      int attempts = 0;
      await expectLater(
        policy.run<void>('test', () async {
          attempts++;
          throw failure;
        }),
        throwsA(same(failure)),
      );
      expect(attempts, 1, reason: failure.runtimeType.toString());
    }
  });

  test('hors ligne : aucune relance', () async {
    final RetryPolicy offline = RetryPolicy(
      delays: const [Duration.zero, Duration.zero],
      isOffline: () => true,
    );
    int attempts = 0;

    await expectLater(
      offline.run<void>('test', () async {
        attempts++;
        throw NetworkFailure.offline();
      }),
      throwsA(isA<NetworkFailure>()),
    );
    expect(attempts, 1);
  });

  test('annulation pendant l\'attente : arrêt sans nouvel essai', () async {
    final CancelToken token = CancelToken();
    const RetryPolicy slow = RetryPolicy(
      delays: [Duration(milliseconds: 100), Duration(milliseconds: 100)],
    );
    int attempts = 0;

    final Future<void> run = slow.run<void>('test', () async {
      attempts++;
      throw NetworkFailure.timeout();
    }, cancelToken: token);
    token.cancel();

    await expectLater(run, throwsA(isA<CancelledFailure>()));
    expect(attempts, 1);
  });
}
