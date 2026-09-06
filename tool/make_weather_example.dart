// Authors examples/weather — the R13 example: one HTTP request, decoded into a
// model, with loading and error states.
//
//   dart run tool/make_weather_example.dart
import 'package:lattice_core/io.dart';
import 'package:lattice_core/lattice_core.dart';

Future<void> main() async {
  final project = Project(
    id: 'weather',
    config: const ProjectConfig(
      appName: 'Weather',
      packageName: 'weather_app',
      bundleId: 'com.example.weather_app',
      description: 'A Lattice example: fetch a forecast over HTTP and show it.',
      targets: [BuildTarget.linux, BuildTarget.web, BuildTarget.android],
    ),
    // R20: the built-in library has no unit conversion and should not — this
    // is the project's own vocabulary, so the project defines it.
    customNodes: [
      const CustomNodeDef(
        type: 'Fahrenheit',
        category: NodeCategory.compute,
        summary: 'Celsius to Fahrenheit.',
        inputs: [CustomPin(name: 'celsius', type: PrimitiveType.double_)],
        outputs: [CustomPin(name: 'out', type: PrimitiveType.double_)],
        template: '{celsius} * 9 / 5 + 32',
      ),
    ],
    models: [
      DataModelDef.fromJson(const {
        'name': 'Forecast',
        'fields': {
          'latitude': 'double',
          'longitude': 'double',
          'currentWeather': 'CurrentWeather',
        },
        // Real APIs rarely spell things the way Dart does.
        'jsonKeys': {'currentWeather': 'current_weather'},
      }, 'weather'),
      DataModelDef.fromJson(const {
        'name': 'CurrentWeather',
        'fields': {
          'time': 'String',
          'temperature': 'double',
          'windspeed': 'double',
          'weathercode': 'int',
        },
      }, 'weather'),
    ],
    pages: [_home()],
  );

  await ProjectIo.save(project, 'examples/weather');
  final result = const Validator().validate(project);
  if (!result.isValid) {
    throw StateError('the fixture does not validate:\n$result');
  }
  print('Wrote examples/weather (${result.diagnostics.length} diagnostics)');
}

Page _home() => Page(
      id: 'page_home',
      name: 'Home',
      route: '/',
      isHome: true,
      hierarchy: _hierarchy(),
      graph: _graph(),
      layout: const {
        'n_city': CanvasPos(80, 60),
        'n_forecast': CanvasPos(80, 160),
        'n_tempC': CanvasPos(360, 400),
        'n_tempF': CanvasPos(620, 400),
        'n_tempFText': CanvasPos(860, 400),
        'n_loading': CanvasPos(80, 260),
        'n_error': CanvasPos(80, 360),
        'n_url': CanvasPos(340, 60),
        'ev_fetch': CanvasPos(340, 460),
        'a_fetch': CanvasPos(560, 460),
      },
    );

