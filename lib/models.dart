class SosMessage {
  final String id;
  final String sender;
  final int ttl;
  final String content;
  final int timestampMs;
  final String type;
  final double? lat;
  final double? lng;

  SosMessage({
    required this.id,
    required this.sender,
    required this.ttl,
    required this.content,
    required this.timestampMs,
    required this.type,
    this.lat,
    this.lng,
  });
}
