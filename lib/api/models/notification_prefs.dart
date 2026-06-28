/// Per-user notification preferences, mirrored from the backend
/// (`GET/PUT /api/notification-prefs`). Replaces the old device-local
/// SharedPreferences model now that the server fires notifications and must
/// honour these values itself.
class NotificationPrefs {
  final bool enabled;
  final bool quietEnabled;

  /// Minutes since local midnight.
  final int quietStartMin;
  final int quietEndMin;

  /// IANA zone reported by the device at registration. Read-only here — the
  /// app reports it via device registration, not the prefs endpoint.
  final String? timezone;

  const NotificationPrefs({
    required this.enabled,
    required this.quietEnabled,
    required this.quietStartMin,
    required this.quietEndMin,
    this.timezone,
  });

  /// Matches the backend defaults (reminders on, quiet hours off, 22:00–08:00).
  static const defaults = NotificationPrefs(
    enabled: true,
    quietEnabled: false,
    quietStartMin: 22 * 60,
    quietEndMin: 8 * 60,
  );

  factory NotificationPrefs.fromJson(Map<String, dynamic> j) => NotificationPrefs(
        enabled: j['enabled'] as bool? ?? true,
        quietEnabled: j['quietEnabled'] as bool? ?? false,
        quietStartMin: (j['quietStartMin'] as num?)?.toInt() ?? 22 * 60,
        quietEndMin: (j['quietEndMin'] as num?)?.toInt() ?? 8 * 60,
        timezone: j['timezone'] as String?,
      );

  NotificationPrefs copyWith({
    bool? enabled,
    bool? quietEnabled,
    int? quietStartMin,
    int? quietEndMin,
    String? timezone,
  }) =>
      NotificationPrefs(
        enabled: enabled ?? this.enabled,
        quietEnabled: quietEnabled ?? this.quietEnabled,
        quietStartMin: quietStartMin ?? this.quietStartMin,
        quietEndMin: quietEndMin ?? this.quietEndMin,
        timezone: timezone ?? this.timezone,
      );
}
