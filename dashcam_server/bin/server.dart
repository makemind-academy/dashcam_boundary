import 'dart:async';
import 'dart:convert';

import 'package:mcp_server/mcp_server.dart';

import 'serve_bundle.dart';

/// dashcam_server — the trip log and the settings, and never the footage.
///
/// A dashcam holds the most sensitive thing in the vehicle. Everything else
/// about it — when it recorded, how much card is left, whether the impact
/// sensor is too twitchy — is ordinary operational data that a fleet manager
/// legitimately needs.
///
/// The way this is usually built is one API that returns everything, with a
/// permission check in front of the video endpoint. That works until somebody
/// removes the check.
///
/// Here there is no video endpoint. Not a locked one — an absent one. The
/// tool list is the surface, and footage is not on it.
void main(List<String> args) async {
  const config = McpServerConfig(
    name: 'Dashcam',
    version: '1.0.0',
    capabilities: ServerCapabilities(
      tools: ToolsCapability(listChanged: true),
      resources: ResourcesCapability(listChanged: true),
    ),
  );
  final server = McpServer.createServer(config);
  DashcamServer(server).register();
  // The screen next door: AppPlayer reads it from here and sends the pages'
  // tool calls back to the tools above.
  registerBundleUi(server, '../dashcam.mbd');
  final transport = McpServer.createStdioTransport().get();
  server.connect(transport);
  await Completer<void>().future;
}

class Trip {
  Trip(this.id, this.startedAt, this.minutes, this.km, this.events, this.clipId);

  final String id;
  final String startedAt;
  final int minutes;
  final double km;

  /// How many times the impact sensor fired. A count, not a clip.
  final int events;

  /// An opaque handle to footage this server cannot open. It exists so that
  /// somebody standing at the vehicle with the right to view can find the
  /// file — and so that this server can prove it never read it.
  final String clipId;
}

class DashcamServer {
  DashcamServer(this.server);

  final Server server;

  /// Words this server must never emit. Footage leaks by being described as
  /// much as by being served: a "summary of what the camera saw" is the video,
  /// laundered through a sentence.
  static const forbidden = [
    'plate', 'licence', 'license', 'face', 'pedestrian', 'frame',
    'thumbnail', 'preview', 'snapshot', 'image', 'footage of',
  ];

  static String _guard(String s) {
    final lower = s.toLowerCase();
    for (final w in forbidden) {
      if (lower.contains(w)) {
        throw StateError('dashcam_server tried to describe footage: "$w"');
      }
    }
    return s;
  }

  final _trips = <Trip>[
    Trip('T-8841', '2026-04-08 07:12', 34, 18.2, 0, 'clip:8841'),
    Trip('T-8842', '2026-04-08 09:40', 52, 41.7, 1, 'clip:8842'),
    Trip('T-8843', '2026-04-08 13:05', 21, 9.4, 0, 'clip:8843'),
    Trip('T-8844', '2026-04-08 17:31', 68, 55.1, 2, 'clip:8844'),
  ];

  var _sensitivity = 3; // 1..5
  var _cardFreeGb = 12.4;
  static const _cardTotalGb = 64.0;

  void register() {
    server.addTool(
      name: 'trips.list',
      description: 'Trips recorded today, with duration, distance and impact counts',
      inputSchema: const {'type': 'object', 'properties': {}},
      handler: (args) async => _state(),
    );

    server.addTool(
      name: 'camera.settings',
      description: 'Read the impact sensitivity and the card space',
      inputSchema: const {'type': 'object', 'properties': {}},
      handler: (args) async => _state(),
    );

    server.addTool(
      name: 'camera.set_sensitivity',
      description: 'Set impact sensitivity, 1 (least) to 5 (most)',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'level': {'type': 'integer'},
        },
        'required': ['level'],
      },
      handler: (args) async {
        var v = args['level'] as int;
        // The camera clamps to its own range. A fleet console asking for 9
        // gets 5, and is told so.
        if (v < 1) v = 1;
        if (v > 5) v = 5;
        _sensitivity = v;
        return _state(notice: 'sensitivity now $_sensitivity');
      },
    );
  }

  CardState get _card => (
        freeGb: _cardFreeGb,
        pct: (_cardFreeGb / _cardTotalGb * 100).round(),
      );

  CallToolResult _state({String notice = ''}) {
    final events = _trips.fold<int>(0, (a, t) => a + t.events);
    final km = _trips.fold<double>(0, (a, t) => a + t.km);
    return CallToolResult(content: [
      TextContent(
        text: jsonEncode({
          'rows': [
            for (final t in _trips)
              {
                'id': t.id,
                'when': t.startedAt.split(' ').last,
                'line': '${t.minutes} min · ${t.km.toStringAsFixed(1)} km',
                // The handle travels; the content does not.
                'clip': t.clipId,
                'events': t.events == 0 ? '' : '${t.events} impact',
                'flagged': t.events > 0,
              },
          ],
          'tripCount': _trips.length,
          'km': '${km.toStringAsFixed(1)} km',
          'events': events,
          'sensitivity': '$_sensitivity of 5',
          'card': '${_card.freeGb.toStringAsFixed(1)} GB free (${_card.pct}%)',
          'boundary': _guard('This app never opens a clip. It reports when one exists.'),
          'notice': notice,
        }),
      )
    ]);
  }
}

typedef CardState = ({double freeGb, int pct});
