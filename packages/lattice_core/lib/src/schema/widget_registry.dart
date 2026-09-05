import '../types/lattice_type.dart';
import '../types/type_parser.dart';
import 'widget_schema.dart';

const _string = PrimitiveType.string;
const _int = PrimitiveType.int_;
const _double = PrimitiveType.double_;
const _bool = PrimitiveType.bool_;
const _color = PrimitiveType.color;
const _insets = PrimitiveType.edgeInsets;
const _textStyle = PrimitiveType.textStyle;
const _iconData = PrimitiveType.iconData;
const _alignment = PrimitiveType.alignment;
const _void = PrimitiveType.void_;

LatticeType _opt(LatticeType t) => NullableType(t);
EnumType _enum(String name) => EnumRegistry.lookup(name)!;

ParamSchema _v(
  String name,
  LatticeType type, {
  bool req = false,
  Object? def,
  bool bind = true,
  bool pos = false,
  String? into,
}) =>
    ParamSchema(
      name: name,
      type: type,
      required: req,
      defaultValue: def,
      bindable: bind,
      positional: pos,
      emitInto: into,
    );

ParamSchema _child(String name, {bool req = false}) => ParamSchema(
      name: name,
      type: const WidgetType(),
      kind: ParamKind.widget,
      required: req,
      bindable: false,
    );

ParamSchema _childList(String name) => ParamSchema(
      name: name,
      type: const ListType(WidgetType()),
      kind: ParamKind.widgetList,
      bindable: false,
    );

ParamSchema _callback(String name,
        {LatticeType payload = _void, bool req = false}) =>
    ParamSchema(
      name: name,
      type: payload,
      kind: ParamKind.callback,
      required: req,
      bindable: false,
    );

const _flexParents = ['Row', 'Column', 'Flex'];

/// The v1 widget whitelist (§7.1, §3.2).
///
/// Roughly forty widgets, grouped by Flutter semantics. Anything outside it is
/// reachable through a `Dart Code` node, so the whitelist bounds what the
/// Inspector must know about — not what a project can express.
class WidgetRegistry {
  WidgetRegistry._();

  static final Map<String, WidgetSchema> _byType = {
    for (final s in _schemas) s.type: s,
  };

  static WidgetSchema? lookup(String type) => _byType[type];

  static bool isKnown(String type) => _byType.containsKey(type);

  static List<WidgetSchema> get all => List.unmodifiable(_schemas);

  static Iterable<WidgetSchema> byCategory(WidgetCategory category) =>
      _schemas.where((s) => s.category == category);

  /// Registers a schema contributed by a plugin node library (R20).
  static void register(WidgetSchema schema) => _byType[schema.type] = schema;

