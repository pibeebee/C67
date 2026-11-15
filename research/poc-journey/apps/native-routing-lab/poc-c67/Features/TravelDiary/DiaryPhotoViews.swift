import ImageIO
import PhotosUI
import SwiftUI
import UIKit

enum DiaryStyle {
    static let ink = Color.primary
    static let accent = Color(red: 0.64, green: 0.29, blue: 0.20)
    static let paper = Color(uiColor: .secondarySystemGroupedBackground)
}

enum DiaryPhotoCodec {
    nonisolated static func normalized(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 1800
              ] as CFDictionary),
              let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.82) else {
            throw DiaryError.message("Foto ini belum dapat dibuka. Coba pilih foto lain.")
        }
        return jpeg
    }

    #if DEBUG
        static func fixture() -> Data {
            UIGraphicsImageRenderer(size: CGSize(width: 600, height: 750)).jpegData(withCompressionQuality: 0.8) { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 600, height: 750))
                UIColor.systemYellow.setFill()
                context.cgContext.fillEllipse(in: CGRect(x: 390, y: 80, width: 110, height: 110))
                UIColor.darkGray.setFill()
                context.fill(CGRect(x: 0, y: 510, width: 600, height: 240))
            }
        }
    #endif
}

struct DiaryPhoto: View {
    let data: Data?
    var body: some View {
        GeometryReader { proxy in
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height).clipped()
            } else {
                ZStack {
                    Color(red: 0.78, green: 0.85, blue: 0.82)
                    Circle().fill(Color(red: 0.96, green: 0.81, blue: 0.52))
                        .frame(width: proxy.size.width * 0.25)
                        .offset(x: proxy.size.width * 0.23, y: -proxy.size.height * 0.18)
                    VStack(spacing: 0) {
                        Spacer()
                        Image(systemName: "building.2.crop.circle")
                            .font(.system(size: min(proxy.size.width * 0.25, 60), weight: .ultraLight))
                            .foregroundStyle(Color(red: 0.29, green: 0.39, blue: 0.34))
                        Rectangle().fill(Color(red: 0.40, green: 0.49, blue: 0.38)).frame(height: proxy.size.height * 0.25)
                    }
                    if proxy.size.width >= 120 {
                        Text("ILUSTRASI KENANGAN")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(1).padding(6).background(.regularMaterial, in: Capsule())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(10)
                    }
                }
            }
        }
        .clipped()
        .accessibilityLabel(data == nil ? "Ilustrasi contoh; foto pembuat belum dipilih" : "Foto kenangan")
    }
}

struct DiaryPhotoStamp: View {
    let original: Data?
    let footprint: Data?
    var body: some View {
        ZStack {
            if footprint != nil {
                RoundedRectangle(cornerRadius: 4).fill(.background).frame(width: 62, height: 72)
                    .rotationEffect(.degrees(-12)).offset(x: -6, y: -3)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
            }
            VStack(spacing: 4) {
                DiaryPhoto(data: footprint ?? original).frame(width: 54, height: 52)
                Circle().fill(DiaryStyle.accent).frame(width: 4, height: 4)
            }
            .padding(5).background(.background, in: RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.18), radius: 5, y: 3)
        }
        .frame(width: 80, height: 85)
        .accessibilityLabel(footprint == nil ? "Pin kenangan pembuat" : "Pin kenangan bersama")
    }
}

struct DiaryMomentCard: View {
    let photo: Data?
    let heading: String
    let name: String
    let date: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DiaryPhoto(data: photo).aspectRatio(0.85, contentMode: .fit)
            Text(heading.uppercased()).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
            Text(name).font(.headline)
            Text(date, format: .dateTime.day().month(.abbreviated).year()).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10).background(DiaryStyle.paper, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.primary.opacity(0.08)))
    }
}

struct DiaryPostcard: View {
    let pin: DiaryPin
    let footprint: DiaryFootprint
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Same place,\ndifferent time.").font(.system(.largeTitle, design: .serif).weight(.medium))
            Text(pin.title).font(.subheadline).foregroundStyle(.secondary)
            if typeSize.isAccessibilitySize {
                VStack(spacing: 12) { original; now }
            } else {
                HStack(alignment: .top, spacing: 12) { original; now }
            }
            Label("Dua waktu. Satu tempat yang menghubungkan kalian.", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.subheadline).foregroundStyle(.secondary)
            if footprint.simulated {
                Label("Lokasi simulasi · bukan bukti kunjungan nyata", systemImage: "testtube.2")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }
    private var original: some View {
        DiaryMomentCard(photo: pin.photo, heading: "Dulu di sini", name: pin.creator, date: pin.visitedAt)
    }
    private var now: some View {
        DiaryMomentCard(photo: footprint.photo, heading: "Sekarang di sini", name: footprint.name, date: footprint.uploadedAt)
    }
}

struct DiaryCamera: UIViewControllerRepresentable {
    let selected: (UIImage) -> Void
    let cancelled: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(selected: selected, cancelled: cancelled) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let selected: (UIImage) -> Void
        let cancelled: () -> Void
        init(selected: @escaping (UIImage) -> Void, cancelled: @escaping () -> Void) {
            self.selected = selected; self.cancelled = cancelled
        }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage else { cancelled(); return }
            selected(image)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { cancelled() }
    }
}
