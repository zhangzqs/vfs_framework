import 'package:xml/xml.dart';

import 'file.dart';
import 'utils.dart';

/// XML template for WebDAV PROPFIND requests to retrieve file information.
const fileXmlStr = '''<d:propfind xmlns:d='DAV:'>
			<d:prop>
				<d:displayname/>
				<d:resourcetype/>
				<d:getcontentlength/>
				<d:getcontenttype/>
				<d:getetag/>
				<d:getlastmodified/>
			</d:prop>
		</d:propfind>''';

// const quotaXmlStr = '''<d:propfind xmlns:d="DAV:">
//            <d:prop>
//              <d:quota-available-bytes/>
//              <d:quota-used-bytes/>
//            </d:prop>
//          </d:propfind>''';

/// Finds all elements with the specified tag in the XML document.
List<XmlElement> findAllElements(XmlDocument document, String tag) =>
    document.findAllElements(tag, namespace: '*').toList();

/// Finds all child elements with the specified tag in the given element.
List<XmlElement> findElements(XmlElement element, String tag) =>
    element.findElements(tag, namespace: '*').toList();

/// Parses WebDAV XML response and converts it to a list of File objects.
///
/// [path] - The base path for the files
/// [xmlStr] - The XML response string from the WebDAV server
/// [skipSelf] - Whether to skip the first entry (usually the directory itself)
List<File> toFiles(String path, String xmlStr, {bool skipSelf = true}) {
  final files = <File>[];
  final xmlDocument = XmlDocument.parse(xmlStr);
  final list = findAllElements(xmlDocument, 'response');

  // Process each response element
  for (final element in list) {
    // Extract href (file path)
    final hrefElements = findElements(element, 'href');
    final href = hrefElements.isNotEmpty ? hrefElements.single.innerText : '';

    // Process propstat elements
    final props = findElements(element, 'propstat');
    for (final propstat in props) {
      // Only process entries with 200 status
      final statusElements = findElements(propstat, 'status');
      if (statusElements.isNotEmpty &&
          statusElements.single.innerText.contains('200')) {
        for (final prop in findElements(propstat, 'prop')) {
          final resourceTypeElements = findElements(prop, 'resourcetype');

          // Determine if this is a directory
          final isDir =
              resourceTypeElements.isNotEmpty &&
              findElements(
                resourceTypeElements.single,
                'collection',
              ).isNotEmpty;

          // Skip self reference if requested
          if (skipSelf) {
            skipSelf = false;
            if (isDir) {
              break;
            }
            throw newXmlError('xml parse error(405)');
          }

          // Extract MIME type
          final mimeTypeElements = findElements(prop, 'getcontenttype');
          final mimeType = mimeTypeElements.isNotEmpty
              ? mimeTypeElements.single.innerText
              : '';

          // Extract file size (only for files, not directories)
          int size = 0;
          if (!isDir) {
            final sizeElements = findElements(prop, 'getcontentlength');
            if (sizeElements.isNotEmpty) {
              final sizeText = sizeElements.single.innerText;
              size = int.tryParse(sizeText) ?? 0;
            }
          }

          // Extract ETag
          final eTagElements = findElements(prop, 'getetag');
          final eTag = eTagElements.isNotEmpty
              ? eTagElements.single.innerText
              : '';

          // Extract creation time
          final cTimeElements = findElements(prop, 'creationdate');
          DateTime? cTime;
          if (cTimeElements.isNotEmpty) {
            final timeText = cTimeElements.single.innerText;
            try {
              cTime = DateTime.parse(timeText).toLocal();
            } catch (e) {
              cTime = null;
            }
          }

          // Extract modification time
          final mTimeElements = findElements(prop, 'getlastmodified');
          final mTime = mTimeElements.isNotEmpty
              ? str2LocalTime(mTimeElements.single.innerText)
              : null;

          // Build file path and name
          if (href.isNotEmpty) {
            final decodedHref = Uri.decodeFull(href);
            final name = path2Name(decodedHref);
            final filePath = '$path$name${isDir ? '/' : ''}';

            files.add(
              File(
                path: filePath,
                isDir: isDir,
                name: name,
                mimeType: mimeType,
                size: size,
                eTag: eTag,
                cTime: cTime,
                mTime: mTime,
              ),
            );
          }
          break;
        }
      }
    }
  }
  return files;
}
