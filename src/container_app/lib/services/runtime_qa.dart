// MIT License
//
// Copyright (c) 2026 iappyx
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

/// The decision layer around the headless WebView probe.
///
/// [RuntimeProbe] records what happened; [RuntimeQa] decides whether the app is
/// allowed to ship. Keeping the decision pure makes the "never ship a white
/// screen" rule testable without an emulator.
library;

import 'runtime_probe.dart';

class RuntimeQaOutcome {
  final RuntimeReport? report;
  final bool blocked;
  final bool cancelled;
  final String message;

  const RuntimeQaOutcome({
    required this.report,
    required this.blocked,
    this.cancelled = false,
    required this.message,
  });

  bool get passed => !blocked && !cancelled && report?.passed == true;
}

class RuntimeQa {
  /// Runs [run] and maps its report to a build decision.
  ///
  /// A user cancellation is treated as "do not build" but is not an error. An
  /// inconclusive probe (old WebView, no report) does not block: it must not
  /// turn a device limitation into a false failure.
  static Future<RuntimeQaOutcome> verify(
      Future<RuntimeReport?> Function() run) async {
    RuntimeReport? report;
    try {
      report = await run();
    } catch (e) {
      return RuntimeQaOutcome(
        report: null,
        blocked: false,
        message: 'Runtime check unavailable: $e',
      );
    }
    return evaluate(report);
  }

  static RuntimeQaOutcome evaluate(RuntimeReport? report) {
    if (report == null) {
      return const RuntimeQaOutcome(
        report: null,
        blocked: true,
        cancelled: true,
        message: 'Runtime check cancelled. The app was not built.',
      );
    }
    if (report.fatal) {
      return RuntimeQaOutcome(
        report: report,
        blocked: true,
        message: report.blank
            ? 'The app rendered a blank screen.'
            : report.fatalErrors.first,
      );
    }
    return RuntimeQaOutcome(
      report: report,
      blocked: false,
      message: report.summary,
    );
  }
}
