/// Returns the last component (folder name) of a file-system [path].
///
/// Handles both forward-slash and backslash separators so it works on
/// Windows paths as well as POSIX paths.
///
/// Example:
/// ```dart
/// deckFolderName('C:\\Users\\me\\decks\\French Verbs') // → 'French Verbs'
/// deckFolderName('/home/me/decks/French Verbs')        // → 'French Verbs'
/// ```
String deckFolderName(String path) =>
    path.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).last;
