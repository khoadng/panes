import 'package:flutter_test/flutter_test.dart';
import 'package:panes/panes.dart';
import 'package:panes/src/auto_hide_state.dart';
import 'package:panes/src/resize_calculator.dart';

void main() {
  group('AutoHide behavior', () {
    late ResizeContext context;
    late PaneEntry entry;

    setUp(() {
      // Standard context: 800px container, minSize=100px
      context = const ResizeContext(
        containerSize: 800,
        resizerThickness: 8,
        resizerCount: 1,
        totalFlexSum: 1.0,
        totalFixedSize: 200,
      );

      entry = PaneEntry(
        id: 'test',
        initialSize: PaneSize.pixel(200),
        minSize: PaneSize.pixel(100),
        autoHide: true,
        // No explicit autoHideThreshold - should default to 50% of minSize = 50px
      );
    });

    test('threshold defaults to half of minSize', () {
      final threshold = ResizeCalculator.getAutoHideThreshold(entry, context);
      expect(threshold, 50.0); // 100 * 0.5
    });

    test('explicit pixel threshold is used when provided', () {
      final entryWithThreshold = entry.copyWith(
        autoHideThreshold: PaneSize.pixel(30),
      );
      final threshold =
          ResizeCalculator.getAutoHideThreshold(entryWithThreshold, context);
      expect(threshold, 30.0);
    });

    test('fractional threshold is interpreted as fraction of minSize', () {
      // minSize = 100px, threshold = 0.5 fraction
      // Should be 100 * 0.5 = 50px, NOT 0.5 * flexSpace
      final entryWithThreshold = entry.copyWith(
        autoHideThreshold: PaneSize.fraction(0.5),
      );
      final threshold =
          ResizeCalculator.getAutoHideThreshold(entryWithThreshold, context);
      expect(threshold, 50.0); // 100 * 0.5, not flexSpace * 0.5
    });

    test('dragging above minSize updates size normally', () {
      final result = AutoHideBehavior.processResize(
        currentState: const AutoHideVisible(pixelSize: 200),
        requestedSize: 150, // Above min (100)
        entry: entry,
        context: context,
        isVisible: true,
      );

      expect(result, isA<AutoHideResultUpdated>());
      final updated = result as AutoHideResultUpdated;
      expect(updated.newSize, 150);
      expect(updated.newState, isA<AutoHideVisible>());
    });

    test('dragging below minSize but above threshold clamps to minSize', () {
      final result = AutoHideBehavior.processResize(
        currentState: const AutoHideVisible(pixelSize: 200),
        requestedSize: 80, // Below min (100), above threshold (50)
        entry: entry,
        context: context,
        isVisible: true,
      );

      expect(result, isA<AutoHideResultUpdated>());
      final updated = result as AutoHideResultUpdated;
      expect(updated.newSize, 100); // Clamped to minSize
      expect(updated.newState, isA<AutoHideDraggingBelowMin>());

      final state = updated.newState as AutoHideDraggingBelowMin;
      expect(state.displaySize, 100); // Visual stays at min
      expect(state.virtualSize, 80); // Tracks actual drag position
    });

    test('dragging below threshold hides the pane', () {
      final result = AutoHideBehavior.processResize(
        currentState: const AutoHideVisible(pixelSize: 200),
        requestedSize: 40, // Below threshold (50)
        entry: entry,
        context: context,
        isVisible: true,
      );

      expect(result, isA<AutoHideResultHide>());
      final hide = result as AutoHideResultHide;
      expect(hide.newState, isA<AutoHidePendingReveal>());

      final state = hide.newState as AutoHidePendingReveal;
      expect(state.restoreSize, 200); // Remember original size
      expect(state.virtualPosition, 40);
    });

    test('continued dragging below min stays clamped at min', () {
      // First drag below min
      var result = AutoHideBehavior.processResize(
        currentState: const AutoHideVisible(pixelSize: 200),
        requestedSize: 80,
        entry: entry,
        context: context,
        isVisible: true,
      );

      expect(result, isA<AutoHideResultUpdated>());
      var state = (result as AutoHideResultUpdated).newState;

      // Continue dragging to 60 (still above threshold)
      result = AutoHideBehavior.processResize(
        currentState: state,
        requestedSize: 60,
        entry: entry,
        context: context,
        isVisible: true,
      );

      expect(result, isA<AutoHideResultUpdated>());
      final updated = result as AutoHideResultUpdated;
      expect(updated.newSize, 100); // Still clamped to min
      expect((updated.newState as AutoHideDraggingBelowMin).virtualSize, 60);
    });

    test('drag-to-reveal: dragging back by threshold reveals pane', () {
      // Start in pending reveal state (pane was hidden)
      const pendingState = AutoHidePendingReveal(
        restoreSize: 200,
        virtualPosition: 30,
        lowestPoint: 30,
      );

      // Drag back by threshold amount (50px from lowest point)
      final result = AutoHideBehavior.processResize(
        currentState: pendingState,
        requestedSize: 80, // 30 + 50 = 80 (threshold reached)
        entry: entry,
        context: context,
        isVisible: false,
      );

      expect(result, isA<AutoHideResultReveal>());
      final reveal = result as AutoHideResultReveal;
      expect(reveal.revealSize, 100); // Clamped to minSize
    });

    test('drag-to-reveal: small reverse drag does not reveal', () {
      const pendingState = AutoHidePendingReveal(
        restoreSize: 200,
        virtualPosition: 30,
        lowestPoint: 30,
      );

      // Small drag back (only 20px, threshold is 50px)
      final result = AutoHideBehavior.processResize(
        currentState: pendingState,
        requestedSize: 50, // 30 + 20 = 50 (below threshold)
        entry: entry,
        context: context,
        isVisible: false,
      );

      expect(result, isA<AutoHideResultNoChange>());
    });
  });
}
