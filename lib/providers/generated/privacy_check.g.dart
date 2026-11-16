// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../privacy_check.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Android's VPN takes every app's sockets, this one's too; a desktop hands
/// them to the core only while its TUN runs, and otherwise leaves the system
/// proxy to apps that ask for it.

@ProviderFor(capturesAppSockets)
final capturesAppSocketsProvider = CapturesAppSocketsProvider._();

/// Android's VPN takes every app's sockets, this one's too; a desktop hands
/// them to the core only while its TUN runs, and otherwise leaves the system
/// proxy to apps that ask for it.

final class CapturesAppSocketsProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Android's VPN takes every app's sockets, this one's too; a desktop hands
  /// them to the core only while its TUN runs, and otherwise leaves the system
  /// proxy to apps that ask for it.
  CapturesAppSocketsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'capturesAppSocketsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$capturesAppSocketsHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return capturesAppSockets(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$capturesAppSocketsHash() =>
    r'a3755a927f41b7f694eb98f1af57a32a30893bc7';

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

String _$privacyCheckHash() => r'1cd193955eede688f6d42dfe3402de8d2e143464';

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
