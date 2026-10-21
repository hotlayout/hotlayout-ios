# Platform notes

Where Apple's platform differs from the other readers of the contract, and what this reader does.

## Locale data

Apple's CLDR data writes some dates differently from the shared tables. The rows marked
`mayDiffer` that this reader shows differently are listed by name in the template tests:

- U+202F before `PM` and before the year marks `р.`, `г.`, `ж.` (uk, ru, kk, `dateTime` in English);
- Arabic: `،` between the month and the year (`15 أكتوبر، 2026`) and U+00A0 before `م`;
- Japanese date parts: a space before the weekday (`10月15日 木曜日`); the order of the parts is
  the same as in the table.

The tables name `tlh`, `dv` and `la` as languages without data. Apple has data for `dv`, so that
row is checked only for non-empty text.

## Done by hand

- **Grouping always** (`x-template.number.grouping`): Foundation follows CLDR minimum grouping and
  writes `1850` in Spanish; the reader groups the integer digits itself with the separator and group
  sizes of the locale (Indian grouping included).
- **Plural categories**: Foundation has no public API; the CLDR cardinal rules are carried in
  `PluralRules.swift`. A language outside the table gives `other`.
- **The date-time joiner**: Apple's templates join with «at» in English; the reader takes the CLDR
  medium joiner (`{1}, {0}` and its exceptions).
- **Regular expressions**: ICU `$` accepts a final line feed; every contract expression is matched
  against the whole string.
- **Numbers shown as is** (no format) are written the way JavaScript's `String(number)` writes them.
- **`number` of a negative value that rounds to zero** (`-0.0001`) is written `0`.
- **String equality**: Swift compares strings by canonical equivalence, so a path or key written
  with a decomposed `é` matches a precomposed one.
- **Lengths** in the contract (2048, 32, 40…) are counted in UTF-16 code units.

## Drawing

- **Shadows**: CSS `spread` grows the shape of the layer by that much on every side (a square corner stays square, a round one grows by the spread), drawn by `ShadowPaint`.
- **Line pitch**: a paragraph with parts of other sizes takes its pitch from the strut through
  `lineSpacing`; SwiftUI `Text` cannot force one pitch on every line, so a line without the tallest
  part can be shorter than the table's pitch.
- **Gradient on glyphs** (`style.textGradient`): the paragraph is drawn through a mask, with the
  parts of their own colour drawn over it.
- **Fonts**: the theme names families such as `Inter`; the package ships no fonts. A device without
  the family uses the system font (the family's own fallback list ends with `system-ui`).
- **Right to left**: SwiftUI mirrors a custom `Layout` and an `offset` in right-to-left text on iOS
  and macOS, but mirrors a `Shape` on macOS only. Layers and motion are placed in logical
  coordinates; the dashed border fixes its own direction.
- **Carousel snapping** to the stops needs iOS 17 (`ScrollTargetBehavior`); on iOS 16 the scroll is
  free and the dots still follow it.
- **Glass** (`style.backdropBlur`) blurs what lies under the box with the system blur view, clipped
  by the radius of the node, with the node's background over it. UIKit gives the strength of that
  blur only as a fraction of its effect, so the radius is mapped onto the opacity of the blur view
  (the whole effect at 40 points). The system blur also lifts and greys the colour under it, and
  that cannot be switched off: the reader uses the dark blur on a dark theme (the one that moves
  the colour least) and the ultra thin material on a light one, and spends only a share of the
  effect, which weakens the tint with the blur. On the Orbit home screen a Stardust card is within
  a few colour levels of the other readers, a little greyer; a larger radius is greyer still. The
  area and the order are the contract's; the exact Gaussian sigma and the exact colour are not.
  On macOS a material stands in.
- **Blur under a modal layer**: the blurs of several layers are applied to each picture below once,
  not to the composite.

## Screen and input

- **Safe areas**: the insets are read from a view that respects the safe area, and the screen
  reaches over them. Left and right insets are not read. A bar of navigation at the top in a bar of
  its own holds the top inset inside its box (the screen is drawn edge to edge on iOS).
- **The width class** is the width of the box `HotlayoutScreen` is given. SwiftUI hands the size
  over in the same layout pass, so there is no first frame in a wrong class.
- **Text fields** use a native control (`UITextField`, `UITextView`) on iOS, because SwiftUI's
  `TextField` does not say whether text is still being composed (IME): nothing is written while
  composing, and the committed text is written once. macOS keeps a SwiftUI `TextField` as a
  stand-in.
- **The keyboard**: the bar of navigation stays under the keyboard; the pinned block rides above it.
- **A layer that cannot be dismissed** (`dismissible: false`) keeps the modal trait of the platform
  (what lies under it is out of reach of VoiceOver) and the reader adds no focus trap of its own;
  the system gives a hardware keyboard no way out of a modal layer other than the host's.
- **Escape**: the escape gesture of assistive technology closes a modal layer that may be closed. A
  hardware Escape key is not read. Shift+F10 and the context menu key perform a long press on the
  focused node on iOS 17 and later.
- **Haptic feedback** goes to `onHaptic`; the reader never vibrates.

## Pictures

- A picture is fetched by the package itself (a private session, three redirects at most, 30
  seconds in all) and decoded through ImageIO from its header, so a larger picture is made smaller
  before any pixel is made.
- Pictures are cached in memory (64 MB, 200 pictures) and a load in flight is shared; an address
  that failed is not asked for again while the process lives. There is no disk cache.
