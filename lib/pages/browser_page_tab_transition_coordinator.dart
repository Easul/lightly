import 'browser_page_tab_flow_coordinator.dart';
import 'browser_page_tab_transition_helper.dart';

class BrowserPageTabTransitionCoordinator {
  const BrowserPageTabTransitionCoordinator({
    BrowserPageTabTransitionHelper transitionHelper =
        const BrowserPageTabTransitionHelper(),
    BrowserPageTabFlowCoordinator flowCoordinator =
        const BrowserPageTabFlowCoordinator(),
  }) : _transitionHelper = transitionHelper,
       _flowCoordinator = flowCoordinator;

  final BrowserPageTabTransitionHelper _transitionHelper;
  final BrowserPageTabFlowCoordinator _flowCoordinator;

  Future<void> prepareOpenedTab({
    required BrowserPageTabTransitionDeps deps,
    required void Function() resetVideoDetectionState,
    required String url,
    required void Function() applyStatusAfterTransition,
    required void Function() syncTrackedScrollPosition,
  }) {
    return _transitionHelper.prepareOpenedOrSwitchedTab(
      deps: deps,
      resetVideoDetectionState: resetVideoDetectionState,
      url: url,
      applyStatusAfterTransition: applyStatusAfterTransition,
      syncTrackedScrollPosition: syncTrackedScrollPosition,
      syncTrackedScroll: false,
    );
  }

  Future<void> prepareSwitchedTab({
    required BrowserPageTabTransitionDeps deps,
    required void Function() resetVideoDetectionState,
    required String url,
    required void Function() applyStatusAfterTransition,
    required void Function() syncTrackedScrollPosition,
  }) {
    return _transitionHelper.prepareOpenedOrSwitchedTab(
      deps: deps,
      resetVideoDetectionState: resetVideoDetectionState,
      url: url,
      applyStatusAfterTransition: applyStatusAfterTransition,
      syncTrackedScrollPosition: syncTrackedScrollPosition,
      syncTrackedScroll: true,
    );
  }

  Future<void> prepareClosedTab({
    required BrowserPageTabTransitionDeps deps,
    required String url,
    required void Function() applyStatusAfterTransition,
  }) {
    return _transitionHelper.prepareClosedTab(
      deps: deps,
      url: url,
      applyStatusAfterTransition: applyStatusAfterTransition,
    );
  }

  Future<void> prepareCloseAllTabs({
    required BrowserPageTabTransitionDeps deps,
    required String url,
    required void Function() applyStatusAfterTransition,
  }) {
    return _transitionHelper.prepareCloseAllTabs(
      deps: deps,
      url: url,
      applyStatusAfterTransition: applyStatusAfterTransition,
    );
  }

  BrowserPageCloseTabDecision decideCloseTabFollowUp({
    required String previousActiveId,
    required String nextTabId,
  }) {
    return _flowCoordinator.decideCloseTabFollowUp(
      previousActiveId: previousActiveId,
      nextTabId: nextTabId,
    );
  }
}
