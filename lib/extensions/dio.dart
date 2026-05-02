import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

extension ChunkDownloaderDioExtension on Dio {
  Future<Response> chunkDownload(
    String urlPath,
    dynamic savePath, {
    ProgressCallback? onReceiveProgress,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    FileAccessMode fileAccessMode = FileAccessMode.write,
    String lengthHeader = Headers.contentLengthHeader,
    Object? data,
    Options? options,
    int connections = 4,
  }) async {
    final targetFile = File(savePath.toString());
    final tempRootDir = await getTemporaryDirectory();
    final tempSaveDir = Directory(
      join(
        tempRootDir.path,
        'Spotube',
        '.chunk_dl_${targetFile.uri.pathSegments.last}',
      ),
    );
    if (await tempSaveDir.exists()) await tempSaveDir.delete(recursive: true);
    await tempSaveDir.create(recursive: true);

    final maxChunkSize = 1024 * 1024; // 1MB for reliability
    try {
      int? totalLength;
      bool supportsRange = false;

      Response? headResp;
      try {
        headResp = await head(
          urlPath,
          queryParameters: queryParameters,
          options: (options ?? Options()).copyWith(
            headers: {
              ...(options?.headers ?? {}),
              'Range': 'bytes=0-0',
            },
            followRedirects: true,
          ),
        );
      } catch (_) {
        // Some servers reject HEAD -> ignore
      }

      final lengthStr = headResp?.headers[lengthHeader]?.first;
      if (lengthStr != null) {
        final parsed = int.tryParse(lengthStr);
        if (parsed != null && parsed > 1) {
          totalLength = parsed;
        }
      }

      supportsRange = headResp?.statusCode == 206 ||
          headResp?.headers.value(HttpHeaders.acceptRangesHeader) == 'bytes';

      if (totalLength == null || totalLength <= 1) {
        final resp = await get<ResponseBody>(
          urlPath,
          options: (options ?? Options()).copyWith(
            responseType: ResponseType.stream,
          ),
          queryParameters: queryParameters,
          cancelToken: cancelToken,
        );

        final len = int.tryParse(resp.headers[lengthHeader]?.first ?? '');
        if (len == null || len <= 1) {
          // can’t safely chunk — fallback
          return download(
            urlPath,
            savePath,
            onReceiveProgress: onReceiveProgress,
            queryParameters: queryParameters,
            cancelToken: cancelToken,
            deleteOnError: deleteOnError,
            options: options,
            data: data,
          );
        }

        totalLength = len;
        supportsRange =
            resp.headers.value(HttpHeaders.acceptRangesHeader)?.toLowerCase() ==
                'bytes';
      }

      if (!supportsRange) {
        return download(
          urlPath,
          savePath,
          onReceiveProgress: onReceiveProgress,
          queryParameters: queryParameters,
          cancelToken: cancelToken,
          deleteOnError: deleteOnError,
          options: options,
          data: data,
        );
      }

      int downloaded = 0;
      final targetSink = targetFile.openWrite(mode: fileAccessMode);

      while (downloaded < totalLength) {
        final start = downloaded;
        final end = (start + maxChunkSize - 1).clamp(0, totalLength - 1);

        bool success = false;
        int retries = 0;
        while (!success && retries < 3) {
          try {
            final resp = await get<ResponseBody>(
              urlPath,
              options: (options ?? Options()).copyWith(
                responseType: ResponseType.stream,
                headers: {
                  ...(options?.headers ?? {}),
                  'Range': 'bytes=$start-$end',
                },
              ),
              queryParameters: queryParameters,
              cancelToken: cancelToken,
            );

            await for (final chunk in resp.data!.stream) {
              targetSink.add(chunk);
              downloaded += chunk.length;
              onReceiveProgress?.call(downloaded, totalLength);
            }
            success = true;
          } catch (e) {
            retries++;
            if (retries >= 3) rethrow;
            await Future.delayed(Duration(seconds: retries));
          }
        }
      }

      await targetSink.close();
      return Response(
        requestOptions: RequestOptions(path: urlPath),
        data: targetFile,
        statusCode: 200,
        statusMessage: 'Robust chunked download completed',
      );
    } catch (e) {

      if (deleteOnError) {
        if (await targetFile.exists()) await targetFile.delete();
        if (await tempSaveDir.exists()) {
          await tempSaveDir.delete(recursive: true);
        }
      }
      rethrow;
    }
  }
}
