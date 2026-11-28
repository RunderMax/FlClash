// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../download_speed.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(DownloadSpeedTest)
final downloadSpeedTestProvider = DownloadSpeedTestProvider._();

final class DownloadSpeedTestProvider
    extends $NotifierProvider<DownloadSpeedTest, DownloadSpeeds> {
  DownloadSpeedTestProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'downloadSpeedTestProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$downloadSpeedTestHash();

  @$internal
  @override
  DownloadSpeedTest create() => DownloadSpeedTest();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DownloadSpeeds value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DownloadSpeeds>(value),
    );
  }
}

String _$downloadSpeedTestHash() => r'b5eb71e735797be404eab491f8ecc29b023ecd83';

abstract class _$DownloadSpeedTest extends $Notifier<DownloadSpeeds> {
  DownloadSpeeds build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<DownloadSpeeds, DownloadSpeeds>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DownloadSpeeds, DownloadSpeeds>,
              DownloadSpeeds,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
