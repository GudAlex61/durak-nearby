#!/usr/bin/env python3
# Log-reader readiness logic adapted from Flutter (Copyright 2014 The Flutter
# Authors), under BSD-3-Clause; see licenses/FLUTTER_BSD_LICENSE.
"""Backport Flutter PR #193142 to the CI's pinned 3.35.7 test launcher.

Only flutter_tools changes. The engine, application and release IPA are untouched.
Upstream: https://github.com/flutter/flutter/pull/193142
"""
from pathlib import Path
import sys


def backport(source):
    if 'durakIosLogStreamBackport' in source:
        return source

    def replace(old, new):
        nonlocal source
        if source.count(old) != 1:
            raise ValueError('Unexpected Flutter tool source; refusing a partial backport: ' + old[:70])
        source = source.replace(old, new, 1)

    replace('final _logReaders = <IOSApp?, DeviceLogReader>{};',
            'final _logReaders = <IOSApp?, _IOSSimulatorLogReader>{};')
    replace('DeviceLogReader getLogReader({covariant IOSApp? app, bool includePastLogs = false}) {',
            '_IOSSimulatorLogReader getLogReader({covariant IOSApp? app, bool includePastLogs = false}) {')
    replace('''    if (debuggingOptions.debuggingEnabled) {
      vmServiceDiscovery = ProtocolDiscovery.vmService(
        getLogReader(app: package),''', '''    if (debuggingOptions.debuggingEnabled) {
      final _IOSSimulatorLogReader logReader = getLogReader(app: package);
      vmServiceDiscovery = ProtocolDiscovery.vmService(
        logReader,''')
    replace('''        logger: globals.logger,
      );
    }

    // Launch the updated application in the simulator.''', '''        logger: globals.logger,
      );
      // durakIosLogStreamBackport: Flutter PR #193142, log reader readiness.
      final timer = Timer(const Duration(seconds: 30), () {
        globals.printError('Waiting for the iOS simulator log stream to become ready...');
      });
      await logReader._logReady.future;
      timer.cancel();
    }

    // Launch the updated application in the simulator.''')
    replace('''  // We log from two files: the device and the system log.
  Process? _deviceProcess;''', '''  // Recreated for each log stream, as in upstream Flutter PR #193142.
  var _logReady = Completer<void>();

  // We log from two files: the device and the system log.
  Process? _deviceProcess;''')
    replace('''  Future<void> _start() async {
    // Unified logging iOS 11 and greater (introduced in iOS 10).''', '''  Future<void> _start() async {
    _logReady = Completer<void>();
    final Completer<void> ready = _logReady;
    // Unified logging iOS 11 and greater (introduced in iOS 10).''')
    replace('''      _deviceProcess?.stdout
          .transform<String>(utf8.decoder)
          .transform<String>(const LineSplitter())
          .listen(_onUnifiedLoggingLine);''', '''      _deviceProcess?.stdout
          .transform<String>(utf8.decoder)
          .transform<String>(const LineSplitter())
          .listen((String line) {
            if (!ready.isCompleted) {
              ready.complete();
            }
            _onUnifiedLoggingLine(line);
          });''')
    replace('''      _deviceProcess?.exitCode.whenComplete(() {
        if (_linesController.hasListener) {''', '''      _deviceProcess?.exitCode.whenComplete(() {
        if (!ready.isCompleted) {
          ready.complete();
        }
        if (_linesController.hasListener) {''')
    return source


if __name__ == '__main__':
    sdk = Path(sys.argv[1]).resolve()
    target = sdk / 'packages/flutter_tools/lib/src/ios/simulators.dart'
    result = backport(target.read_text())
    target.write_text(result)
    for name in ['flutter_tools.snapshot', 'flutter_tools.stamp']:
        (sdk / 'bin/cache' / name).unlink(missing_ok=True)
    print('Applied upstream simulator log-stream readiness fix to Flutter test tooling.')
