import Foundation

protocol VoiceParsingDelegate: AnyObject {
    func didParseItems(_ result: ParsedResult)
}
