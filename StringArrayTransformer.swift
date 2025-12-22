import Foundation
import SwiftData

@objc(StringArrayTransformer)
class StringArrayTransformer: ValueTransformer {
    static var recoveryNeeded = false
    private static var logCount = 0
    private static let maxLogEntries = 5 // Only log the first 5 transformations
    
    // Specify the transformed value class as NSData
    override class func transformedValueClass() -> AnyClass {
        return NSData.self
    }
    
    // Allow reverse transformation
    override class func allowsReverseTransformation() -> Bool {
        return true
    }
    
    // Helper method to control logging
    private func log(_ message: String) {
        if Self.logCount < Self.maxLogEntries {
            print(message)
            Self.logCount += 1
        } else if Self.logCount == Self.maxLogEntries {
            print("StringArrayTransformer: Further logging suppressed to reduce console output")
            Self.logCount += 1
        }
    }

    // Encode the array into Data
    override func transformedValue(_ value: Any?) -> Any? {
        guard let array = value as? [String] else {
            log("StringArrayTransformer: Input value is not a valid array of strings.")
            return nil
        }
        
        // Use NSKeyedArchiver since that's what we're getting when decoding
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: array, requiringSecureCoding: false)
            log("StringArrayTransformer: Successfully encoded array of size \(array.count)")
            return data
        } catch {
            log("StringArrayTransformer: Error encoding array: \(error)")
            return nil
        }
    }

    // Decode the Data back into an array with improved error handling
    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else {
            log("StringArrayTransformer: Input value is not valid data.")
            return nil
        }
        
        // First try NSKeyedUnarchiver with explicit allowed classes
        do {
            // Include NSData in allowed classes
            let allowedClasses = [NSArray.self, NSString.self, NSData.self]
            if let array = try NSKeyedUnarchiver.unarchivedObject(ofClasses: allowedClasses, from: data) as? [String] {
                return array
            }
        } catch {
            // Silent handling - we'll try other methods
        }
        
        // If that fails, try property list approach
        if data.count >= 8 && data.prefix(8).elementsEqual("bplist00".data(using: .ascii)!) {
            do {
                let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                
                // Handle NSKeyedArchiver format
                if let dict = plist as? [String: Any], 
                   dict.keys.contains("$archiver") && dict.keys.contains("$objects") && dict.keys.contains("$top") {
                    
                    // Check for the empty JSON array case
                    if let objects = dict["$objects"] as? [Any],
                       objects.count > 1,
                       let dataObject = objects[1] as? Data,
                       dataObject.count == 2,
                       dataObject[0] == 0x5b, // '['
                       dataObject[1] == 0x5d  // ']'
                    {
                        return []
                    }
                    
                    // Try to extract JSON array from NSData
                    if let objects = dict["$objects"] as? [Any],
                       objects.count > 1, 
                       let dataObject = objects[1] as? Data {
                        do {
                            if let jsonString = String(data: dataObject, encoding: .utf8),
                               jsonString.hasPrefix("[") && jsonString.hasSuffix("]") {
                                return try JSONDecoder().decode([String].self, from: dataObject)
                            }
                        } catch {
                            // Silent handling - we'll try other methods
                        }
                    }
                    
                    // Other manual extraction methods - if needed
                }
                
                // Try regular property list formats
                if let array = plist as? [String] {
                    return array
                } else if let singleString = plist as? String {
                    return [singleString]
                }
            } catch {
                // Silent handling - we'll try other methods
            }
        }
        
        // If property list decoding fails, try JSON decoding
        do {
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            // Silent handling - we'll try other methods
        }
        
        // Return empty array as fallback
        return []
    }
}

extension NSValueTransformerName {
    // Custom transformer name
    static let stringArrayTransformerName = NSValueTransformerName(rawValue: "StringArrayTransformer")
}

extension StringArrayTransformer {
    static func register() {
        let name = NSValueTransformerName.stringArrayTransformerName
        
        // Make sure we don't register twice
        if ValueTransformer(forName: name) == nil {
            let transformer = StringArrayTransformer()
            ValueTransformer.setValueTransformer(transformer, forName: name)
            print("App initialization - StringArrayTransformer registered")
        }
    }
}
