import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../state/async_cache.dart';
import '../theme/colors.dart';
import 'error_view.dart';

/// Standard renderer for an [AsyncCache]-backed screen. Handles all four
/// states (first-load skeleton, first-load error, stale-with-refresh,
/// fresh) so each screen only has to provide:
///   - the cache
///   - a [placeholder] value to feed [builder] while real data is missing
///   - the actual [builder] that renders content given a non-null T
///   - a short [where] string used by the embedded [ErrorView]
///
/// Stack with `fit: expand` so the content widget gets the full available
/// space (the LinearProgressIndicator at the top is positioned absolutely
/// and doesn't compete for layout).
class CachedView<T> extends StatelessWidget {
  const CachedView({
    super.key,
    required this.cache,
    required this.placeholder,
    required this.builder,
    this.where = 'this screen',
    this.showProgressBar = true,
  });

  /// When false, the thin top refresh bar is not drawn — the host screen is
  /// expected to surface the refreshing state itself (e.g. a progress bar
  /// pinned above its own header). Defaults to true.
  final bool showProgressBar;

  final AsyncCache<T> cache;
  /// Realistic-shape dummy used to populate [builder] during the first-load
  /// skeleton state. Should look like real data with enough rows/items to
  /// fill the expected layout; the actual values don't matter because
  /// everything renders as a skeleton block.
  final T placeholder;
  final Widget Function(BuildContext, T data) builder;
  final String where;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cache,
      builder: (_, __) {
        final hasData = cache.data != null;
        if (!hasData && cache.error != null && !cache.refreshing) {
          return ErrorView(
            error: cache.error!,
            stack: cache.stack,
            where: where,
            // ignore: discarded_futures
            onRetry: () => cache.refresh(),
          );
        }
        final data = cache.data ?? placeholder;
        return Stack(
          fit: StackFit.expand,
          children: [
            Skeletonizer(
              enabled: !hasData,
              child: builder(context, data),
            ),
            if (showProgressBar && hasData && cache.refreshing)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: BrandColors.accent,
                  backgroundColor: Colors.transparent,
                ),
              ),
          ],
        );
      },
    );
  }
}
