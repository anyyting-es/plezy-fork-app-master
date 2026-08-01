/// Smart Download Configuration — stores user preferences for automated torrent selection.
library;

// ---------------------------------------------------------------------------
// Quality preference
// ---------------------------------------------------------------------------
enum SmartDownloadQuality {
  any('Cualquiera', ''),
  q480p('480p', '480p'),
  q720p('720p', '720p'),
  q1080p('1080p', '1080p'),
  q2160p('4K / 2160p', '2160p');

  const SmartDownloadQuality(this.label, this.tag);
  final String label;
  /// The string fragment used to match against torrent titles.
  final String tag;
}

// ---------------------------------------------------------------------------
// Audio / subtitle preference
// ---------------------------------------------------------------------------
enum SmartDownloadAudio {
  sub('Subtitulado (SUB)'),
  dub('Doblado (DUB)'),
  multiSub('Multi-Sub'),
  multiAudio('Multi-Audio');

  const SmartDownloadAudio(this.label);
  final String label;
}

// ---------------------------------------------------------------------------
// Release group preference
// ---------------------------------------------------------------------------
enum SmartDownloadProvider {
  any('Cualquiera (Más Seeds)', ''),
  eraiRaws('Erai-raws', 'Erai-raws'),
  toonsHub('ToonsHub', 'ToonsHub'),
  judas('Judas', 'Judas'),
  ironclad('Ironclad', 'Ironclad'),
  subsPlease('SubsPlease', 'SubsPlease');

  const SmartDownloadProvider(this.label, this.tag);
  final String label;
  /// The exact group name to look for in torrent title brackets, e.g. [Erai-raws].
  final String tag;
}

// ---------------------------------------------------------------------------
// Combined config object
// ---------------------------------------------------------------------------
class SmartDownloadConfig {
  final SmartDownloadQuality quality;
  final SmartDownloadAudio audio;
  final SmartDownloadProvider provider;

  const SmartDownloadConfig({
    required this.quality,
    required this.audio,
    required this.provider,
  });

  @override
  String toString() =>
      'SmartDownloadConfig(quality: ${quality.label}, audio: ${audio.label}, provider: ${provider.label})';
}
