class BuildInfo {
  const BuildInfo({
    required this.applicationName,
    required this.version,
    required this.buildNumber,
    required this.channel,
    required this.gitSha,
    required this.platform,
    required this.architecture,
  });

  final String applicationName;
  final String version;
  final String buildNumber;
  final String channel;
  final String gitSha;
  final String platform;
  final String architecture;

  bool get isRelease => channel.toLowerCase() == 'release';

  String get shortGitSha => gitSha.length > 8 ? gitSha.substring(0, 8) : gitSha;

  String get displayVersion => '$version ${isRelease ? 'Release' : 'Debug'}';

  String get displayBuild {
    final parts = <String>[
      if (buildNumber.isNotEmpty) 'Build $buildNumber',
      if (shortGitSha.isNotEmpty && shortGitSha != 'unknown') shortGitSha,
    ];
    return parts.join(' · ');
  }

  String get displayPlatform => '$platform $architecture';

  String get copyText => [
    '$applicationName $displayVersion',
    if (displayBuild.isNotEmpty) displayBuild,
    displayPlatform,
  ].join('\n');
}
