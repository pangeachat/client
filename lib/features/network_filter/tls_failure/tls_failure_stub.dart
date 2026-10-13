/// Whether [error] is a TLS failure that `package:http` passes through
/// unwrapped. Never, off `dart:io`: a browser reports a TLS failure as a
/// `ClientException` like any other failed request. Implementation for the
/// native apps: tls_failure_io.dart.
bool isTlsFailure(Object error) => false;
