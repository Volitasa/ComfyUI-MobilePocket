import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comfyui_mobilepocket/l10n/app_localizations.dart';
import 'package:comfyui_mobilepocket/services/image_ref.dart';
import 'package:comfyui_mobilepocket/services/server_image_service.dart';
import 'package:comfyui_mobilepocket/ui/builder/server_image_picker_view.dart';

/// 只想验证界面，不打真服务器
class _FakeService extends ServerImageService {
  _FakeService(this.listing, {this.fail = false});

  final ServerImageListing listing;
  final bool fail;
  int calls = 0;

  @override
  Future<ServerImageListing> list(String baseUrl, {required String type}) async {
    calls++;
    if (fail) throw Exception('boom');
    return listing;
  }
}

Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

void main() {
  testWidgets('两个目录各一个 Tab，有图时铺成网格', (tester) async {
    final service = _FakeService(
      const ServerImageListing(
        images: [
          ImageRef(filename: 'a.png', type: 'output'),
          ImageRef(filename: 'b.png', type: 'output'),
        ],
      ),
    );

    await tester.pumpWidget(
      _wrap(ServerImagePickerView(baseUrl: 'http://h:8190', service: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('输出目录'), findsOneWidget);
    expect(find.text('输入目录'), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));
  });

  testWidgets('点一张就把 ImageRef 返回给调用方', (tester) async {
    final service = _FakeService(
      const ServerImageListing(
        images: [ImageRef(filename: 'picked.png', type: 'output')],
      ),
    );

    ImageRef? result;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<ImageRef>(
                    MaterialPageRoute(
                      builder: (_) => ServerImagePickerView(
                        baseUrl: 'http://h:8190',
                        service: service,
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Image).first);
    await tester.pumpAndSettle();

    expect(result?.value, 'picked.png [output]');
  });

  testWidgets('空目录给空态，不是一张白屏', (tester) async {
    final service = _FakeService(const ServerImageListing(images: []));

    await tester.pumpWidget(
      _wrap(ServerImagePickerView(baseUrl: 'http://h:8190', service: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('这个目录里还没有图片'), findsOneWidget);
  });

  testWidgets('internal 不可用时顶部如实说明降级', (tester) async {
    final service = _FakeService(
      const ServerImageListing(
        images: [ImageRef(filename: 'a.png', type: 'output')],
        degraded: true,
      ),
    );

    await tester.pumpWidget(
      _wrap(ServerImagePickerView(baseUrl: 'http://h:8190', service: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('这台服务器只能列出生成过的图片'), findsOneWidget);
  });

  testWidgets('读取失败给重试入口', (tester) async {
    final service = _FakeService(const ServerImageListing(images: []), fail: true);

    await tester.pumpWidget(
      _wrap(ServerImagePickerView(baseUrl: 'http://h:8190', service: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('读不到服务器的图片列表'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}
