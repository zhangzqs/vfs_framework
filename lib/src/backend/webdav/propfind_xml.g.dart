// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'propfind_xml.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WebDAVPropfindResponse _$WebDAVPropfindResponseFromJson(
  Map<String, dynamic> json,
) => WebDAVPropfindResponse(
  multistatus: WebDAVMultistatus.fromJson(
    json['multistatus'] as Map<String, dynamic>,
  ),
);

Map<String, dynamic> _$WebDAVPropfindResponseToJson(
  WebDAVPropfindResponse instance,
) => <String, dynamic>{'multistatus': instance.multistatus.toJson()};

WebDAVMultistatus _$WebDAVMultistatusFromJson(Map<String, dynamic> json) =>
    WebDAVMultistatus(
      responses: WebDAVMultistatus._responseFromJson(json['response']),
    );

Map<String, dynamic> _$WebDAVMultistatusToJson(WebDAVMultistatus instance) =>
    <String, dynamic>{
      'response': instance.responses.map((e) => e.toJson()).toList(),
    };

WebDAVResponse _$WebDAVResponseFromJson(Map<String, dynamic> json) =>
    WebDAVResponse(
      href: WebDAVResponse._decodeHref(json['href'] as String),
      propstats: WebDAVResponse._propstatFromJson(json['propstat']),
    );

Map<String, dynamic> _$WebDAVResponseToJson(WebDAVResponse instance) =>
    <String, dynamic>{
      'href': instance.href,
      'propstat': instance.propstats.map((e) => e.toJson()).toList(),
    };

WebDAVPropstat _$WebDAVPropstatFromJson(Map<String, dynamic> json) =>
    WebDAVPropstat(
      prop: WebDAVProp.fromJson(json['prop'] as Map<String, dynamic>),
      status: json['status'] as String,
    );

Map<String, dynamic> _$WebDAVPropstatToJson(WebDAVPropstat instance) =>
    <String, dynamic>{
      'prop': instance.prop.toJson(),
      'status': instance.status,
    };

WebDAVProp _$WebDAVPropFromJson(Map<String, dynamic> json) => WebDAVProp(
  displayName: json['displayname'] as String?,
  lastModified: WebDAVProp._parseLastModified(json['getlastmodified']),
  contentLength: WebDAVProp._parseContentLength(json['getcontentlength']),
  resourceType: json['resourcetype'] == null
      ? null
      : WebDAVResourceType.fromJson(
          json['resourcetype'] as Map<String, dynamic>,
        ),
  contentType: json['getcontenttype'] as String?,
  etag: json['getetag'] as String?,
);

Map<String, dynamic> _$WebDAVPropToJson(WebDAVProp instance) =>
    <String, dynamic>{
      'displayname': instance.displayName,
      'getlastmodified': instance.lastModified?.toIso8601String(),
      'getcontentlength': instance.contentLength,
      'getcontenttype': instance.contentType,
      'getetag': instance.etag,
      'resourcetype': instance.resourceType?.toJson(),
    };

WebDAVResourceType _$WebDAVResourceTypeFromJson(Map<String, dynamic> json) =>
    WebDAVResourceType(
      collection: json['collection'],
      principal: json['principal'],
      calendar: json['calendar'],
      addressbook: json['addressbook'],
    );

Map<String, dynamic> _$WebDAVResourceTypeToJson(WebDAVResourceType instance) =>
    <String, dynamic>{
      'collection': instance.collection,
      'principal': instance.principal,
      'calendar': instance.calendar,
      'addressbook': instance.addressbook,
    };
