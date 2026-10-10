/// Ticket title for a race name. Jolpica names already end in "Grand Prix", so
/// plain styles shorten it to "GP" and script styles hand it to the script
/// line — appending it again printed "MONACO GRAND PRIX GP". Names carrying
/// the words mid-string ("Bahrain Grand Prix in Malaysia") stay whole.
({String title, String? script}) ticketTitle(String eventName,
    {required bool hasScript}) {
  const suffix = ' Grand Prix';
  if (!eventName.endsWith(suffix)) {
    return (title: eventName.toUpperCase(), script: null);
  }
  final place =
      eventName.substring(0, eventName.length - suffix.length).toUpperCase();
  return hasScript
      ? (title: place, script: 'Grand Prix')
      : (title: '$place GP', script: null);
}
