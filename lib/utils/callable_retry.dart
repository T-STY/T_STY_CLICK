library;

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

const _retryableCodes = {'unavailable', 'deadline-exceeded', 'internal'};

Future<HttpsCallableResult> callIdempotentCallable(
  String name, {
  Map<String, dynamic>? parameters,
  int maxAttempts = 3,
}) async {
  for (var attempt = 1; ; attempt++) {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(name);
      return parameters == null
          ? await callable.call()
          : await callable.call(parameters);
    } on FirebaseFunctionsException catch (e) {
      final transient = _retryableCodes.contains(e.code);
      if (!transient || attempt >= maxAttempts) rethrow;
      await Future.delayed(Duration(milliseconds: 500 * attempt));
    }
  }
}
