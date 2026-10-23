/// Build-time configuration (API.md section 1). Pass a config file:
///
/// ```sh
/// flutter run --flavor dev --dart-define-from-file=config/dev.json
/// ```
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// The project's publishable key (`sb_publishable_…`) or legacy anon key.
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// `dev` or `prod`. Dev builds show a DEV ribbon.
  static const flavor = String.fromEnvironment('FLAVOR', defaultValue: 'dev');

  static bool get isProd => flavor == 'prod';

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
