import 'dart:io';

/// Whether [error] is a TLS failure — a filter presenting its own
/// certificate. `package:http` wraps a socket failure in a `ClientException`
/// but passes this through as a raw `TlsException`.
bool isTlsFailure(Object error) => error is TlsException;
