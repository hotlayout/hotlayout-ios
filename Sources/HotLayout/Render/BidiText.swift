import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// The base direction of a paragraph and the slant of scripts that have no italic.
///
/// `Text` takes the direction of a paragraph from its first strong letter, whatever the layout
/// direction of the environment says. The contract says the direction follows the language of the
/// SHOWN text (`directionFollows`), so «+50» in an Arabic line must be set right to left as
/// «50+». SwiftUI ignores `NSParagraphStyle.baseWritingDirection`, so the paragraph is led by one
/// zero-width mark of the wanted direction, added to what is DRAWN only; the strings of the
/// contract (templates, money, markers) stay free of marks.
enum BidiText {
    static let leftToRightMark = "\u{200E}"
    static let rightToLeftMark = "\u{200F}"

    /// The text to hand to `Text` so that the paragraph runs in `rightToLeft`.
    static func led(_ text: String, rightToLeft: Bool) -> String {
        text.isEmpty ? text : (rightToLeft ? rightToLeftMark : leftToRightMark) + text
    }

    /// The text cut to what is drawn (see `drawLimit`), on a character boundary.
    static func limited(_ text: String) -> String {
        guard text.utf16.count > drawLimit else { return text }
        let index = text.utf16.index(text.utf16.startIndex, offsetBy: drawLimit)
        let cut = String.Index(index, within: text) ?? text.index(before: index)
        return String(text[..<cut]) + "…"
    }

    /// Longer text is drawn from its start only. One `Text` of hundreds of thousands of characters
    /// makes SwiftUI lay out nothing at all and the node would be an empty box.
    static let drawLimit = 8_000

    /// A character of a script with no italic face in the system font.
    static func lacksItalic(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: return true
        default: return false
        }
    }

    /// The text split into pieces: those in a script with no italic face (slanted by a shear, a
    /// synthetic italic) and the rest (real italic). Neutral characters stay
    /// with the piece before them.
    static func italicPieces(_ text: String) -> [(text: String, sheared: Bool)] {
        var pieces: [(text: String, sheared: Bool)] = []
        for character in text {
            let scalars = character.unicodeScalars
            let strong = scalars.first { $0.properties.isAlphabetic || $0.properties.numericType != nil }
            let sheared = strong.map(lacksItalic) ?? pieces.last?.sheared ?? false
            if let last = pieces.last, last.sheared == sheared {
                pieces[pieces.count - 1].text.append(character)
            } else {
                pieces.append((String(character), sheared))
            }
        }
        return pieces
    }
}

extension TextStyleValue {
    /// The font with a synthetic slant (12 degrees), for scripts whose face has no italic.
    func shearedFont(family: String?) -> Font {
        #if canImport(UIKit)
        let weight = Font.Weight(cssWeight: fontWeight)
        let base: UIFont
        if let family, Self.isInstalled(family), let named = UIFont(name: family, size: fontSize) {
            base = named
        } else {
            base = UIFont.systemFont(ofSize: fontSize, weight: Self.uiWeight(weight))
        }
        let slant = CGAffineTransform(a: 1, b: 0, c: CGFloat(tan(12.0 * Double.pi / 180)), d: 1, tx: 0, ty: 0)
        return Font(UIFont(descriptor: base.fontDescriptor.withMatrix(slant), size: fontSize))
        #else
        return font(family: family, italic: true)
        #endif
    }

    #if canImport(UIKit)
    static func uiWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
    #endif
}

/// One styled run as a `Text`: the font, the letter spacing, the slant where the script has no
/// italic, and, for the first run of a paragraph, the mark that sets its direction.
func styledRun(_ text: String, style: TextStyleValue, family: String?, italic: Bool, rightToLeft: Bool, leadsParagraph: Bool) -> Text {
    let shown = BidiText.limited(text)
    let pieces: [(text: String, sheared: Bool)] = italic ? BidiText.italicPieces(shown) : [(shown, false)]
    var result = Text("")
    for (index, piece) in pieces.enumerated() {
        let content = index == 0 && leadsParagraph ? BidiText.led(piece.text, rightToLeft: rightToLeft) : piece.text
        let font = piece.sheared ? style.shearedFont(family: family) : style.font(family: family, italic: italic)
        result = result + Text(content).font(font).tracking(style.letterSpacing)
    }
    return result
}
