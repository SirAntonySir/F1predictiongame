import '../api/models/event.dart';
import '../components/ticket/ticket_style.dart';
import '../components/ticket/ticket_watermark_config.dart';

/// Resolves the paper variant for an event by reading
/// [kTicketStyleRotation] from `ticket_watermark_config.dart`. Round-based,
/// deterministic, mod-safe for negative rounds (legacy fixtures).
TicketStyle styleForEvent(Event event) {
  final r = event.round - 1;
  final n = kTicketStyleRotation.length;
  return kTicketStyleRotation[((r % n) + n) % n];
}
