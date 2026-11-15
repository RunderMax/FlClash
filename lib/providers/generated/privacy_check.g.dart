// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../privacy_check.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(PrivacyCheck)
final privacyCheckProvider = PrivacyCheckProvider._();

final class PrivacyCheckProvider
    extends $NotifierProvider<PrivacyCheck, PrivacyCheckState> {
  PrivacyCheckProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'privacyCheckProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$privacyCheckHash();

  @$internal
  @override
  PrivacyCheck create() => PrivacyCheck();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PrivacyCheckState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PrivacyCheckState>(value),
    );
  }
}

String _$privacyCheckHash() => r'daf1da099c35924c5282e36b648ff28ef64538c9';

abstract class _$PrivacyCheck extends $Notifier<PrivacyCheckState> {
  PrivacyCheckState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PrivacyCheckState, PrivacyCheckState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PrivacyCheckState, PrivacyCheckState>,
              PrivacyCheckState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
