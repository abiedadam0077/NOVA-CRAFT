import 'dart:async';

/// Cooperative cancellation signal for a single install operation.
///
/// HTTP requests pass [whenCancelled] to `package:http`'s AbortableRequest so
/// cancelling an install aborts both response download and repository upload.
class CancellationToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const OperationCancelledException();
  }

  Future<void> waitOrCancel(Duration delay) async {
    if (isCancelled) throw const OperationCancelledException();
    await Future.any<void>(<Future<void>>[
      Future<void>.delayed(delay),
      whenCancelled.then<void>((_) => throw const OperationCancelledException()),
    ]);
    throwIfCancelled();
  }
}

class OperationCancelledException implements Exception {
  const OperationCancelledException();

  @override
  String toString() => 'Operation cancelled';
}
