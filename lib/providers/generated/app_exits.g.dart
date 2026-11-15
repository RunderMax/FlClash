// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../app_exits.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AppExits)
final appExitsProvider = AppExitsProvider._();

final class AppExitsProvider
    extends $AsyncNotifierProvider<AppExits, Map<String, List<AppExit>>> {
  AppExitsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appExitsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appExitsHash();

  @$internal
  @override
  AppExits create() => AppExits();
}

String _$appExitsHash() => r'40f371a68081df0500b579c46862b403e04f4996';

abstract class _$AppExits extends $AsyncNotifier<Map<String, List<AppExit>>> {
  FutureOr<Map<String, List<AppExit>>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<Map<String, List<AppExit>>>,
              Map<String, List<AppExit>>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<Map<String, List<AppExit>>>,
                Map<String, List<AppExit>>
              >,
              AsyncValue<Map<String, List<AppExit>>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