WidgetNode _hierarchy() => WidgetNode(
      id: 'w_root',
      type: 'Scaffold',
      props: {
        'appBar': WidgetProp(
          WidgetNode(
            id: 'w_appbar',
            type: 'AppBar',
            props: {
              'title': WidgetProp(
                WidgetNode(
                  id: 'w_title',
                  type: 'Text',
                  props: {'data': const LiteralProp('Weather')},
                ),
              ),
            },
          ),
        ),
      },
      children: [
        WidgetNode(
          id: 'w_pad',
          type: 'Padding',
          props: {'padding': const LiteralProp(24)},
          children: [
            WidgetNode(
              id: 'w_col',
              type: 'Column',
              props: {'crossAxisAlignment': const LiteralProp('stretch')},
              children: [
                WidgetNode(
                  id: 'w_city',
                  type: 'TextField',
                  props: {
                    'labelText': const LiteralProp('City'),
                    'hintText': const LiteralProp('Berlin, Tokyo, Paris…'),
                    'text': const BindProp(PinRef('n_city', 'value')),
                    'onChanged': const EventProp('ev_city'),
                  },
                ),
                WidgetNode(
                  id: 'w_gap',
                  type: 'SizedBox',
                  props: {'height': const LiteralProp(16)},
                ),
                WidgetNode(
                  id: 'w_fetch',
                  type: 'ElevatedButton',
                  props: {'onPressed': const EventProp('ev_fetch')},
                  children: [
                    WidgetNode(
                      id: 'w_fetch_label',
                      type: 'Text',
                      props: {'data': const LiteralProp('Get forecast')},
                    ),
                  ],
                ),
                WidgetNode(
                  id: 'w_gap2',
                  type: 'SizedBox',
                  props: {'height': const LiteralProp(24)},
                ),

                // Exactly one of these three shows at a time.
                WidgetNode(
                  id: 'w_if_loading',
                  type: 'If',
                  props: {
                    'condition': const BindProp(PinRef('n_loading', 'value')),
                  },
                  children: [
                    WidgetNode(
                      id: 'w_spinner',
                      type: 'CircularProgressIndicator',
                    ),
                  ],
                ),
                WidgetNode(
                  id: 'w_if_error',
                  type: 'If',
                  props: {
                    'condition': const BindProp(PinRef('n_hasError', 'out')),
                  },
                  children: [
                    WidgetNode(
                      id: 'w_error',
                      type: 'Text',
                      props: {
                        'data': const BindProp(PinRef('n_errorText', 'out')),
                        'style': const LiteralProp({'color': '#B3261E'}),
                      },
                    ),
                  ],
                ),
                WidgetNode(
                  id: 'w_if_result',
                  type: 'If',
                  props: {
                    'condition': const BindProp(PinRef('n_hasForecast', 'out')),
                  },
                  children: [
                    WidgetNode(
                      id: 'w_result',
                      type: 'Column',
                      props: {'mainAxisSize': const LiteralProp('min')},
                      children: [
                        WidgetNode(
                          id: 'w_temp',
                          type: 'Text',
                          props: {
                            'data': const BindProp(PinRef('n_tempText', 'out')),
                            'style': const LiteralProp({
                              'fontSize': 40,
                              'fontWeight': 'bold',
                            }),
                          },
                        ),
                        WidgetNode(
                          id: 'w_temp_f',
                          type: 'Text',
                          props: {
                            'data':
                                const BindProp(PinRef('n_tempFText', 'out')),
                          },
                        ),
                        WidgetNode(
                          id: 'w_wind',
                          type: 'Text',
                          props: {
                            'data': const BindProp(PinRef('n_windText', 'out')),
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

Graph _graph() => Graph(
      nodes: [
        GraphNode(
          id: 'n_city',
          type: 'Signal',
          config: const {
            'dartType': 'String',
            'init': 'Berlin',
            'name': 'city',
          },
        ),
        GraphNode(
          id: 'n_forecast',
          type: 'Signal',
          config: const {'dartType': 'Forecast?', 'name': 'forecast'},
        ),
        GraphNode(
          id: 'n_loading',
          type: 'Signal',
          config: const {
            'dartType': 'bool',
            'init': false,
            'name': 'loading',
          },
        ),
        GraphNode(
          id: 'n_error',
          type: 'Signal',
          config: const {'dartType': 'String?', 'name': 'error'},
        ),

        // The URL comes from a hand-written lookup table in custom/ (§7.8).
        GraphNode(
          id: 'n_url',
          type: 'DartCode',
          config: const {
            'name': 'urlFor',
            'dartType': 'String',
            'inputs': {'city': 'String'},
            'imports': ['custom/cities.dart'],
            'body': 'return forecastUrl(city);',
          },
        ),

        GraphNode(
          id: 'n_hasError',
          type: 'Computed',
          config: const {
            'name': 'hasError',
            'dartType': 'bool',
            'inputs': {'message': 'String?'},
            'expr': 'message != null',
          },
        ),
        GraphNode(
          id: 'n_errorText',
          type: 'Computed',
          config: const {
            'name': 'errorText',
            'dartType': 'String',
            'inputs': {'message': 'String?'},
            'expr': "message ?? ''",
          },
        ),
        GraphNode(
          id: 'n_hasForecast',
          type: 'Computed',
          config: const {
            'name': 'hasForecast',
            'dartType': 'bool',
            'inputs': {'forecast': 'Forecast?'},
            'expr': 'forecast != null',
          },
        ),
        GraphNode(
          id: 'n_tempText',
          type: 'Computed',
          config: const {
            'name': 'temperatureText',
            'dartType': 'String',
            'inputs': {'forecast': 'Forecast?'},
            'expr':
                r"forecast == null ? '—' : '${forecast.currentWeather.temperature} °C'",
          },
        ),
        // The graph reaches into the model, the project's own node does the
        // arithmetic, and Format renders it. No hand-written Dart involved.
        GraphNode(
          id: 'n_tempC',
          type: 'Computed',
          config: const {
            'name': 'temperatureCelsius',
            'dartType': 'double',
            'inputs': {'forecast': 'Forecast?'},
            'expr': 'forecast?.currentWeather.temperature ?? 0',
          },
        ),
        GraphNode(id: 'n_tempF', type: 'Fahrenheit'),
        GraphNode(
          id: 'n_tempFText',
          type: 'Format',
          config: const {'template': '{0} °F'},
        ),
        GraphNode(
          id: 'n_windText',
          type: 'Computed',
          config: const {
            'name': 'windText',
            'dartType': 'String',
            'inputs': {'forecast': 'Forecast?'},
            'expr':
                r"forecast == null ? '' : 'Wind ${forecast.currentWeather.windspeed} km/h'",
          },
        ),

        GraphNode(
          id: 'ev_city',
          type: 'Event',
          config: const {'widget': 'w_city', 'event': 'onChanged'},
        ),
        GraphNode(
          id: 'a_city',
          type: 'SetSignal',
          config: const {'signal': 'n_city'},
        ),
        GraphNode(
          id: 'ev_fetch',
          type: 'Event',
          config: const {'widget': 'w_fetch', 'event': 'onPressed'},
        ),
        GraphNode(
          id: 'a_fetch',
          type: 'HttpRequest',
          config: const {
            'method': 'GET',
            'signal': 'n_forecast',
            'loadingSignal': 'n_loading',
            'errorSignal': 'n_error',
          },
        ),
      ],
      edges: const [
        Edge(PinRef('n_city', 'value'), PinRef('n_url', 'city')),
        Edge(PinRef('n_error', 'value'), PinRef('n_hasError', 'message')),
        Edge(PinRef('n_error', 'value'), PinRef('n_errorText', 'message')),
        Edge(
            PinRef('n_forecast', 'value'), PinRef('n_hasForecast', 'forecast')),
        Edge(PinRef('n_forecast', 'value'), PinRef('n_tempText', 'forecast')),
        Edge(PinRef('n_forecast', 'value'), PinRef('n_windText', 'forecast')),
        Edge(PinRef('n_forecast', 'value'), PinRef('n_tempC', 'forecast')),
        Edge(PinRef('n_tempC', 'out'), PinRef('n_tempF', 'celsius')),
        Edge(PinRef('n_tempF', 'out'), PinRef('n_tempFText', 'args', index: 0)),
        Edge(PinRef('ev_city', 'fire'), PinRef('a_city', 'exec')),
        Edge(PinRef('ev_city', 'payload'), PinRef('a_city', 'value')),
        Edge(PinRef('ev_fetch', 'fire'), PinRef('a_fetch', 'exec')),
        Edge(PinRef('n_url', 'out'), PinRef('a_fetch', 'url')),
      ],
    );
