// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../app_route_activity.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// An app stays marked for a while after its last routed connection.

@ProviderFor(ActiveRoutedApps)
final activeRoutedAppsProvider = ActiveRoutedAppsProvider._();

/// An app stays marked for a while after its last routed connection.
final class ActiveRoutedAppsProvider
    extends $NotifierProvider<ActiveRoutedApps, Set<String>> {
  /// An app stays marked for a while after its last routed connection.
  ActiveRoutedAppsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeRoutedAppsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeRoutedAppsHash();

  @$internal
  @override
  ActiveRoutedApps create() => ActiveRoutedApps();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$activeRoutedAppsHash() => r'0f532dd626b43fd0bad3459bdcef26a53ca8ce77';

/// An app stays marked for a while after its last routed connection.

abstract class _$ActiveRoutedApps extends $Notifier<Set<String>> {
  Set<String> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(GuardBlocked)
final guardBlockedProvider = GuardBlockedProvider._();

final class GuardBlockedProvider
    extends $NotifierProvider<GuardBlocked, GuardBlocks> {
  GuardBlockedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'guardBlockedProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$guardBlockedHash();

  @$internal
  @override
  GuardBlocked create() => GuardBlocked();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GuardBlocks value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GuardBlocks>(value),
    );
  }
}

String _$guardBlockedHash() => r'76804a2c86d89721d3dec6ebc1f14e3050e45a1d';

abstract class _$GuardBlocked extends $Notifier<GuardBlocks> {
  GuardBlocks build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<GuardBlocks, GuardBlocks>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<GuardBlocks, GuardBlocks>,
              GuardBlocks,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
