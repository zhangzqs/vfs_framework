import 'dart:convert';
import 'dart:io';

import 'package:json_annotation/json_annotation.dart';
import 'package:xml2json/xml2json.dart';

part 'propfind_xml.g.dart';

const propfindRequestXML = '''
<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:displayname/>
    <d:getlastmodified/>
    <d:getcontentlength/>
    <d:getcontenttype/>
    <d:getetag/>
    <d:resourcetype/>
  </d:prop>
</d:propfind>
''';

@JsonSerializable(explicitToJson: true)
class WebDAVPropfindResponse {
  WebDAVPropfindResponse({required this.multistatus});
  factory WebDAVPropfindResponse.fromJson(Map<String, dynamic> json) =>
      _$WebDAVPropfindResponseFromJson(json);
  factory WebDAVPropfindResponse.fromXml(String xmlString) {
    final jsonMap = _convertXmlToJson(xmlString);
    return WebDAVPropfindResponse.fromJson(jsonMap);
  }
  @JsonKey(name: 'multistatus')
  WebDAVMultistatus multistatus;

  Map<String, dynamic> toJson() => _$WebDAVPropfindResponseToJson(this);
}

@JsonSerializable(explicitToJson: true)
class WebDAVMultistatus {
  WebDAVMultistatus({required this.responses});

  factory WebDAVMultistatus.fromJson(Map<String, dynamic> json) =>
      _$WebDAVMultistatusFromJson(json);

  @JsonKey(name: 'response', fromJson: _responseFromJson)
  final List<WebDAVResponse> responses;

  // 静态方法用于处理propstat的反序列化
  static List<WebDAVResponse> _responseFromJson(dynamic json) {
    if (json == null) return [];

    if (json is List) {
      // 如果是数组，直接转换每个元素
      return json
          .map((item) => WebDAVResponse.fromJson(item as Map<String, dynamic>))
          .toList();
    } else if (json is Map<String, dynamic>) {
      // 如果是单个对象，包装成数组
      return [WebDAVResponse.fromJson(json)];
    }

    throw FormatException(
      'Invalid response format: $json. Expected a Map or List.',
    );
  }

  Map<String, dynamic> toJson() => _$WebDAVMultistatusToJson(this);
}

@JsonSerializable(explicitToJson: true)
class WebDAVResponse {
  WebDAVResponse({required this.href, required this.propstats});

  factory WebDAVResponse.fromJson(Map<String, dynamic> json) =>
      _$WebDAVResponseFromJson(json);

  @JsonKey(name: 'href')
  final String href;

  @JsonKey(name: 'propstat', fromJson: _propstatFromJson)
  final List<WebDAVPropstat> propstats;

  // 静态方法用于处理propstat的反序列化
  static List<WebDAVPropstat> _propstatFromJson(dynamic json) {
    if (json == null) return [];

    if (json is List) {
      // 如果是数组，直接转换每个元素
      return json
          .map((item) => WebDAVPropstat.fromJson(item as Map<String, dynamic>))
          .toList();
    } else if (json is Map<String, dynamic>) {
      // 如果是单个对象，包装成数组
      return [WebDAVPropstat.fromJson(json)];
    }

    throw FormatException(
      'Invalid propstat format: $json. Expected a Map or List.',
    );
  }

  Map<String, dynamic> toJson() => _$WebDAVResponseToJson(this);

  bool get isDirectory {
    return propstats.any((propstat) => propstat.prop.isDirectory());
  }

  DateTime? get lastModified {
    for (final propstat in propstats) {
      if (propstat.prop.lastModified != null) {
        return propstat.prop.lastModified;
      }
    }
    return null;
  }

  String? get contentType {
    for (final propstat in propstats) {
      if (propstat.prop.contentType != null) {
        return propstat.prop.contentType;
      }
    }
    return null;
  }

  int? get contentLength {
    for (final propstat in propstats) {
      if (propstat.prop.contentLength != null) {
        return propstat.prop.contentLength;
      }
    }
    return null;
  }
}

@JsonSerializable(explicitToJson: true)
class WebDAVPropstat {
  WebDAVPropstat({required this.prop, required this.status});

  factory WebDAVPropstat.fromJson(Map<String, dynamic> json) =>
      _$WebDAVPropstatFromJson(json);

