//
//  LocalizationSorter.swift
//  Loop
//
//  Created by Kai Azim on 2025-11-01.
//

/// To compile, run this: `swiftc -O ./.github/LocalizationSorter.swift -o ./.github/LocalizationSorter`

import Foundation

/// Crowdin's Localizable.xcstrings file includes null comments.
/// Since Xcode doesn't generate null comments, it's cleaner to remove them.
func removeNullComments(from json: Any) -> Any {
    if let dict = json as? [String: Any] {
        var newDict = [String: Any]()
        for (key, value) in dict {
            if key == "comment" && value is NSNull {
                continue
            }
            newDict[key] = removeNullComments(from: value)
        }
        return newDict
    } else if let array = json as? [Any] {
        return array.map { removeNullComments(from: $0) }
    }
    return json
}

/// Crowdin's Localizable.xcstrings is set to export empty strings when exporting a key without a localization.
/// This function removes them so that Loop uses the default English key instead of displaying an empty string.
func removeEmptyStrings(from json: Any) -> Any {
    if let dict = json as? [String: Any] {
        var newDict = [String: Any]()
        for (key, value) in dict {
            // Check if this is a stringUnit dictionary with an empty "value"
            if key == "stringUnit",
               let stringUnitDict = value as? [String: Any],
               let stringValue = stringUnitDict["value"] as? String,
               stringValue.isEmpty {
                // Skip adding this key to newDict, effectively removing it
                continue
            }
            
            // Recurse for other keys
            newDict[key] = removeEmptyStrings(from: value)
        }
        return newDict
    } else if let array = json as? [Any] {
        return array.map { removeEmptyStrings(from: $0) }
    }
    return json
}

/// Crowdin's Localizable.xcstrings file's localizations are not sorted alphabetically.
/// To sort them, we can simply read it into a JSON object here in Swift, then re-output it as JSON, with the `.sortedKeys` option enabled in the encoder.
func sortLocalizations(inputPath: String, outputPath: String) throws {
    // Read and decode as generic JSON dictionary
    let data = try Data(contentsOf: URL(fileURLWithPath: inputPath))
    let json = try JSONSerialization.jsonObject(with: data)
    
    // Remove null comments and sort
    let noNullCommentsJson = removeNullComments(from: json)
    let cleanedJson = removeEmptyStrings(from: noNullCommentsJson)
    
    // Write back with sorted keys
    let sortedData = try JSONSerialization.data(
        withJSONObject: cleanedJson,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    
    // Write output
    try sortedData.write(to: URL(fileURLWithPath: outputPath))
}

do {
    let args = CommandLine.arguments
    if args.count != 3 {
        print("Usage: swift LocalizationSorter.swift <input_file> <output_file>")
        exit(1)
    }
    
    try sortLocalizations(inputPath: args[1], outputPath: args[2])
    print("Successfully sorted localizations!")
} catch {
    print("Error: \(error)")
    exit(1)
}
