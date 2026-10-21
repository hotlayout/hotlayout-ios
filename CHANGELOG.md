# Changelog

## Unreleased

- **Top of the screen.** The body is cut at the edge of its area (the bottom edge of the status-bar
  inset without an app bar), so a scrolled body no longer shows under the clock. The scrolled look
  of the app bar (`styleScrolled`, `titleShown: 'scrolled'`) follows the scroll offset of the
  scroll view itself: the geometry preference it used did not fire while the content was only
  scrolled, so the look never switched on.
- **Modal window.** A window is centred in the area between the top inset and the home indicator,
  as the shared table says. The shadow and the border of the layer's root are drawn.
- **Loaders as members.** `HotlayoutDocument.load(_:)`, `HotlayoutThemeSet.load(_:)`,
  `HotlayoutVersions.check(_:readerVersion:)`, `HotlayoutVersions.checkDocument(_:)` and
  `LocaleResolution.resolve(_:available:source:)` replace the global functions `loadDocument`,
  `loadTheme`, `checkVersion`, `checkDocumentVersion` and `resolveLocale`, which stay as deprecated
  forwards.
- **README.** The example reads the document and the theme once, in `.task`, and shows the load
  error, instead of parsing on every evaluation of `body`.
- **Values for words.** `ScreenEntry.placement`, `ScreenEntry.statusBar`,
  `ScreenShownEvent.placement`, `ScreenShownEvent.statusBar` and `HotlayoutTheme.appearance` give
  `modalPlacement`, `statusBarIcons` and `brightness` as enums (`ModalPlacement`, `StatusBarIcons`,
  `ThemeBrightness`). `ScreenShownEvent.modalPlacement` and `.statusBarIcons` are deprecated.
- **Documentation.** One-line comments on the public declarations of the model, the JSON value and
  the actions; the reason for the own JSON parser is stated; the module `HotLayout` and the types
  `Hotlayout…` are named alike on purpose.
- **Internal.** Widgets and actions are dispatched on enums instead of string literals; the token
  name, whole number and absent value rules have one home; the icon file is parsed once; the
  shared caches sit behind one lock type; the theme colour, gradient and role types are immutable.
  The whole-string match is now used by the text-span rules as well, so a token name or a colour
  with a trailing line feed is not read.
- **Demo.** The showcase reads its document once per app and language instead of on every
  evaluation of `body`.
- **Border and rim.** The content of a rounded node is clipped by the inner edge of its border
  (the outer radius less the border width), so the background shows round the corners as it does
  along the straight edges, as in the other readers.
