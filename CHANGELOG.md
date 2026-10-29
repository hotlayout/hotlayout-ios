# Changelog

## 0.7.2 - Unreleased

- **Placement schedule (placement contract 1.1.0).** A place may carry promotions with a `from`
  and an `until` (UTC, `until` excluded) that replace its permanent content for their window; an
  item without a document is a pause and the place is empty. The reader resolves the schedule by
  the device clock, sets a timer for the next edge, and resolves again when the app returns to
  the foreground; the map is not asked again on an edge. New: `HotlayoutPlacementMap.resolve(_:at:)`
  and `nextBoundary(_:after:)`, and a `clock:` parameter on `HotlayoutPlacement.load` and
  `HotlayoutPlacementView`. A broken item is skipped whole and spoils nothing else.

- **A carousel with `stopPath` stays on the stop a person swiped to.** From the second swipe on, the
  row went back to the stop before about half a second after it settled. The change of the value
  was handed to the carousel from the draw before the change, so each write was followed as a change
  of the previous value; the carousel now takes the new value the change carries.
- **A node that fades out leaves the layout when its fade ends.** It could stay for good, nearly
  transparent and holding its place, when the last frame of its timeline was not drawn; each
  boundary of a phase now draws the node again on a timer of its own.
- **A node that fades and is out of the layout takes no gap.** A hidden row of a list whose template
  fades, and a hidden child of a column, left an empty space of one gap: they were drawn as an empty
  view, which the column counted. Out of the layout they now draw no view at all.
- The demo's contract samples carry `account.cardIndex` (dictionary 1.8.0), so the carousel fixtures
  open with the content of their first card.
- **A carousel that follows its stop value no longer stops short when the value changes twice in
  a row.** While the reader was still scrolling smoothly to the first target, a second value was
  compared with the stop the scroll was passing and taken for "already there". The follow now
  starts from the target of the reader's own last scroll until that scroll settles, or until a
  person moves the row.
- **A node of a list template that fades does so apart from the other rows.** An instance whose
  condition stops holding stays in the list while it fades out (it used to leave at once), and the
  rows of a list are keyed by their record, so a row that leaves does not hand its state to the next.

## 0.7.1 - Unreleased

- **Fading nodes in a stack and in a grid.** A layer of a `Stack` and a cell of a `Grid` (or of a list
  with `columns`) that names `visibilityTransition: 'fade'` fades like a child of a column: a grid no
  longer drops it from its cells the moment its condition stops holding, and while it is out of the
  layout the cell takes no place, so the other cells close up without a hole. The layer that gives
  a stack its size is still counted by the document.

## 0.7.0 - Unreleased

Reads document contract **9.33.0** (theme 4.0.1, icon set 1.0.0).

- **A node fades in and out when its condition changes.** A node with `visibilityTransition: 'fade'`
  and a `visibleIf` no longer appears and disappears at once. When the condition stops holding on
  a shown screen, the node keeps its place and fades out for 120 ms, then leaves the layout. When it
  starts to hold, the node waits 120 ms out of the layout, then enters it transparent and fades in
  for 160 ms, so two neighbours with opposite conditions are never in the layout together and the
  layout changes once. A change during a transition goes to the new goal from the current opacity,
  the time scaled by the distance; a node still waiting stays hidden. The times and the curves come
  from the contract. A node that fades out catches no press and is not heard by VoiceOver from the
  first moment; one that fades in is a control from the moment it enters the layout.
  Nothing fades on the first show of a screen, when the language or the width class changes, or
  under Reduce Motion: the node goes to its new state at once. The app
  bar of the screen, a pinned node (`pin` of any value), a navigation bar and its items follow
  their condition at once, and so do the tabs and the parts of a composed text. Every row of the shared tables runs in the tests.

## 0.6.0 - Unreleased

Reads document contract **9.32.0** (theme 4.0.1, icon set 1.0.0).

- **A carousel tells its active stop.** A carousel (a scrolling `Row` or a `Repeater` in a row) may
  name a number data path in `carousel.stopPath`. When a person swipes it and the scroll settles on
  a stop, the reader writes the number of that stop, counted from 0 (stops, not cards), the way an
  input field writes: into the session of the screen and to the host at the same moment, under
  `writablePaths`; `onAction` is not called. Nothing is written during the gesture, for a move the
  reader made itself (the show, following the value), or for the number the path already holds.
  When the carousel is shown it stands on the stop the value names, without animation (a number
  past the last stop is the last one, anything that is not a whole number is the first); when the
  number the value names changes, it scrolls there (not while a finger holds the row, without
  animation under Reduce Motion). A write the host refused leaves the carousel where the person
  put it. A path of a wrong shape counts as no path. The scroll counts as settled after a quiet
  time of 150 ms. A gesture the system cancels counts as a finger lifted. Every row of the shared table runs in the tests.

## 0.5.0 - Unreleased

