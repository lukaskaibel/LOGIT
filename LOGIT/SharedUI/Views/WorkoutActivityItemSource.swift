//
//  WorkoutActivityItemSource.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 26.02.26.
//

import UIKit
import LinkPresentation

/// Custom UIActivityItemSource that provides a rich share sheet preview
/// showing the LOGIT app icon and workout/template name instead of raw JSON content.
final class WorkoutActivityItemSource: NSObject, UIActivityItemSource {
    
    private let fileURL: URL
    private let title: String
    
    init(fileURL: URL, title: String) {
        self.fileURL = fileURL
        self.title = title
        super.init()
    }
    
    // The placeholder tells the share sheet what type of data we're sharing
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return fileURL
    }
    
    // The actual item to share
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return fileURL
    }
    
    // Explicitly declare the UTI so the receiving device knows this is a LOGIT file
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "logitworkout":
            return "com.logit.workout"
        case "logittemplate":
            return "com.logit.template"
        default:
            return "public.data"
        }
    }
    
    // Provide a subject line (used in Mail, Messages, etc.)
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return title
    }
    
    // Rich metadata for the share sheet preview
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.originalURL = fileURL
        
        // Use the app icon for the preview thumbnail
        if let appIcon = loadAppIcon() {
            metadata.iconProvider = NSItemProvider(object: appIcon)
        }
        
        return metadata
    }
    
    /// Loads the app icon from the main bundle
    private func loadAppIcon() -> UIImage? {
        // Try loading the app icon via the standard Info.plist approach
        if let iconsDictionary = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primaryIconsDictionary = iconsDictionary["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primaryIconsDictionary["CFBundleIconFiles"] as? [String],
           let lastIcon = iconFiles.last,
           let icon = UIImage(named: lastIcon) {
            return icon
        }
        // Fallback: try loading directly from bundle
        if let iconURL = Bundle.main.url(forResource: "AppIcon60x60@3x", withExtension: "png"),
           let data = try? Data(contentsOf: iconURL),
           let icon = UIImage(data: data) {
            return icon
        }
        // Final fallback: use the custom LOGIT symbol
        return UIImage(named: "LOGIT")
    }
}
