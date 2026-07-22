/// Retry wrapper for IDEMPOTENT Cloud Functions callables.
///
/// At cold launch a callable often races the network coming up or a
/// scaled-to-zero 2nd-gen function spinning up, which surfaces as
/// `unavailable` / `deadline-exceeded` / `internal`. A couple of short
/// retries let the call self-heal instead of failing on first use.
///
/// ⚠️ USE ONLY FOR READ-ONLY / IDEMPOTENT calls (e.g. `getRewardsBalance`).
/// Do NOT wrap mutations like `placeOrder`, `claimCoupon`, or
/// `createRewardsWallet`: if the first attempt actually succeeded server-side
/// but the response was lost, a silent retry would double-apply (duplicate
/// order, double-claim, etc.). Those keep their own explicit, user-facing
/// error handling.
library;

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

/// Transient FCM/Functions error codes worth retrying.
const _retryableCodes = {'unavailable', 'deadline-exceeded', 'internal'};

/// Calls [name] with up to [maxAttempts] tries, backing off 500ms × attempt
/// between transient failures. Non-transient errors (permission-denied,
/// unauthenticated, invalid-argument, …) throw immediately. On the final
/// failed attempt the last exception is rethrown so the caller can handle it.
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
