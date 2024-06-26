import 'package:flexible_polyline_dart/converter.dart';
import 'package:flexible_polyline_dart/latlngz.dart';

class FlexiblePolyline {
  static const int version = 1;
  static final List<String> encodingTable =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'
          .split('');
  static final List<int> decodingTable = [
    62,
    -1,
    -1,
    52,
    53,
    54,
    55,
    56,
    57,
    58,
    59,
    60,
    61,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22,
    23,
    24,
    25,
    -1,
    -1,
    -1,
    -1,
    63,
    -1,
    26,
    27,
    28,
    29,
    30,
    31,
    32,
    33,
    34,
    35,
    36,
    37,
    38,
    39,
    40,
    41,
    42,
    43,
    44,
    45,
    46,
    47,
    48,
    49,
    50,
    51
  ];

  ///
  /// Decode the encoded input {@link String} to {@link List} of coordinate
  /// triples.
  ///
  /// @param encoded URL-safe encoded {@link String}
  /// @return {@link List} of coordinate triples that are decoded from input
  ///
  /// @see FlexiblePolyline#getThirdDimension(String) getThirdDimension
  /// @see LatLngZ
  ///
  static List<LatLngZ> decode(String? encoded) {
    if (encoded == null || encoded.trim().isEmpty) {
      throw ArgumentError("Invalid argument!");
    }
    final List<LatLngZ> results = [];
    final _Decoder dec = _Decoder(encoded);
    LatLngZ? result;

    do {
      result = dec.decodeOne();
      if (result != null) results.add(result);
    } while (result != null);
    return results;
  }

  ///
  /// Encode the list of coordinate triples.<BR><BR>
  /// The third dimension value will be eligible for encoding only when
  /// ThirdDimension is other than ABSENT.
  /// This is lossy compression based on precision accuracy.
  ///
  /// @param coordinates {@link List} of coordinate triples that to be encoded.
  /// @param precision   Floating point precision of the coordinate to be
  /// encoded.
  /// @param thirdDimension {@link ThirdDimension} which may be a level,
  /// altitude, elevation or some other custom value
  /// @param thirdDimPrecision Floating point precision for thirdDimension value
  /// @return URL-safe encoded {@link String} for the given coordinates.
  ///
  static String encode(List<LatLngZ>? coordinates, int precision,
      ThirdDimension? thirdDimension, int thirdDimPrecision) {
    if (coordinates == null || coordinates.isEmpty) {
      throw ArgumentError("Invalid coordinates!");
    }
    if (thirdDimension == null) {
      throw ArgumentError("Invalid thirdDimension");
    }
    final _Encoder enc = _Encoder(precision, thirdDimension, thirdDimPrecision);
    final Iterator<LatLngZ> iter = coordinates.iterator;
    while (iter.moveNext()) {
      enc.add(iter.current);
    }
    return enc.getEncoded();
  }

  /// ThirdDimension type from the encoded input {@link String}
  /// @param encoded URL-safe encoded coordinate triples {@link String}
  /// @return type of {@link ThirdDimension}
  static ThirdDimension getThirdDimension(List<String> encoded) {
    int index = 0;
    (BigInt, int) headerResult =
        _Decoder.decodeHeaderFromString(encoded, index);
    final int header = headerResult.$1.toInt();
    return ThirdDimension.values[(header >> 4) & 7];
  }
}

/// Single instance for decoding an input request.
class _Decoder {
  final String encoded;
  late int index;
  late Converter latConverter;
  late Converter lngConverter;
  late Converter zConverter;
  late List<String> split;

  late int precision;
  late int thirdDimPrecision;
  late ThirdDimension thirdDimension;

  _Decoder(this.encoded) {
    index = 0;
    split = encoded.split('');
    _decodeHeader();
    latConverter = Converter(precision);
    lngConverter = Converter(precision);
    zConverter = Converter(thirdDimPrecision);
  }

  bool hasThirdDimension() => thirdDimension != ThirdDimension.ABSENT;

  void _decodeHeader() {
    final (BigInt, int) headerResult = decodeHeaderFromString(split, index);
    int header = headerResult.$1.toInt();
    index = headerResult.$2;
    precision = header & 15; // we pick the first 3 bits only
    header = header >> 4;

    thirdDimension =
        ThirdDimension.values[header & 7]; // we pick the first 4 bits only
    thirdDimPrecision = (header >> 3) & 15;
  }

  // Returns polyline header, new index in tuple.
  static (BigInt, int) decodeHeaderFromString(List<String> encoded, int index) {
    // Decode the header version
    final (BigInt, int) result = Converter.decodeUnsignedVarint(encoded, index);

    if (result.$1.toInt() != FlexiblePolyline.version) {
      throw ArgumentError("Invalid format version");
    }

    // Decode the polyline header
    return Converter.decodeUnsignedVarint(encoded, result.$2);
  }

  LatLngZ? decodeOne() {
    if (index == encoded.length) {
      return null;
    }
    final (double, int) latResult = latConverter.decodeValue(split, index);
    index = latResult.$2;
    final (double, int) lngResult = lngConverter.decodeValue(split, index);
    index = lngResult.$2;
    if (hasThirdDimension()) {
      final (double, int) zResult = zConverter.decodeValue(split, index);
      index = zResult.$2;
      return LatLngZ(latResult.$1, lngResult.$1, zResult.$1);
    }
    return LatLngZ(latResult.$1, lngResult.$1);
  }
}

/// Single instance for configuration, validation and encoding for an input
/// request.
class _Encoder {
  final int precision;
  final ThirdDimension thirdDimension;
  final int thirdDimPrecision;
  late Converter latConverter;
  late Converter lngConverter;
  late Converter zConverter;
  String result = '';

  _Encoder(this.precision, this.thirdDimension, this.thirdDimPrecision) {
    latConverter = Converter(precision);
    lngConverter = Converter(precision);
    zConverter = Converter(thirdDimPrecision);
    encodeHeader();
  }

  void encodeHeader() {
    final int thirdDimensionValue = thirdDimension.index;

    /// Encode the `precision`, `third_dim` and `third_dim_precision` into one
    /// encoded char
    if (precision < 0 || precision > 15) {
      throw ArgumentError("precision out of range");
    }

    if (thirdDimPrecision < 0 || thirdDimPrecision > 15) {
      throw ArgumentError("thirdDimPrecision out of range");
    }

    if (thirdDimensionValue < 0 || thirdDimensionValue > 7) {
      throw ArgumentError("thirdDimensionValue out of range");
    }
    final double res =
        ((thirdDimPrecision << 7) | (thirdDimensionValue << 4) | precision)
            .toDouble();
    result +=
        Converter.encodeUnsignedVarint(BigInt.from(FlexiblePolyline.version));
    result += Converter.encodeUnsignedVarint(BigInt.from(res));
  }

  void addTuple(double lat, double lng) {
    result += latConverter.encodeValue(lat);
    result += lngConverter.encodeValue(lng);
  }

  void addTriple(double lat, double lng, double z) {
    addTuple(lat, lng);
    if (thirdDimension != ThirdDimension.ABSENT) {
      result += zConverter.encodeValue(z);
    }
  }

  void add(LatLngZ? tuple) {
    if (tuple == null) {
      throw ArgumentError("Invalid LatLngZ tuple");
    }
    addTriple(tuple.lat, tuple.lng, tuple.z);
  }

  String getEncoded() => result.toString();
}
