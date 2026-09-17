# Google Photos bottom bar glass

Enable `GoToHP > Appearance > Google Photos · Liquid Glass` on iOS 26+.
The option defaults to off. Google Photos 7.92.0 is the audited host; later
versions must pass the same runtime contracts and live hierarchy checks.
Exported diagnostics include `bottomBarGlass` with availability, attached-bar
count, visible overlay count and a skip reason.

## Why the native controller must be independent

The visible navigation is a real UIKit `UITabBarController`, not a hand-drawn
capsule and not a standalone `UITabBar`. UIKit therefore owns the floating
Liquid Glass platter, the selected-tab lens, press/hold refraction, layout and the
semantic trailing Search tab.

It is intentionally **not** inserted into Google Photos'
`PHSTabBarController.childViewControllers`. Device validation on iOS 27 beta
showed that Photos treats child controllers as app destinations: inserting a
stock `UITabBarController` caused Google code to send it the private selector
`destination` and terminate with
`-[UITabBarController destination]: unrecognized selector`.

Gunshot instead creates a transparent `UIWindow` attached to the same
`UIWindowScene` and uses the native `UITabBarController` as that window's root.
This gives UIKit a normal full-screen container, which is important because the
previous constrained/standalone experiments produced the compact, too-thin tab
platter. The overlay never becomes a Google child controller and the native
`tabBar.frame` is not manually stretched.

The overlay window only participates in hit-testing over the native tab bar
(with a small touch margin). Everywhere else it returns `nil`, so the underlying
Google Photos window keeps receiving gestures and controls normally. Visibility,
appearance and scene geometry are mirrored from the host window; the overlay is
hidden when the source bottom bar is hidden or the app resigns active.

## Native tab model

The controller uses the modern tab model:

- three `UITab` instances for Photos, Collections and Create;
- one `UISearchTab` as the fourth tab;
- `UITabBarControllerModeTabBar`;
- `UISearchTab.automaticallyActivatesSearch = NO` because Google Photos still
  owns the actual search destination.

`UISearchTab` is used instead of a custom search `UIButton` so UIKit can give the
search affordance its semantic pinned/trailing placement and system Liquid Glass
presentation. Selecting Search is intercepted and forwarded to Google's original
`M3CButton` `TouchUpInside` action. Selecting one of the regular native tabs
writes the corresponding `PHSSegmentedControl.selectedSegmentIndex`.

Google Photos' original `PHSSegmentedControl` and `M3CButton` remain in the
original `UIStackView` as navigation/action backends. While the option is active
they are visually, interactively and accessibility hidden, but their target/action
registrations, gestures and Google-owned subviews are not rewritten. Disabling
the option tears down the overlay window and restores the saved source state.

Some 7.92.0 variants emit `UIControlEventValueChanged` from
`setSelectedSegmentIndex:` and some device validation did not. Tab forwarding
therefore temporarily observes that event around the setter and synthesizes one
only when the host did not emit it. Programmatic Google selection is mirrored
back to `UITabBarController.selectedTab`.

## Compatibility opt-in

The supplied Google Photos 7.92.0 IPA reports:

- `CFBundleShortVersionString = 7.92.0`;
- `CFBundleVersion = 7.92.977090216`;
- `MinimumOSVersion = 18.0`;
- `DTSDKName = iphoneos26.4`;
- `UIDesignRequiresCompatibility = true`.

The compatibility flag suppresses the new system design for the process. When
the option is enabled, Gunshot writes
`com.apple.SwiftUI.IgnoreSolariumOptOut=true` before `UIApplicationMain` on the
next launch so UIKit can render the current Liquid Glass design without modifying
the host Info.plist. Changing the option therefore requires a Google Photos
restart.

Static strings in the supplied 7.92.0 executable also confirm the audited host
surface (`PHSTabBarController`, `floatingBottomTabBar`,
`floatingSegmentedControl`, `floatingSearchButton`, `createFloatingSearchButton`)
and multiple `destination` selectors/methods. The production gate additionally
checks exact Objective-C ABIs for the methods it calls before attaching anything.

## Regression coverage

The UIKit smoke deliberately makes the fake Google segmented control only 44 pt
high while Search remains 56 pt. It verifies that the visible controller lives in
an independent full-screen scene window instead of inheriting that compact
geometry. It also checks:

- Google `childViewControllers` does not change;
- there are three regular `UITab`s plus one `UISearchTab`;
- Search is semantic and does not auto-activate its own search controller;
- the overlay only intercepts touches in the native tab-bar region;
- tab routing fires the Google backend exactly once;
- Search forwards to the original button;
- programmatic Google selection synchronizes the native selected tab;
- hiding the Google bar hides the overlay;
- disabling restores the original controls and removes the overlay root.

The simulator smoke is not a substitute for injected-device validation. Device
validation should cover launch, all four controls, selected/unselected press and
hold, light/dark appearance, rotation, background/foreground transitions and
presented full-screen flows.

Apple API references:
- https://developer.apple.com/videos/play/wwdc2025/284/
- https://developer.apple.com/videos/play/wwdc2024/10147/
- https://developer.apple.com/documentation/uikit/uitabbarcontroller
- https://developer.apple.com/documentation/uikit/uitab
- https://developer.apple.com/documentation/uikit/uisearchtab
