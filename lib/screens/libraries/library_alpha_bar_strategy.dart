import '../../media/library_first_character.dart';
import '../../media/media_backend.dart';
import 'alpha_jump_helper.dart';

/// Backend-specific alpha-jump-bar behaviour.
/// Since only online/Jellyfin strategies are retained, this is a simplified interface.
abstract class LibraryAlphaBarStrategy {
  /// Whether the bar should be rendered at all. Implementations consider
  /// total item count, sort key, and current filter state.
  bool shouldShow({
    required int totalItemCount,
    required int loadedCharacterCount,
    required String? sortKey,
    required bool isFolderGrouping,
    required String? jellyfinAlphaPrefix,
    required bool isPhone,
  });

  /// Load the first-character buckets for the current filter state.
  /// Returns the new helper plus the synthesised character list.
  Future<({List<LibraryFirstCharacter> chars, AlphaJumpHelper helper})> loadCharacters({
    required Map<String, String> filters,
    required int? typeId,
    required bool descending,
  });

  /// Letter to highlight given the current scroll-derived index.
  String currentLetter(int index, AlphaJumpHelper helper, {String? jellyfinAlphaPrefix});

  /// Handle a tap on the letter at [targetIndex].
  void onLetterPressed(
    int targetIndex,
    AlphaJumpHelper helper, {
    required String? currentJellyfinPrefix,
    required void Function(int index) onPlexJump,
    required void Function(String? nextPrefix) onJellyfinPrefixChange,
  });

  /// Construct the right strategy for [backend].
  factory LibraryAlphaBarStrategy.forBackend(
    MediaBackend backend, {
    dynamic plexClientProvider,
    String? libraryKey,
    bool? isShared,
  }) {
    return const JellyfinAlphaBarStrategy();
  }
}

/// Jellyfin strategy — synthesises the 27-letter alphabet locally and uses
/// the bar as a `NameStartsWith` filter.
class JellyfinAlphaBarStrategy implements LibraryAlphaBarStrategy {
  static const _letters = [
    '#',
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
  ];

  const JellyfinAlphaBarStrategy();

  @override
  bool shouldShow({
    required int totalItemCount,
    required int loadedCharacterCount,
    required String? sortKey,
    required bool isFolderGrouping,
    required String? jellyfinAlphaPrefix,
    required bool isPhone,
  }) {
    if (isPhone) return false;
    if (isFolderGrouping) return false;
    if (loadedCharacterCount == 0) return false;
    return totalItemCount >= 80 || jellyfinAlphaPrefix != null;
  }

  @override
  Future<({List<LibraryFirstCharacter> chars, AlphaJumpHelper helper})> loadCharacters({
    required Map<String, String> filters,
    required int? typeId,
    required bool descending,
  }) async {
    final synthetic = [for (final l in _letters) LibraryFirstCharacter(key: l, title: l, size: 1)];
    return (chars: synthetic, helper: AlphaJumpHelper(synthetic, descending: descending));
  }

  @override
  String currentLetter(int index, AlphaJumpHelper helper, {String? jellyfinAlphaPrefix}) => jellyfinAlphaPrefix ?? '';

  @override
  void onLetterPressed(
    int targetIndex,
    AlphaJumpHelper helper, {
    required String? currentJellyfinPrefix,
    required void Function(int index) onPlexJump,
    required void Function(String? nextPrefix) onJellyfinPrefixChange,
  }) {
    if (targetIndex < 0 || targetIndex >= helper.letters.length) return;
    final letter = helper.letters[targetIndex];
    final next = (currentJellyfinPrefix == letter) ? null : letter;
    onJellyfinPrefixChange(next);
  }
}
