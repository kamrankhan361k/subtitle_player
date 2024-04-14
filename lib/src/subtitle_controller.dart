import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:subtitle_player/subtitle_player.dart';

/// Holds the subtitle ranges, current subtitle
/// and index of current subtitle at any given point
/// in the synchronization.
class SubtitlePlayerValue {
  const SubtitlePlayerValue({
    required this.subtitleRanges,
    required this.currentSubtitle,
    required this.currentSubtitleIndex,
  });

  factory SubtitlePlayerValue.empty() {
    return const SubtitlePlayerValue(
      subtitleRanges: [],
      currentSubtitle: '',
      currentSubtitleIndex: -1,
    );
  }

  final List<SubtitleRange> subtitleRanges;
  final String currentSubtitle;
  final int currentSubtitleIndex;

  SubtitlePlayerValue copyWith({
    List<SubtitleRange>? subtitleRanges,
    String? currentSubtitle,
    int? currentSubtitleIndex,
  }) {
    return SubtitlePlayerValue(
      subtitleRanges: subtitleRanges ?? this.subtitleRanges,
      currentSubtitle: currentSubtitle ?? this.currentSubtitle,
      currentSubtitleIndex: currentSubtitleIndex ?? this.currentSubtitleIndex,
    );
  }

  @override
  int get hashCode => Object.hashAll([
        subtitleRanges,
        currentSubtitle,
        currentSubtitleIndex,
      ]);

  @override
  bool operator ==(Object other) {
    return other is SubtitlePlayerValue &&
        currentSubtitle == other.currentSubtitle &&
        currentSubtitleIndex == other.currentSubtitleIndex &&
        other.subtitleRanges
            .every((element) => subtitleRanges.contains(element));
  }

  @override
  String toString() {
    return 'SubtitlePlayerValue(currentSubtitleIndex: $currentSubtitleIndex, currentSubtitle: $currentSubtitle, subtitleRanges: $subtitleRanges)';
  }
}

/// Controller for synchronizing song lyrics and subtitles
/// with audio and video players.
class SubtitleController extends ValueNotifier<SubtitlePlayerValue> {
  SubtitleController() : super(SubtitlePlayerValue.empty());
  bool _disposed = false;
  Timer? _timer;
  Timer? _seekTimer;

  Subtitle? _subtitle;
  int _currentSubtitleRangeIndex = 0;

  bool _shouldLoop = false;

  bool get _abort => _currentSubtitleRangeIndex == -1;

  /// Load subtitle content.
  ///
  /// Use:
  /// [Subtitle.fromWebVTT] for WebVTT (.vtt) subtitle files
  /// [Subtitle.fromSubRip] for SubRip (.srt) subtitle files
  /// [Subtitle.fromLyrics] for LRC (.lrc) subtitle files
  void loadSubtitle(Subtitle subtitle) {
    _subtitle = subtitle;
    _updateValueSafely(() {
      value = value.copyWith(
        subtitleRanges: subtitle.ranges,
        currentSubtitleIndex: -1,
        currentSubtitle: '',
      );
    });
  }

  /// Sets whether or not the subtitle should loop after playing once.
  void setLooping(bool value) {
    _shouldLoop = value;
  }

  void _queueNextSubtitleRange([bool wait = true]) async {
    final subtitleRanges = _subtitle?.ranges ?? <SubtitleRange>[];

    if (_currentSubtitleRangeIndex >= subtitleRanges.length) {
      _updateValueSafely(() {
        value = value.copyWith(
          currentSubtitle: '',
          currentSubtitleIndex: -1,
        );
      });

      if (_currentSubtitleRangeIndex == subtitleRanges.length && _shouldLoop) {
        _currentSubtitleRangeIndex = 0;
        _queueNextSubtitleRange();
        return;
      }

      return;
    }

    final subtitleRange = subtitleRanges[_currentSubtitleRangeIndex];

    if (_currentSubtitleRangeIndex == 0 &&
        subtitleRange.start != Duration.zero &&
        wait) {
      await Future.delayed(subtitleRange.start);
    }

    if (_abort) return;

    _updateValueSafely(() {
      value = value.copyWith(
        currentSubtitle: subtitleRange.subtitle,
        currentSubtitleIndex: _currentSubtitleRangeIndex,
      );
    });
    _timer?.cancel();

    _timer = Timer(
      subtitleRange.end - subtitleRange.start,
      () {
        if (_abort) return;
        _currentSubtitleRangeIndex++;
        _queueNextSubtitleRange();
      },
    );
  }

  /// Starts synchronizing the loaded subtitle.
  ///
  /// If [position] is not `null` or [Duration.zero],
  /// [SubtitleController] seeks to [position] and starts
  /// synchronizing from there.
  void play([Duration? position]) {
    if (position != null && position != Duration.zero) {
      seekTo(position);
      return;
    }

    pause();
    _currentSubtitleRangeIndex = 0;
    _queueNextSubtitleRange();
  }

  /// Pauses subtitle synchronization.
  void pause() {
    _currentSubtitleRangeIndex = -1;
    _timer?.cancel();
    _seekTimer?.cancel();
  }

  /// Sets the current subtitle synchronization to be at [position].
  void seekTo(Duration position) {
    pause();

    _updateValueSafely(() {
      value = value.copyWith(
        currentSubtitle: '',
        currentSubtitleIndex: -1,
      );
    });

    final result = _subtitle?.findSubtitleRangeAt(position);
    if (result == null || result.subtitleRange == null) return;

    final subtitleRange = result.subtitleRange!;

    if (subtitleRange.start <= position) {
      _updateValueSafely(() {
        value = value.copyWith(
          currentSubtitle: subtitleRange.subtitle,
          currentSubtitleIndex: result.index,
        );
      });

      _seekTimer = Timer(
        subtitleRange.end - position,
        () {
          _currentSubtitleRangeIndex = result.index + 1;
          _queueNextSubtitleRange();
        },
      );
    } else {
      _seekTimer = Timer(
        subtitleRange.start - position,
        () {
          _currentSubtitleRangeIndex = result.index;
          _queueNextSubtitleRange(false);
        },
      );
    }
  }

  /// Only allows updates to [value] when
  ///  [SubtitleController] hasn't been disposed.
  void _updateValueSafely(Function updateCallback) {
    if (!_disposed) updateCallback.call();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _seekTimer?.cancel();
    super.dispose();
  }
}
