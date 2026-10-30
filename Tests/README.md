# Tests

The same unit tests run on macOS (`swift test`) and on an iOS simulator, which is the platform the
library ships for: `xcrun simctl boot <device-id>`, then
`xcodebuild test -scheme HotLayout -destination 'platform=iOS Simulator,id=<device-id>'`. The
off-screen layout tests draw the screen through the platform's hosting view on each (`AdaptiveRender.draw`).

## Shared case tables

`swift test` runs these groups of `contract/fixtures/*/*-cases.json` (all rows pass, or a row
is listed by name where Apple's CLDR data writes other characters than the table):

- `template`: `cases`, `moneyCases`, `datePartsCases`, `countdownCases`, `compactCases`,
  `shownTextCases`, `shownTemplateCases`
- `locale`: `cases`
- `actions`: `formCases`, `handedCases`, `flowCases`
- `scope`: `readCases`, `recordCases`, `flowCases`
- `rich-text`: `cases`, `struts`, `emphasis`, `emphasisStruts`, `amountPartCases`, `amountPartStruts`, `textGradientCases`, `textGradientPartCases`; `list-marker`: all six groups
- `icon-text`: `orderCases`, `glyphCases`, `buttonSizeCases`, `iconButtonCases`, `nameCases`, `colorCases`, `iconPathCases`
- `list-tile`: `lineCases`, `tileCases`, `leadingBoxCases`, `trailingColumnCases`, `rowCases`, `lookCases`, `leadingColorCases`
- `adaptive`: every group but the validator's (`wideSectionCases`, `olderReaderShowOnCases`, `unsetDocumentCases`, `unsetScreenCases`); `offset`: `layerCases`, `layerReadCases`, `layerPlaceCases`, `layerDocumentCases` (the reader's side), `pullCases`, `pullReadCases`, `pullDocumentCases` (the reader's side); `adaptive`: `weightCases` (arithmetic of the row; the other groups are in the line below)
- `sheet-dismiss`: `startCases`, `releaseCases`, `entryCases`, `ruleCases`, `escapeCases`; `media-chrome`: `modalCases`, `modalAreaCases`, `placementCases`, `shownCases` (without `statusBarIcons`); `motion`: `blurCases`
- `repeater-filter`: `filterCases`, `limitCases`, `emptinessCases`, `carouselCases`
- `long-press`, `press-feedback`, `swipe-confirm`, `shadow-color`, `border-dash`: every group but the validator's (`documentCases`, `schemaCases`); `composition`: `pressableCases`, `pressCases`, `nameCases`; `motion`: `poseCases`, `documentCases`; `bottom-zone`: the three `navBadge…Motion…` groups
- `carousel`: all eight groups
- `value-transition`: `layoutCases` (the place of the final value, the value painted over it)
- `inputs`: all groups for a reader except the validator's (`ruleCases`, `formRuleCases`, `emptinessDocumentCases`, `placementCases`) and the parts of a text field (`fieldBoxCases`, `affixRowCases`, `counterCases`, `noteRowCases`, `partsDocumentCases`); `actions`: `writeCases`, `writeControlCases`, `writePressCases`, `hapticCases`

- `media-chrome`, pictures: `ratioCases`, `imageBoxCases` (also through the real node), `paintCases`, `radiusCases`, `circleCases`
- `media-chrome`: `screenAppBarCases`, `zoneCases`, `appBarCases`, `appBarDrawnCases`, `appBarLeadingCases`, `appBarLeadingShownCases`, `appBarChildrenCases`, `screenRuleCases`, `placementCases`, `statusBarCases`, `shownCases`, `bodyTopCases`, `topZoneCases`, `screenTopZoneCases`, `screenTopPressCases`, `safeTopValueCases`, `scrolledThresholdCases`, `scrolledLayerCases`, `screenTopRuleCases`, `appBar916RuleCases`; `bottom-zone`: all groups but `documentCases`; `top-zone`: all groups. The zone rows also run through the real layout. Groups not run are named with their reason in `ScreenAnatomyCasesTests.testEveryGroupIsRunOrNamed`.

Tests also compare every shipped copy of contract data (built-in theme, icon set, versions,
action forms, widget list) with the artifacts, and draw every fixture screen off screen.

## Wiring

A table run through a rule function proves the arithmetic; the screen proves the drawing only
when it calls that same function. Tests named `…Wiring…`, `HostWiringTests`, `ScreenInteractionTests`
and the off-screen layout tests drive the real `HotlayoutScreen` (through the accessibility
interface of the platform, or by measuring the drawn view) to check that the screen does.

Some rules of the tables are carried out by the platform rather than by a function of the
reader, and their functions stay as the reference the tables are checked against:

- who takes a press at a point (`ScreenAnatomy.pressZone`, `PressTarget.receiver`) and the click
  after a long press (`LongPressRules.swallowsClick`): SwiftUI's hit testing and gestures; the
  long press and its swallowed click are driven on a simulator by the UI tests;
- the rows of a text field's marks (`InputPartsRules.affixRow`), the heights and label widths of a
  switch and a checkbox (`InputRules`), the room of the carousel dots (`CarouselRules.indicatorBlock`)
  and the natural width of a list item (`ListMarkerRules.naturalInline`): stacks of SwiftUI; the
  parts of a text field are checked by pixels in `InputPartsTests`;
- the content column of each zone (`WidthRules.contentRects`): compared with the drawn screen in
  `AdaptiveWideLayoutTests`.

`HotLayoutAPITests` compiles the README example with `import HotLayout` alone.
