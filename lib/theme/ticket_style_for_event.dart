import '../api/models/event.dart';
import '../components/ticket/ticket_style.dart';
import 'circuit_slugs.dart';

/// Heritage and night circuits use the slugs from [circuitIdForEvent].
const _heritage = <String>{
  'monaco',
  'monza',
  'silverstone',
  'spa-francorchamps',
  'suzuka',
  'interlagos',
};

const _night = <String>{
  'marina-bay', // Singapore
  'las-vegas',
  'jeddah',
  'lusail', // Qatar
  'yas-marina', // Abu Dhabi
};

/// Picks a [TicketStyle] for an event based on its circuit. Heritage tracks
/// get the vintage stencil; night races get the dark boarding pass; everything
/// else falls through to the poster sprint default.
TicketStyle styleForEvent(Event event) {
  final id = circuitIdForEvent(
    name: event.name,
    country: event.country,
    circuitName: event.circuitName,
  );
  if (id == null) return TicketStyle.posterSprint;
  if (_heritage.contains(id)) return TicketStyle.vintageStencil;
  if (_night.contains(id)) return TicketStyle.darkBoardingPass;
  return TicketStyle.posterSprint;
}