  static final List<WidgetSchema> _schemas = [
    // ---- structure ---------------------------------------------------------
    WidgetSchema(
      type: 'Scaffold',
      category: WidgetCategory.structure,
      summary: 'Page shell: app bar, body, floating action button.',
      childArity: ChildArity.one,
      childrenParam: 'body',
      params: [
        _child('appBar'),
        _child('floatingActionButton'),
        _child('drawer'),
        _v('backgroundColor', _opt(_color)),
      ],
    ),
    WidgetSchema(
      type: 'AppBar',
      category: WidgetCategory.structure,
      constCtor: false,
      summary: 'Top bar with a title and actions.',
      params: [
        _child('title'),
        _child('leading'),
        _childList('actions'),
        _v('backgroundColor', _opt(_color)),
        _v('centerTitle', _opt(_bool)),
        _v('elevation', _opt(_double)),
      ],
    ),
    WidgetSchema(
      type: 'ListView',
      category: WidgetCategory.structure,
      constCtor: false,
      summary: 'Scrolling list of children.',
      childArity: ChildArity.many,
      childrenParam: 'children',
      params: [
        _v('padding', _opt(_insets)),
        _v('shrinkWrap', _bool, def: false),
        _v('scrollDirection', _enum('Axis'), def: 'vertical'),
      ],
    ),
    WidgetSchema(
      type: 'ListTile',
      category: WidgetCategory.structure,
      summary: 'A single fixed-height row in a list.',
      params: [
        _child('title'),
        _child('subtitle'),
        _child('leading'),
        _child('trailing'),
        _callback('onTap'),
      ],
    ),
    WidgetSchema(
      type: 'Card',
      category: WidgetCategory.structure,
      summary: 'Rounded, elevated surface.',
      childArity: ChildArity.one,
      childrenParam: 'child',
      params: [
        _v('elevation', _opt(_double)),
        _v('color', _opt(_color)),
        _v('margin', _opt(_insets)),
      ],
    ),
    WidgetSchema(
      type: 'SafeArea',
      category: WidgetCategory.structure,
      summary: 'Insets its child away from system intrusions.',
      childArity: ChildArity.one,
      childrenParam: 'child',
    ),
    WidgetSchema(
      type: 'SingleChildScrollView',
      category: WidgetCategory.structure,
      summary: 'Makes an oversized child scrollable.',
      childArity: ChildArity.one,
      childrenParam: 'child',
      params: [_v('padding', _opt(_insets))],
    ),

    // ---- layout ------------------------------------------------------------
    WidgetSchema(
      type: 'Column',
      category: WidgetCategory.layout,
      summary: 'Lays children out vertically.',
      childArity: ChildArity.many,
      childrenParam: 'children',
      params: [
        _v('mainAxisAlignment', _enum('MainAxisAlignment'), def: 'start'),
        _v('crossAxisAlignment', _enum('CrossAxisAlignment'), def: 'center'),
        _v('mainAxisSize', _enum('MainAxisSize'), def: 'max'),
      ],
    ),
    WidgetSchema(
      type: 'Row',
      category: WidgetCategory.layout,
      summary: 'Lays children out horizontally.',
      childArity: ChildArity.many,
      childrenParam: 'children',
      params: [
        _v('mainAxisAlignment', _enum('MainAxisAlignment'), def: 'start'),
        _v('crossAxisAlignment', _enum('CrossAxisAlignment'), def: 'center'),
        _v('mainAxisSize', _enum('MainAxisSize'), def: 'max'),
      ],
    ),
    WidgetSchema(
      type: 'Stack',
      category: WidgetCategory.layout,
      summary: 'Overlays children.',
      childArity: ChildArity.many,
      childrenParam: 'children',
      params: [_v('alignment', _opt(_alignment))],
    ),
    WidgetSchema(
      type: 'Center',
      category: WidgetCategory.layout,
      summary: 'Centres its child.',
      childArity: ChildArity.one,
      childrenParam: 'child',
    ),
    WidgetSchema(
      type: 'Align',
      category: WidgetCategory.layout,
      summary: 'Aligns its child within itself.',
      childArity: ChildArity.one,
      childrenParam: 'child',
      params: [_v('alignment', _alignment)],
    ),
    WidgetSchema(
      type: 'Padding',
      category: WidgetCategory.layout,
      summary: 'Insets its child.',
      childArity: ChildArity.one,
      childrenParam: 'child',
      params: [_v('padding', _insets, req: true)],
    ),
    WidgetSchema(
      type: 'Container',
      category: WidgetCategory.layout,
      constCtor: false,
      summary: 'Painting, positioning and sizing in one box.',
      childArity: ChildArity.one,
      childrenParam: 'child',
      params: [
        _v('width', _opt(_double)),
        _v('height', _opt(_double)),
        _v('color', _opt(_color)),
        _v('padding', _opt(_insets)),
        _v('margin', _opt(_insets)),
        _v('alignment', _opt(_alignment)),
      ],
    ),
    WidgetSchema(
      type: 'SizedBox',
      category: WidgetCategory.layout,
      summary: 'A box of a fixed size, or plain empty space.',
      childArity: ChildArity.one,
      childrenParam: 'child',
      params: [
        _v('width', _opt(_double)),
        _v('height', _opt(_double)),
      ],
    ),
    WidgetSchema(
      type: 'Expanded',
      category: WidgetCategory.layout,
      summary: 'Fills the remaining space along a Flex axis.',
      childArity: ChildArity.one,
      childrenParam: 'child',
      mustBeInside: _flexParents,
      params: [_v('flex', _int, def: 1)],
    ),
    WidgetSchema(
      type: 'Flexible',
      category: WidgetCategory.layout,
      summary: 'Lets a child shrink or grow along a Flex axis.',
      childArity: ChildArity.one,
      childrenParam: 'child',
      mustBeInside: _flexParents,
      params: [_v('flex', _int, def: 1)],
    ),
    WidgetSchema(
      type: 'Spacer',
      category: WidgetCategory.layout,
      summary: 'Empty flexible space between Flex children.',
      mustBeInside: _flexParents,
      params: [_v('flex', _int, def: 1)],
    ),
    WidgetSchema(
      type: 'Wrap',
      category: WidgetCategory.layout,
      summary: 'Lays children out in runs, wrapping as needed.',
      childArity: ChildArity.many,
      childrenParam: 'children',
      params: [
        _v('spacing', _double, def: 0.0),
        _v('runSpacing', _double, def: 0.0),
      ],
    ),
    WidgetSchema(
      type: 'Divider',
      category: WidgetCategory.layout,
      summary: 'A one-pixel horizontal rule.',
      params: [
        _v('height', _opt(_double)),
        _v('thickness', _opt(_double)),
        _v('color', _opt(_color)),
      ],
    ),

    // ---- content -----------------------------------------------------------
    WidgetSchema(
      type: 'Text',
      category: WidgetCategory.content,
      summary: 'A run of styled text.',
      params: [
        _v('data', _string, req: true, pos: true),
        _v('style', _opt(_textStyle)),
        _v('textAlign', _opt(_enum('TextAlign'))),
        _v('maxLines', _opt(_int)),
        _v('overflow', _opt(_enum('TextOverflow'))),
      ],
    ),
    WidgetSchema(
      type: 'Icon',
      category: WidgetCategory.content,
      summary: 'A glyph from an icon font.',
      params: [
        _v('icon', _iconData, req: true, pos: true),
        _v('size', _opt(_double)),
        _v('color', _opt(_color)),
      ],
    ),
    WidgetSchema(
      type: 'Image',
      category: WidgetCategory.content,
      constructor: 'network',
      constCtor: false,
      summary: 'An image loaded over the network.',
      params: [
        _v('src', _string, req: true, pos: true),
        _v('width', _opt(_double)),
        _v('height', _opt(_double)),
        _v('fit', _opt(_enum('BoxFit'))),
      ],
    ),
    WidgetSchema(
      type: 'CircularProgressIndicator',
      category: WidgetCategory.content,
      summary: 'An indeterminate spinner.',
      params: [_v('color', _opt(_color))],
    ),

    // ---- input -------------------------------------------------------------
    WidgetSchema(
      type: 'ElevatedButton',
      category: WidgetCategory.input,
      summary: 'A filled button.',
      childArity: ChildArity.one,
      childrenParam: 'child',
      params: [_callback('onPressed', req: true)],
    ),
    WidgetSchema(
      type: 'TextButton',
      category: WidgetCategory.input,
      summary: 'A flat button.',
      childArity: ChildArity.one,
      childrenParam: 'child',
      params: [_callback('onPressed', req: true)],
    ),
    WidgetSchema(
      type: 'OutlinedButton',
      category: WidgetCategory.input,
      summary: 'A button with an outline.',
      childArity: ChildArity.one,
      childrenParam: 'child',
      params: [_callback('onPressed', req: true)],
    ),
    WidgetSchema(
      type: 'IconButton',
      category: WidgetCategory.input,
      summary: 'A tappable icon.',
      params: [
        _callback('onPressed', req: true),
        _child('icon', req: true),
        _v('tooltip', _opt(_string)),
      ],
    ),
    WidgetSchema(
      type: 'FloatingActionButton',
      category: WidgetCategory.input,
      summary: 'The primary action of a page.',
      childArity: ChildArity.one,
      childrenParam: 'child',
      params: [
        _callback('onPressed', req: true),
        _v('tooltip', _opt(_string)),
      ],
    ),
    WidgetSchema(
      type: 'TextField',
      category: WidgetCategory.input,
      summary: 'A single-line text input.',
      composites: {'decoration': 'InputDecoration'},
      params: [
        _callback('onChanged', payload: _string),
        _callback('onSubmitted', payload: _string),
        _v('hintText', _opt(_string), into: 'decoration'),
        _v('labelText', _opt(_string), into: 'decoration'),
        _v('obscureText', _bool, def: false),
        _v('keyboardType', _opt(_enum('TextInputType'))),
      ],
    ),
    WidgetSchema(
      type: 'Checkbox',
      category: WidgetCategory.input,
      summary: 'A binary toggle box.',
      params: [
        _v('value', _bool, req: true),
        _callback('onChanged', payload: _bool, req: true),
      ],
    ),
    WidgetSchema(
      type: 'Switch',
      category: WidgetCategory.input,
      summary: 'A binary on/off switch.',
      params: [
        _v('value', _bool, req: true),
        _callback('onChanged', payload: _bool, req: true),
      ],
    ),
    WidgetSchema(
      type: 'Slider',
      category: WidgetCategory.input,
      summary: 'A continuous value picker.',
      params: [
        _v('value', _double, req: true),
        _callback('onChanged', payload: _double, req: true),
        _v('min', _double, def: 0.0),
        _v('max', _double, def: 1.0),
      ],
    ),
    WidgetSchema(
      type: 'GestureDetector',
      category: WidgetCategory.input,
      constCtor: false,
      summary: 'Recognises taps on an arbitrary child.',
      childArity: ChildArity.one,
      childrenParam: 'child',
      params: [
        _callback('onTap'),
        _callback('onLongPress'),
      ],
    ),
    WidgetSchema(
      type: 'InkWell',
      category: WidgetCategory.input,
      summary: 'Tap target with a material ripple.',
      childArity: ChildArity.one,
      childrenParam: 'child',
      params: [_callback('onTap')],
    ),
  ];
}
