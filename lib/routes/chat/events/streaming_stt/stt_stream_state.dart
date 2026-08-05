/// Lifecycle of the streaming-STT WebSocket transport ([SttStreamRepo]).
///
/// Adapted from Luna's `LunaSessionState`, dropped to the four states a
/// pilot streaming socket actually has (no server-side admission handshake in
/// the D4 wire protocol): [connecting] before the socket opens, [open] once it
/// is ready, [closed] on a clean teardown (either side), and [error] on a
/// transport failure or a relay `{"type":"error"}` frame.
enum SttStreamState { connecting, open, closed, error }
