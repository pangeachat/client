import 'dart:js_interop';

@JS('console.log')
external void _consoleLog(JSString line);

/// Web: the test framework keeps `print` from reaching the browser console,
/// where web_runner.js reads the result, so write to the console directly.
void perfOutput(String line) => _consoleLog(line.toJS);
