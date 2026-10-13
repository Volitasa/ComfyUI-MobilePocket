import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/release_info.dart';
import '../services/update_service.dart';
import 'github_token_provider.dart';
import 'locale_provider.dart';

/// 更新检查的状态：仅手动触发，没有自动检查。
enum UpdateStatus { idle, checking, upToDate, available, downloading, error }

class UpdateState {
  final UpdateStatus status;
  final ReleaseInfo? release;
  final double progress;
  final String? message;
  final String currentVersion;
  final String currentBuild;

  const UpdateState({
    this.status = UpdateStatus.idle,
    this.release,
    this.progress = 0,
    this.message,
    this.currentVersion = '',
    this.currentBuild = '',
  });

  UpdateState copyWith({
    UpdateStatus? status,
    ReleaseInfo? release,
    double? progress,
    String? message,
    String? currentVersion,
    String? currentBuild,
  }) {
    return UpdateState(
      status: status ?? this.status,
      release: release ?? this.release,
      progress: progress ?? this.progress,
      message: message ?? this.message,
      currentVersion: currentVersion ?? this.currentVersion,
      currentBuild: currentBuild ?? this.currentBuild,
    );
  }
}

class UpdateNotifier extends Notifier<UpdateState> {
  @override
  UpdateState build() => const UpdateState();

  /// 读取当前安装包的版本与构建号（AboutView 初始化时调用）
  Future<void> loadCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      state = state.copyWith(
        currentVersion: info.version,
        currentBuild: info.buildNumber,
      );
    } catch (_) {
      // 取不到不影响页面其它部分，保持空值
    }
  }

  /// 手动检查更新：与当前版本比对，结果写入状态
  Future<void> checkForUpdate() async {
    if (state.status == UpdateStatus.checking ||
        state.status == UpdateStatus.downloading) {
      return;
    }

    state = state.copyWith(
      status: UpdateStatus.checking,
      message: null,
      release: null,
      progress: 0,
    );

    try {
      // 私有仓库需要令牌；未配置时按匿名请求走（仅公开仓库可用）
      final release = await UpdateService.instance.fetchLatestRelease(
        token: ref.read(githubTokenProvider),
        l10n: l10nFor(ref.read(localeProvider)),
      );
      final current = state.currentVersion;
      final hasUpdate =
          current.isEmpty ||
          UpdateService.compareVersion(release.version, current) > 0;

      state = state.copyWith(
        status: hasUpdate ? UpdateStatus.available : UpdateStatus.upToDate,
        release: hasUpdate ? release : null,
      );
    } on UpdateException catch (e) {
      state = state.copyWith(status: UpdateStatus.error, message: e.message);
    } catch (_) {
      state = state.copyWith(
        status: UpdateStatus.error,
        message: l10nFor(ref.read(localeProvider)).updateCheckFailedRetry,
      );
    }
  }

  /// 下载安装包，返回本地路径；进度通过状态回报。
  /// 下载本身不负责安装，交由调用方唤起系统安装界面。
  Future<String> downloadUpdate() async {
    final release = state.release;
    if (release == null) {
      throw UpdateException(l10nFor(ref.read(localeProvider)).updateNoPending);
    }

    state = state.copyWith(
      status: UpdateStatus.downloading,
      progress: 0,
      message: null,
    );

    try {
      final path = await UpdateService.instance.downloadApk(
        release,
        token: ref.read(githubTokenProvider),
        l10n: l10nFor(ref.read(localeProvider)),
        onProgress: (p) {
          state = state.copyWith(progress: p);
        },
      );
      state = state.copyWith(status: UpdateStatus.available, progress: 1);
      return path;
    } on UpdateException catch (e) {
      state = state.copyWith(status: UpdateStatus.error, message: e.message);
      rethrow;
    } catch (_) {
      state = state.copyWith(
        status: UpdateStatus.error,
        message: l10nFor(ref.read(localeProvider)).updateDownloadFailedRetry,
      );
      rethrow;
    }
  }

  void reset() {
    state = state.copyWith(
      status: UpdateStatus.idle,
      release: null,
      progress: 0,
      message: null,
    );
  }
}

final updateProvider = NotifierProvider<UpdateNotifier, UpdateState>(
  UpdateNotifier.new,
);
