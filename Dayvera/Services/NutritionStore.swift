import Foundation
import UIKit

enum NutritionStore {
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let values = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", values.year!, values.month!, values.day!)
    }
    static func mealDayKey(_ meal: MealRecord) -> String {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: meal.timeZoneID) ?? .current
        return dayKey(meal.date, calendar: calendar)
    }
    static var mediaDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NutritionPhotos", isDirectory: true)
    }
    static func photoURL(_ filename: String) -> URL? {
        guard filename == URL(fileURLWithPath: filename).lastPathComponent, filename.hasSuffix(".jpg") else { return nil }
        return mediaDirectory.appendingPathComponent(filename)
    }
    /// Redraw strips metadata and normalizes orientation before local analysis/storage.
    static func normalizedPhoto(_ data: Data) throws -> Data {
        guard data.count <= 30_000_000, let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
            throw NutritionError.invalid("Choose an image smaller than 30 MB.")
        }
        let scale = min(1, 1280 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = rendered.jpegData(compressionQuality: 0.8) else { throw NutritionError.invalid("This image could not be prepared.") }
        return jpeg
    }
    static func savePhoto(_ data: Data) throws -> String {
        let directory = mediaDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var protected = directory; try protected.setResourceValues(values)
        let filename = UUID().uuidString + ".jpg"
        try data.write(to: directory.appendingPathComponent(filename), options: [.atomic, .completeFileProtection])
        return filename
    }
    static func removePhoto(_ filename: String?) {
        guard let filename, let url = photoURL(filename) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