- **Glass.** The blur follows the theme with the system blur that changes the colour under it
  least (dark on a dark theme), and the radius maps onto a smaller share of the effect (the whole
  at 40 points, as the contract's largest radius), so a glass card keeps nearly the colour of the
  node's background over the page instead of a greyer one. A slight grey cast remains on the
  system blur, more at larger radii.
- **Pictures.** A picture that failed to load is asked for again after a minute, and at once when
  the app becomes active; before, it stayed the placeholder until the app restarted. Decoded
  pictures are kept by address and decoded size, so a screen with a larger `maxPixelSide` no longer
  gets a picture another screen decoded smaller.
- **Presses and timers.** A second press during the return of the first keeps the control pressed;
  a sheet dragged away and replaced before it had left no longer closes the layer that took its
  place. The busy state of a swipe-to-confirm button and the motion of a navigation dot end with
  their view.
- **Reports.** Every report reaches the newest `onReport` the host passed, once.
- **Inside.** No state changes while SwiftUI evaluates a body (reports, number transitions, text
  fields); the safe area is reached over with `ignoresSafeArea` instead of a frame and an offset;
  the modal stack is generic instead of wrapping screens in `AnyView`; the render context is
  grouped. What is drawn is unchanged.

## 0.2.0

Reads document contract **9.28.0** (theme 4.0.1, icon set 1.0.0). The contract added no field; it
fixed what a reader does at five edges, and the same shared case tables now run here.

- **Pictures.** The default rule is exactly the address form of `openUrl`; a host's own `resolve`
  answer is final, except that `javascript:` and `vbscript:` (read as a URL parser reads them) are
  never a picture. A refused address draws the placeholder, makes no request and is reported: the
  document's address cut at 120 characters, an address from data by scheme and host only. A
  picture that fails to load is reported too. At most three redirects are followed (each one put
  to the host's rule), no `Referer` is sent, one picture has 30 seconds in all, and a larger
  picture is decoded smaller (its longer side at most 4096, the proportion kept) instead of being
  refused.
- **Breaking:** `ImagePolicy.maxPixels` and `defaultMaxPixels` (a count of pixels) are replaced by
  `maxPixelSide` and `defaultMaxPixelSide` (the longer side, 4096).
- **Lists.** A screen draws at most 2550 instances of list templates, counted in document order
  over the tree of its width class (a hidden list costs the same). The instance that would pass
  the budget is not drawn, nor anything after it; one report per screen says how many were left out.
- **Theme.** A number outside the bounds of the theme schema (or not finite) is replaced by the
  value of the same token and field of the built-in theme of the same brightness, otherwise by the
  nearest bound (a part of a shadow or a gradient always takes the bound), and reported. Before,
  such a token was dropped, and an infinite or enormous spacing could reach the layout.
- **Names.** A text that paints nothing (opacity 0 on it or on a node between the card and it, or
  a colour with opacity 0) is no longer part of the accessible name of a pressable card.
- **Modal layers.** A layer that cannot be dismissed keeps the modal semantics of the platform and
  adds no focus trap of its own.
- **Reports** that arise after the first frame (a refused address on new data, a picture that
  failed) now reach `onReport`; before, only the reports of the frame in which a press, an update
  or the first appearance happened were handed over.

- **Countdowns.** A host that gives `now` owns the clock: nothing ticks, as in the web reader. Without
  `now` the countdown still runs from the device clock.
- **Stacks.** A picture, or a container that holds one and names no width, takes the whole width of its
  stack instead of collapsing to nothing.
- **Top zone.** The second and later nodes of the top zone are pulled by their `pull`, as the case table
  says (only the first one pulls nothing).
- **Text.** The line box is `lineHeight` × size for the font the theme names: the extra leading is counted
  from that font's natural line, not from the system font's.
- **Glass.** The blur material follows the brightness of the theme, not of the device.
- **Buttons.** A button with a named height fills it; the shadow of a button, an icon button or a badge is
  no longer cut by its box.

## 0.1.0

The first public release. Reads document contract **9.27.0** (theme 4.0.1, icon set 1.0.0).

- `HotlayoutScreen` draws all 28 widgets of the contract with SwiftUI on iOS 16 and later: the
  screen stack the reader navigates itself (`navigate`, `navigate.back`, `navigate.section`),
  modal sheets and windows with the blur under them, the fixed app bar and bottom zone with only
  the body scrolling, width classes, forms, lists from data with the live record of a page.
- The host decides: `onAction` (plain or `async`; a swipe-to-confirm button waits for an `async`
  handler), `onTrack`, `onHaptic` (`HapticFeedback`), `onNavigate` (may cancel a change of
  screen), `onWrite` with `writablePaths`, `onScreenChange`, `onReport`, `ImagePolicy`, and
  `ScreenLabels` for the texts of the reader itself.
- `loadDocument` and `loadTheme` read from `Data` or `JSONValue` and throw `HotlayoutLoadError`;
  `checkDocumentVersion` and `resolveLocale` work without a view.
- Documents, themes and data are untrusted input: a piece of the wrong shape is skipped and
  reported, never a crash; pictures load only from public `https:` host names by default, within
  a size limit, without the cookies of the app. See `docs/security.md`.
