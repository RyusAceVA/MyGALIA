import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mygalia/core/network/failure.dart';

DioException _dio(DioExceptionType type, [Object? error]) => DioException(
      requestOptions: RequestOptions(path: 'https://expernet.sc-form.net/'),
      type: type,
      error: error,
    );

void main() {
  test('un timeout est une erreur réseau transitoire', () {
    final Failure failure =
        failureFromDioException(_dio(DioExceptionType.receiveTimeout));

    expect(failure, isA<NetworkFailure>());
    expect((failure as NetworkFailure).issue, NetworkIssue.timeout);
    expect(failure.isTransient, isTrue);
  });

  test('un échec DNS est classé « pas de réseau » et garde sa cause', () {
    final DioException error = _dio(
      DioExceptionType.connectionError,
      const SocketException("Failed host lookup: 'expernet.sc-form.net'"),
    );

    final Failure failure = failureFromDioException(error);

    expect(failure, isA<NetworkFailure>());
    expect((failure as NetworkFailure).issue, NetworkIssue.offline);
    expect(failure.cause, same(error));
  });

  test('une coupure en cours de réponse est réseau, pas « inconnue »', () {
    final Failure failure = failureFromDioException(
      _dio(
        DioExceptionType.unknown,
        const HttpException('Connection closed before full header was received'),
      ),
    );

    expect(failure, isA<NetworkFailure>());
    expect((failure as NetworkFailure).issue, NetworkIssue.interrupted);
    expect(failure.isTransient, isTrue);
  });

  test("une annulation n'est pas présentée comme une erreur réseau", () {
    expect(
      failureFromDioException(_dio(DioExceptionType.cancel)),
      isA<CancelledFailure>(),
    );
  });

  test('5xx transitoire, 4xx non transitoire', () {
    expect(ServerFailure.status(503).isTransient, isTrue);
    expect(ServerFailure.status(404).isTransient, isFalse);
  });

  test('identifiants refusés et données illisibles ne sont jamais relancés', () {
    expect(const InvalidCredentialsFailure('refusé').isTransient, isFalse);
    expect(const DataFailure('illisible').isTransient, isFalse);
    expect(const SessionFailure('session').isTransient, isFalse);
  });
}
