import 'dart:io';
import 'package:args/args.dart';



void main(List<String> args) async {
  var parser = ArgParser();

  parser.addOption('port', abbr: 'p', defaultsTo: '9090');
  parser.addOption('listen', abbr: 'l', defaultsTo: '127.0.0.1');

  var result = parser.parse(args);

  var port = int.tryParse(result.option('port')!) ?? 9090;
  var addr = result.option('listen')!;
  var server = await HttpServer.bind(addr, port);

  server.listen((req) async {
    var headerMaps = {};
    ///nginx proxy
    var xIp = 'X-Real-IP'.toLowerCase();
    req.headers.forEach((k, v) => headerMaps[k.toLowerCase()] = v.join(';'));
    var rAddress = req.connectionInfo?.remoteAddress.toString();
    if (headerMaps.containsKey(xIp)) {
      rAddress = headerMaps[xIp];
    }

    print('${DateTime.now()}---> $rAddress - ${req.method} ${req.requestedUri}');

    try {
      void close() {
        req.response.write('Fast Server Is Running');
        req.response.close();
      }

      var path = req.uri.path;
      if (path.isEmpty || path == '/' || !path.startsWith('/')) {
        close();
        return;
      }

      var uri = Uri.tryParse(req.uri.path.substring(1));

      if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
        close();
        return;
      }
      var client = HttpClient();
      ///close forward client when req done or disconnect
      req.response.done.then((_) {
        client.close(force: true);
        req.response.close();
      });
      var fReq = await client.openUrl(req.method, uri.replace(queryParameters: {...req.requestedUri.queryParameters}));
      req.headers.forEach(fReq.headers.set);
      ///fix host
      fReq.headers.set('host', uri.host);
      fReq.close().then((fRes) {
        req.response.headers.clear();
        bool isGzip = false;
        fRes.headers.forEach((k, v) {
          if (k.toLowerCase() == 'content-encoding' && v.join(';') == 'gzip') {
            isGzip = true;
          }
          req.response.headers.set(k, v);
        });
        ///fix gzip encoding
        Stream stream = isGzip ? fRes.transform(gzip.encoder) : fRes.cast<List<int>>();

        stream.pipe(req.response).onError((e, s) {
          req.response.close();
          client.close(force: true);
        }).whenComplete(() {
          req.response.close();
          client.close();
        });
      });
    } catch (e) {
      if (e is Error) {
        print(e.stackTrace);
      }
      print('request error：${req.requestedUri}-$e');
      req.response.statusCode = 404;
      req.response.close();
    }
  });
  print('server listen on http://$addr:$port');
}

