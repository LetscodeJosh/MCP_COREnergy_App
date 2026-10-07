enum AppMode {
  hcp,
  corenergy,
}

enum Environment {
  development,
  production,
}

class AppConfig {
  static AppMode mode = AppMode.corenergy;

  /// =========================================================================
  /// ENVIRONMENT CONFIGURATION (DEV vs PRODUCTION)
  /// =========================================================================
  /// Toggle this single variable from [Environment.development] to [Environment.production]
  /// when switching from testing to live production.
  static Environment environment = Environment.development;

  /// Development ERPNext v15 Server URL
  static const String devBaseUrl = 'https://dev.pmii-marketing.com';

  /// Production ERPNext v15 Server URL (Configure your live production domain here)
  static const String prodBaseUrl = 'https://pmii-marketing.com';

  /// Active Server Base URL (Used throughout the entire application)
  static String get baseUrl =>
      environment == Environment.production ? prodBaseUrl : devBaseUrl;
}