Reads document contract **9.31.0** (theme 4.0.1, icon set 1.0.0).

- **Bottom safe inset of a modal sheet.** A sheet reaches the physical bottom of the area, and the
  home indicator no longer covers its last node: the reader adds the bottom safe inset of the
  window inside the box of the sheet, under its content. The background and the radius of the
  sheet extend under the inset; the sheet is as tall as its content plus the inset, no taller than
  the area, and a taller body scrolls above the inset. The inset is added once: with a shown
  pinned block it lies under the content of that zone, otherwise under the content of the root.
  A window in the centre and a sheet shown as a window in a wide place get none, and a host that
  accounted for the inset itself and gives zero gets zero. A value that is not a number, not
  finite or negative counts as zero. Every row of the shared table runs in the tests.
- **Write on a long press.** A long press may carry `setValue` or `toggleValue`, as long as the
  press of the node does not write. It runs like the action of a node that writes: the same
  session and `onWrite` under `writablePaths`, the same "a value already held is not written
  again", and the haptic request and the analytics event go before the write. The keyboard
  (Shift+F10) and the named action of a screen reader do the same. Only `action` gives a node its
  role, so such a node stays a plain button, not an option or a switch. Before, a write action on
  a long press was ignored.
- **Node `name`.** The optional name a node carries for the editor's tree is not drawn, not part
  of any accessible name, and not passed to actions, events or reports; a document with it draws
  exactly as without it.

## 0.3.0 - 2026-10-26

Placements:

- **Named places of the app.** `HotlayoutPlacement.load(name:projectBase:)` reads the placement map
  of the project (`placements/published.json`, with its `ETag`), finds the document placed under
  the name and returns it with its entry point, the status of the map and a report of why nothing
  is drawn (`empty`, `unknown`, `unreadable`, `documentMissing`, `documentUnreadable`,
  `entryMissing`). `HotlayoutPlacementView` draws it with a `HotlayoutScreen`, and nothing for a
  place that has no document. The map is read tolerantly (an unknown field is skipped, a broken
  record spoils only its own place, a key is looked up among the map's own keys, a `documentId` must
  have the form of a path segment before it is put into an address). The last known map and
  documents are kept (`UserDefaults` by default) and a copy bundled with the app is the last
  fallback; "the network is silent", "the map is broken" and "the project published no map" are
  different statuses. Every row of the shared placement table runs in the tests.

Reading rules, the same in every reader:

- The map body is read up to 262 144 bytes as strict UTF-8, with one leading byte order mark skipped;
  anything else, or nesting deeper than 32 levels, is `corrupt` for the whole map. The major version
  is compared as a string of digits, so a very long major is `unsupported` and never wraps around.
- Redirects are not followed (even within the same host): a 3xx answer is "the network is silent"
  for the map (`offline`) and `documentUnreadable` for a document. A request has a 20-second limit
  from its start to the end of its body.
- `onPlacement` is called with the first settled state of a place and then on every change of
  `placement.event` (`status`, `report`, `mapStatus`, `documentId`, `entry`), including the return
  to a shown document. A new `name` or `projectBase` drops the old place at once, and a load that
  was replaced or cancelled never writes the view.
- The last known map is kept under the address of the map. Documents are kept in files in the
  caches directory (`HotlayoutFilePlacementDocumentStore`; `documents:` on `load` and the view
  chooses another), under the address of the document: one for each place of the current map,
  the others removed once a fresh map is read, and a 404 removes its document.

Fixes:

Drawing:

- **Navigation bar under the keyboard.** With the on-screen keyboard up, the navigation bar (fixed or
  floating) stayed directly above it, because the system shrank the screen for the keyboard before the
  reader's own rules ran. The screen now keeps its size, so the bar stays under the keyboard and only the
  pinned block rides above it, as the contract says.
- **Focused field above the keyboard.** The field with the keyboard, together with the helper or
  counter under it, is scrolled into the body area once the keyboard has shrunk the area (before,
  the scroll ran on focus, ahead of the keyboard, and the field could stay under it). A field that
  is already in view does not move. A person who scrolls the body while the reveal is repeating
  keeps the position they chose.
- **Modal layer and the keyboard.** A sheet or window lifts above the on-screen keyboard as a whole,
  so a field in it is no longer covered by the keyboard (a tall sheet scrolls to the field, a short
  one moves up).
- **Glass over a light picture.** The material of the glass now follows the brightness of what
  lies around it on the screen, not the theme: glass over a light gradient on a dark theme (the
  round buttons and the tile of a reward hero) is light and keeps the colour under it, where the
  dark blur turned it a muddy grey. Until the screen has been read the theme decides, as before.
- **Glass under a nearly opaque background.** The share of the blur spent grows with the opacity
  of the node's own background colour, which hides the tint of the system blur: a scrolled app bar
  or a navigation bar with a dense background now blurs what passes under it as fully as the other
  readers, while a faint glass card keeps its colour.

## 0.2.1

