/// The next host id handed to a hosted widget.
///
/// A released event names the host it displaced, and the bar and the surface share this one
/// counter so their ids can never collide: one id space for one plugin.
int _nextHostId = 0;

/// Returns a fresh host id.
int nextHostedThingId() => ++_nextHostId;
