import 'dart:js_interop';

@JS('zettaxTrackDownload')
external void _trackDownload(JSString source);

void trackDownloadClick(String source) => _trackDownload(source.toJS);
