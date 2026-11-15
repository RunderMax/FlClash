// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../pick_routes.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Changes only when the routes do, not with every request.

@ProviderFor(PickRoutesState)
final pickRoutesStateProvider = PickRoutesStateProvider._();

/// Changes only when the routes do, not with every request.
final class PickRoutesStateProvider
    extends $NotifierProvider<PickRoutesState, PickRoutes> {
  /// Changes only when the routes do, not with every request.
  PickRoutesStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pickRoutesStateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pickRoutesStateHash();

  @$internal
  @override
  PickRoutesState create() => PickRoutesState();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PickRoutes value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PickRoutes>(value),
    );
  }
}

String _$pickRoutesStateHash() => r'83689f31a41c2f0d60a2c6e4e40a4954fe60d994';

/// Changes only when the routes do, not with every request.

abstract class _$PickRoutesState extends $Notifier<PickRoutes> {
  PickRoutes build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PickRoutes, PickRoutes>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PickRoutes, PickRoutes>,
              PickRoutes,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
