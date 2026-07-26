# Lightly UI Design Guidelines

[中文](ui-design.md)

## Goals

Lightly combines a browser, network connectivity, local services, and remote-control tools in one application. The UI should therefore:

- keep information clear without adding decorative hierarchy
- remain compact while preserving comfortable touch targets and vertical space
- use one shared theme instead of feature-specific color systems
- make dangerous actions recognizable without large saturated red surfaces
- keep standard dialogs, bottom sheets, and settings lists visually consistent

## Sources of Truth

- Global theme and colors: `lib/theme/app_theme.dart`
- Shared settings row: `lib/widgets/shared/setting_tile.dart`
- Settings group container: `lib/browser/widgets/settings/settings_section_widgets.dart`
- Browser More grid: `lib/browser/widgets/browser_more_actions_sheet.dart`
- Long-press action lists: `lib/browser/widgets/browser_long_press_actions_sheet.dart`
- Custom disconnect dialog: `lib/features/remote_control/presentation/widgets/remote_control_disconnect_dialog.dart`

New screens should reuse these components and `Theme.of(context).colorScheme`. Do not redefine nearly identical colors, radii, or shadows inside individual pages.

## Color System

Core tokens in the current light theme:

| Purpose | Color | Usage |
| --- | --- | --- |
| Primary | `#6D9F5B` | Active states, primary buttons, important icons |
| Primary container | `#E4EFE0` | Selected backgrounds and subtle emphasis |
| Page background | `#F3F5F2` | Scaffolds and spacing between groups |
| Content surface | `#FFFFFF` | Cards, bottom sheets, and dialogs |
| Primary text | `#3F4742` | Titles and important information without pure black |
| Secondary text | `#7B837E` | Descriptions, default menu icons, supporting text |
| Divider | `#E8ECE7` | Lightweight boundaries |
| Danger | `#B66C6C` | Delete, exit, disconnect, and error states |
| Danger container | `#F7ECEC` | Warning and error backgrounds |

Rules:

- Do not use red, orange, or pure black to emphasize normal features.
- Use the primary green for active states instead of inventing feature colors.
- Use `colorScheme.error` and `errorContainer` rather than `Colors.red`.
- Dark backgrounds remain appropriate for video, remote-screen, and player-control surfaces.

## Sizing and Shape

- Typical page side padding is `12` or `16`.
- Content cards use an `18` radius.
- Inputs and primary buttons use a `14` radius.
- Standard dialogs use a `22` radius; bottom sheets use a `24` top radius.
- Primary buttons default to `48` logical pixels high.
- Global `ListTileTheme` owns the minimum settings-row height.
- Shadows are reserved for floating surfaces; normal cards use no shadow or a very subtle one.

## Modal Patterns

### Short Actions: Grid Sheet

Use for short labels, a limited number of actions, and icons that can be recognized quickly.

- Use five columns at widths of at least `380`, otherwise four.
- Keep icons around `23` and labels around `11.5`.
- Default items use the secondary text color, active items use the primary color, and dangerous items use the muted danger color.
- Preserve comfortable vertical spacing without icon background tiles or trailing arrows.
- Close the sheet before invoking navigation or the selected action.

Reference: `BrowserMoreActionsSheet`.

### Long Actions: Text List Sheet

Use for longer labels, URL previews, or actions that need to be read line by line.

- Use vertical `ListTile` rows with left-aligned titles.
- Avoid large leading icons by default; use a subtle trailing chevron only when it communicates navigation.
- Separate groups with space or a light surface block rather than heavy dividers.
- Supporting text and URL previews use secondary text colors and limited line counts.

References: favorites menu, page long-press menus, and calculator copy menu.

### Confirmation and Input Dialogs

- Prefer the global `AlertDialog` theme.
- Keep titles short, explain the result or risk, and use no more than three actions.
- Use text buttons for cancellation and the primary style for the main action.
- Delete, exit, and disconnect actions may use the danger color, but not a large saturated red background.
- Use an `isScrollControlled` bottom sheet for keyboard-sensitive or longer input flows.

## Lists and Settings

- Split the settings home into independent white blocks by feature domain, such as browsing, network/local services, and remote control.
- Rows contain a title, one-line description, and trailing chevron.
- Do not wrap every row in its own outlined card or large colored icon container.
- Detailed settings screens may use `SettingsCard` to group fields, switches, and status text.
- Use lightweight dividers inside a group and roughly `12` pixels of page-background spacing between groups.

## States and Dangerous Actions

- Normal, enabled, connected: primary green.
- Disabled, secondary, unavailable: secondary text or outline color.
- Error, stop, delete, exit: muted danger color.
- Never rely on color alone; retain text, icons, or disabled states.
- Remote-control, proxy, and EasyTier error messages may be long and must be allowed to wrap.

## Performance Boundaries

- Do not trigger parent-page `setState()` calls from high-frequency WebView callbacks for visual effects.
- Keep bottom-sheet list geometry stable and avoid unnecessary `shrinkWrap` during animations.
- Do not add blur, shadow animation, or frequently recomputed gradients to browser, video, or remote-screen hot paths.
- Theme work must not alter WebView keep-alive behavior, proxy connections, remote-control sockets, or service lifecycles.

## New UI Checklist

- [ ] Colors come from `AppTheme` / `ColorScheme`; no duplicate hard-coded theme colors were added.
- [ ] Titles, body text, and supporting text have clear hierarchy without large pure-black surfaces.
- [ ] Short actions use a compact layout; longer labels use a vertical list.
- [ ] Settings are grouped by domain instead of stacking independent large cards.
- [ ] Danger colors are reserved for genuinely dangerous operations.
- [ ] Narrow screens, keyboard display, and larger system font sizes do not overflow.
- [ ] UI work does not change performance-sensitive WebView, proxy, video, or remote-control behavior.

## Validation

```bash
flutter analyze
flutter test
```

For browser dialogs or settings changes, manually verify at least:

1. More-grid column count and truncation on a roughly 360dp screen and a wider device.
2. Link long-press, favorites, browsing-data, and input dialogs.
3. Settings groups, detailed settings pages, and disabled switch states.
4. Video, remote-screen, and keyboard surfaces retain the required readability and immersion.