Drawing:

- **Top of the screen.** The body is cut at the edge of its area (the bottom edge of the status-bar
  inset without an app bar), so a scrolled body no longer shows under the clock. The scrolled look
  of the app bar (`styleScrolled`, `titleShown: 'scrolled'`) follows the scroll offset of the
  scroll view itself: the geometry preference it used did not fire while the content was only
  scrolled, so the look never switched on.
- **Modal window.** A window is centred in the area between the top inset and the home indicator,
  as the shared table says. The shadow and the border of the layer's root are drawn.
- **Border and rim.** The content of a rounded node is clipped by the inner edge of its border
  (the outer radius less the border width), so the background shows round the corners as it does
  along the straight edges, as in the other readers.
- **Glass.** The blur follows the theme with the system blur that changes the colour under it
  least (dark on a dark theme), and the radius maps onto a smaller share of the effect (the whole
  at 40 points, as the contract's largest radius), so a glass card keeps nearly the colour of the
  node's background over the page instead of a greyer one. A slight grey cast remains on the
  system blur, more at larger radii.

Behaviour:

- **Carousel flick.** A fast flick moves the carousel one stop in the direction of the throw (clamped
  to the first and last stop), as in the other readers; before, the stop nearest to where the
  momentum would land was taken, so a flick could skip a card. A slower release still settles on
  the nearest stop. The flick threshold is Flutter's, `1 / (0.05 * pixel ratio)` points per second.
- **Sheet drag.** A drag down on a sheet whose body is scrolled scrolls the body back first and
  moves the sheet only once the body is at its top (`x-sheetDismiss`): the sheet now hears the
  offset from the scroll view of the body, the same reading as the scrolled look of the app bar.
  Before, it never learned that the body was scrolled.
- **Text fields.** A field the platform focused (a tap) is no longer resigned by an update drawn
  before the screen heard of the focus; such an update committed an open composition and wrote
  each composed character.
- **Pictures.** A picture that failed to load is asked for again after a minute, and at once when
  the app becomes active; before, it stayed the placeholder until the app restarted. Decoded
  pictures are kept by address and decoded size, so a screen with a larger `maxPixelSide` no longer
  gets a picture another screen decoded smaller.
- **Presses and timers.** A second press during the return of the first keeps the control pressed;
  a sheet dragged away and replaced before it had left no longer closes the layer that took its
  place. The busy state of a swipe-to-confirm button and the motion of a navigation dot end with
  their view.
- **Host callbacks.** Every report reaches the newest `onReport` the host passed, once, and every
  screen-shown event after the first reaches the newest `onScreenChange` (a show that followed a
  new document or entry went to the handler from before the update).

API:

- **Loaders as members.** `HotlayoutDocument.load(_:)`, `HotlayoutThemeSet.load(_:)`,
  `HotlayoutVersions.check(_:readerVersion:)`, `HotlayoutVersions.checkDocument(_:)` and
  `LocaleResolution.resolve(_:available:source:)` replace the global functions `loadDocument`,
  `loadTheme`, `checkVersion`, `checkDocumentVersion` and `resolveLocale`, which stay as deprecated
  forwards.
- **Values for words.** `ScreenEntry.placement`, `ScreenEntry.statusBar`,
  `ScreenShownEvent.placement`, `ScreenShownEvent.statusBar` and `HotlayoutTheme.appearance` give
  `modalPlacement`, `statusBarIcons` and `brightness` as enums (`ModalPlacement`, `StatusBarIcons`,
  `ThemeBrightness`). The string properties `modalPlacement` and `statusBarIcons` of `ScreenEntry`
  and `ScreenShownEvent`, and `HotlayoutTheme.brightness`, are deprecated.
- **Documentation.** One-line comments on the public declarations of the model, the JSON value and
  the actions; the reason for the own JSON parser is stated; the module `HotLayout` and the types
  `Hotlayout…` are named alike on purpose. The README example reads the document and the theme
  once, in `.task`, and shows the load error, instead of parsing on every evaluation of `body`.

Inside (what is drawn is unchanged, but for one edge: the text-span rules now match the whole
string too, so a token name or a colour with a trailing line feed in a span style is not read):

- No state changes while SwiftUI evaluates a body (reports, number transitions, text fields); the
  safe area is reached over with `ignoresSafeArea` instead of a frame and an offset; the modal
  stack is generic instead of wrapping screens in `AnyView`; the render context is grouped.
- Widgets and actions are dispatched on enums instead of string literals; the token name, whole
  number and absent value rules have one home; the icon file is parsed once; the shared caches sit
  behind one lock type; the theme colour, gradient and role types are immutable.

Demo:

- The showcase reads its document once per app and language instead of on every evaluation of
  `body`.
- `-clock running` (with `-contractSamples`) runs the host's clock from the samples' moment, so a
  countdown goes down; with the fixed moment of the samples alone it stands, as the host owns the
  clock.

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
