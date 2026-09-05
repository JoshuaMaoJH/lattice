/// Hand-written, called from the graph through a `Dart Code` node — and this
/// one runs on the *server* (§7.8, §7.7).
///
/// A price list is a table, not a computation, and it is also the sort of
/// thing that should not be shipped to a client. Both reasons point here.
///
/// Nothing in this file may import Flutter: the mirror that copies it onto the
/// server checks, and says so rather than letting the server fail to compile.
const Map<String, double> _catalogue = {
  'PRO': 49.0,
  'TEAM': 149.0,
  'LITE': 19.0,
  'BASIC': 9.0,
};

/// The list price for a SKU, by its family prefix.
double unitPriceFor(String sku) {
  final family = sku.split('-').first.toUpperCase();
  return _catalogue[family] ?? _catalogue['BASIC']!;
}

/// Volume discount, as a fraction.
double discountFor(int quantity) {
  if (quantity >= 100) return 0.2;
  if (quantity >= 25) return 0.15;
  if (quantity >= 10) return 0.1;
  return 0;
}
