import SwiftUI

/// Where an image of the document comes from (`ImageSource`): an asset token of the host, an
/// address, or an address from data with an asset token as the fallback. Every address goes
/// through the host's policy (by default the address form of `openUrl`); a refused one draws the
/// placeholder, makes no request and is reported.
enum ImageSource {
    static func url(_ source: JSONValue?, context: RenderContext) -> URL? {
        guard let object = source?.objectValue else { return nil }
        func judged(_ address: String, fromData: Bool) -> URL? {
            let url = context.images.resolve(address)
            if url == nil {
                context.sink.add(.ignoredInput, "screen “\(context.screenId)”: image", ImageSourceRules.refusal(address, fromData: fromData))
            }
            return url
        }
        switch object["kind"]?.stringValue {
        case "asset":
            return object["asset"]?.stringValue.flatMap { context.images.assets[$0] }
        case "url":
            return object["url"]?.stringValue.flatMap { judged($0, fromData: false) }
        case "binding":
            if let path = object["path"]?.stringValue, let address = context.scope[path]?.stringValue, !address.isEmpty,
                let url = judged(address, fromData: true)
            {
                return url
            }
            return object["fallback"]?.stringValue.flatMap { context.images.assets[$0] }
        default:
            return nil
        }
    }
}

/// A picture in a box: the placeholder while it loads and when it fails, then the file placed
/// by `ImageRules.paintRect` (`cover` over the box, `contain` inside it, centred) and cut by the
/// box. The slot is the same before and after, so the layout does not jump.
struct RemoteImage: View {
    let url: URL?
    let fit: String
    let placeholder: Color
    /// Where a picture that failed to load is reported; none outside a screen.
    var sink: ReportSink?
    @StateObject private var loader = ImageLoader()

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let image = loader.image {
                    let natural = image.size.height > 0 ? Double(image.size.width / image.size.height) : 1
                    let rect = ImageRules.paintRect(boxWidth: Double(proxy.size.width), boxHeight: Double(proxy.size.height), natural: natural, fit: fit)
                    platformPicture(image)
                        .resizable()
                        .frame(width: rect.width, height: rect.height)
                        // `position`, not `offset`: SwiftUI mirrors an offset in right-to-left text.
                        .position(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2)
                } else {
                    placeholder
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
        }
        .onAppear { load(url) }
        .onChange(of: url) { load($0) }
    }

    private func load(_ url: URL?) {
        let sink = sink
        loader.load(url) { failed in sink?.add(.ignoredInput, "image", ImageSourceRules.failure(failed)) }
    }

    private func platformPicture(_ image: PlatformImage) -> Image {
        #if canImport(UIKit)
        Image(uiImage: image)
        #else
        Image(nsImage: image)
        #endif
    }
}
