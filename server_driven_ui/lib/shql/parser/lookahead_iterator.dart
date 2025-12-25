/// LookaheadIterator: givs hasNext/next/peek on top of Iterator<T>.
class LookaheadIterator<T> {
  final Iterator<T> _it;
  bool _hasPeek = false;
  T? _peeked; // buffered next value
  T? _current; // latest returned value
  bool _done = false;

  LookaheadIterator(Iterable<T> source) : _it = source.iterator;
  LookaheadIterator.fromIterator(Iterator<T> it) : _it = it;

  /// Is there a next element?
  bool get hasNext {
    if (_done) return false;
    if (_hasPeek) return true;

    // Attempt to buffer next
    _hasPeek = _it.moveNext();
    if (_hasPeek) {
      _peeked = _it.current;
    } else {
      _done = true;
    }
    return _hasPeek;
  }

  /// Peek next element without consuming
  T peek() {
    if (!hasNext) {
      throw StateError('No more elements');
    }
    return _peeked as T;
  }

  /// Get and consume next element
  T next() {
    if (!hasNext) {
      throw StateError('No more elements');
    }
    _current = _peeked;
    _hasPeek = false; // vi har konsumerat bufferten
    return _current as T;
  }

  /// Latest returned element (after call to next()).
  T get current {
    final v = _current;
    if (v == null) {
      throw StateError('No current element. Call next() first.');
    }
    return v;
  }
}

/// Neat extension to get lookahead on any Iterable.
extension LookaheadExt<T> on Iterable<T> {
  LookaheadIterator<T> lookahead() => LookaheadIterator<T>(this);
}
