/// Public client configuration. The anon key is safe to ship in the app:
/// every table is protected by Row Level Security.
class AppConfig {
  AppConfig._();

  static const supabaseUrl = 'https://iegtcejcgizufqkzgkhe.supabase.co';
  static const supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImllZ3RjZWpjZ2l6dWZxa3pna2hlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ4MjMzMDIsImV4cCI6MjExMDM5OTMwMn0.fjgXVoyZglfBsocvbE-77p4YJChYaQdBJGGpk9blIJ4';

  static const environment = 'sandbox';

  /// Reown (WalletConnect) Cloud project for connecting external wallets.
  static const reownProjectId = 'e563992730f6edc6221ea331e8eeaeff';

  static const appUrl = 'https://thetechguydev.github.io/NovaApp/';
}
