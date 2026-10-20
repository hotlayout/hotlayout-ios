# Security model

The document, the theme and the data arrive over the network. HotLayout treats all three as
untrusted input: a document may have been written by someone other than the builder, and the
reader must not let it reach further than drawing a screen.

## What the reader guarantees

- **No crash on malformed input.** A piece of the wrong shape (a node without `props`, a string
  where an object belongs, a number out of range) is skipped and reported through `onReport`; the
  rest of the screen is drawn. A tree deeper than 32 levels under the root is refused as a whole.
  Every number of the document, the theme or the data that becomes an integer is checked first, so
  a value such as `1e300` cannot end the host process.
- **The reader opens nothing by itself.** `navigate`, `navigate.back`, `navigate.section`,
  `setValue` and `toggleValue` stay inside the document. `openUrl`, `deeplink`, `close` and every
  other action go to `onAction`, with the parameters checked against the forms of the contract
  (`standard` or `invalid`, never both). An address is judged by the contract's expression, not by
  a platform URL parser. `StandardActions.url(for:allowedDeeplinkSchemes:)` opens an app link only
  for a scheme the host allows.
- **Writes are gated.** A field or a write action writes only to a path of the form of a data path;
  a segment `__proto__`, `constructor` or `prototype` is refused. `writablePaths` narrows the list
  further. A refused path reaches neither the session of the screen nor `onWrite`.
- **Pictures go through the host's policy.** By default (`ImagePolicy.httpsOnly`) the address has
  exactly the form of an `openUrl` address of the contract: `https:` and a host name with an
  alphabetic top-level domain. IP literals in any base, IPv6, `localhost`, single-label names and
  addresses with user information are refused. A host's own `resolve` is final, except that
  `javascript:` and `vbscript:` (read as a URL parser reads them) are never a picture. A refused
  address makes no request and is reported: the address of the document cut at 120 characters, an
  address from data by scheme and host only (its path or query may carry a token).
  Every redirect target is put to the same policy, and at most three redirects are followed.
- **Pictures are bounded.** One picture is at most 10 MiB (`maxDownloadBytes`, checked against
  `Content-Length` and while reading), its transfer, redirects included, has 30 seconds, and its
  longer side is at most 4096 pixels when decoded (`maxPixelSide`; the size is read from the
  header, and a larger picture is made smaller with its proportion kept, not refused).
- **Pictures are private.** They are fetched with an ephemeral session of the package: no cookies
  of the host app are sent or stored, no credentials are attached, no `Referer` goes out, and
  nothing goes into the URL cache of the app.
- **Lists are bounded per screen.** A list draws at most 50 records, and nested lists multiply
  that, so a screen draws at most 2550 instances of list templates in all, counted in document
  order over the tree of its width class (a list hidden by a condition, in an inactive tab or in a
  folded block costs the same). What is beyond is not drawn, and one report says how many.
- **Theme numbers are bounded.** A number of a theme outside the bounds of the theme schema, or
  not finite, is replaced by the value of the same token and field of the built-in theme of the
  same brightness, otherwise by the nearest bound, and reported.
- **Accessibility names speak only what is shown.** A pressable card is named from the children
  shown under the current data and width class; a text that paints nothing (opacity 0, or a colour
  with opacity 0) is not part of it.

## What the host decides

- What an action of the app does, and whether to perform a standard action at all.
- Which data paths a document may write (`writablePaths`), and what it does with the values in
  `onWrite`: they are what the person typed and must be validated before they are trusted.
- Where pictures may come from (`ImagePolicy.resolve`) and how large they may be.

## Known limits

- The breadth of a document is not capped: a screen with a very large number of sibling nodes is
  built and drawn in full (list instances are capped per screen, see above).

## Reporting a vulnerability

Please report security issues privately to the maintainers through the contact on
[hotlayout.com](https://hotlayout.com) rather than in a public issue.
