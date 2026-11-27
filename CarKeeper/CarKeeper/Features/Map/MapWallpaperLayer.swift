import SwiftUI

struct MapWallpaperLayer: View {
    let image: UIImage?
    let position: Double

    var body: some View {
        GeometryReader { g in
            let w = max(1, g.size.width)
            let h = max(1, g.size.height)
            let drawn = Self.coverWidth(of: image, in: CGSize(width: w, height: h))
            let travel = max(0, drawn - w)
            ZStack(alignment: .leading) {
                TokensPalette.canvas
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: drawn, height: h)
                        .clipped()
                        .offset(x: -CGFloat(min(1, max(0, position))) * travel)
                }
            }
            .frame(width: w, height: h, alignment: .leading)
            .clipped()
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    static func coverWidth(of image: UIImage?, in size: CGSize) -> CGFloat {
        guard let img = image, img.size.width > 0, img.size.height > 0 else { return size.width }
        let ar = img.size.width / img.size.height
        return max(size.width, size.height * ar)
    }
}