  @JsonKey(name: 'prop')
  final WebDAVProp prop;

  @JsonKey(name: 'status')
  final String status;

  Map<String, dynamic> toJson() => _$WebDAVPropstatToJson(this);
}

@JsonSerializable(explicitToJson: true)
class WebDAVProp {
  WebDAVProp({
    this.displayName,
    this.lastModified,
    this.contentLength,
    this.resourceType,
    this.contentType,
    this.etag,
  });

  factory WebDAVProp.fromJson(Map<String, dynamic> json) =>
      _$WebDAVPropFromJson(json);

  @JsonKey(name: 'displayname')
  final String? displayName;

  @JsonKey(name: 'getlastmodified', fromJson: _parseLastModified)
  final DateTime? lastModified;

  static DateTime? _parseLastModified(dynamic value) {
    if (value == null) return null;

    final stringValue = value.toString().trim();
    if (stringValue.isEmpty) return null;

    try {
      // 首先尝试使用Dart标准库的HttpDate解析
      // HttpDate专门用于解析RFC 2822/HTTP日期格式
      return HttpDate.parse(stringValue);
    } catch (e) {
      try {
        // 如果HttpDate失败，尝试标准的DateTime.parse
        return DateTime.parse(stringValue).toUtc();
      } catch (e2) {
        // 如果都失败了，返回null并记录错误
        print('Failed to parse WebDAV date: $stringValue (${e.toString()})');
        return null;
      }
    }
  }

  @JsonKey(name: 'getcontentlength', fromJson: _parseContentLength)
  final int? contentLength;

  static int? _parseContentLength(dynamic value) {
    if (value == null) return null;

    final stringValue = value.toString().trim();
    if (stringValue.isEmpty) return null;

    try {
      return int.parse(stringValue);
    } catch (e) {
      print('Failed to parse content length: $stringValue');
      return null;
    }
  }

  @JsonKey(name: 'getcontenttype')
  final String? contentType;

  @JsonKey(name: 'getetag')
  final String? etag;

  @JsonKey(name: 'resourcetype')
  final WebDAVResourceType? resourceType;

  bool isDirectory() {
    return resourceType?.isDirectory ?? false;
  }

  Map<String, dynamic> toJson() => _$WebDAVPropToJson(this);
}

@JsonSerializable(explicitToJson: true)
class WebDAVResourceType {
  WebDAVResourceType({
    this.collection,
    this.principal,
    this.calendar,
    this.addressbook,
  });

  factory WebDAVResourceType.fromJson(Map<String, dynamic> json) =>
      _$WebDAVResourceTypeFromJson(json);

  @JsonKey(name: 'collection')
  final dynamic collection; // 可能是空 Map 或 null

  @JsonKey(name: 'principal')
  final dynamic principal; // Principal 资源

  @JsonKey(name: 'calendar')
  final dynamic calendar; // CalDAV 日历

  @JsonKey(name: 'addressbook')
  final dynamic addressbook; // CardDAV 通讯录

  /// 是否为目录/集合
  bool get isDirectory => collection != null;

  /// 是否为普通文件
  bool get isFile =>
      collection == null &&
      principal == null &&
      calendar == null &&
      addressbook == null;

  /// 是否为Principal资源
  bool get isPrincipal => principal != null;

  /// 是否为日历
  bool get isCalendar => calendar != null;

  /// 是否为通讯录
  bool get isAddressbook => addressbook != null;

  /// 获取资源类型的描述
  String get typeDescription {
    final types = <String>[];

    if (isDirectory) types.add('Collection');
    if (isPrincipal) types.add('Principal');
    if (isCalendar) types.add('Calendar');
    if (isAddressbook) types.add('Addressbook');

    if (types.isEmpty) return 'File';
    return types.join(', ');
  }

  Map<String, dynamic> toJson() => _$WebDAVResourceTypeToJson(this);
}

Map<String, dynamic> _convertXmlToJson(String xmlString) {
  final transformer = Xml2Json();
  print("Converting XML to JSON...${xmlString}");

  transformer.parse(xmlString);
  final openRallyJson = transformer.toOpenRally();
  print(openRallyJson);
  return jsonDecode(openRallyJson) as Map<String, dynamic>;
}
