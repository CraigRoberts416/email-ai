import Foundation

// No token or network is requested. Only GmailClient.mimeMessage is exercised.
struct AuthService { func validAccessToken(for id: String) async throws -> String { fatalError("Unexpected network access") } }
enum APIError: Error { case transport }

@main struct GmailMIMETests {
    static func main() throws {
        let file = GmailClient.FileAttachment(filename: "résumé.pdf", mimeType: "application/pdf", data: Data([0, 1, 2, 127, 128, 255]))
        let full = GmailClient.Draft(to: ["recipient@example.invalid"], cc: ["copy@example.invalid"], subject: "Forward — source", body: "A note\n\nOriginal email: real source words.", threadID: nil, inReplyTo: "gmail-resource-id", attachments: [file])
        let plain = GmailClient.Draft(to: ["recipient@example.invalid"], subject: "Reply\r\nBcc: evil@example.invalid", body: "Unicode body: café", threadID: "gmail-thread", inReplyTo: "<real@example.invalid>")
        var unsafe = plain
        unsafe.to = ["recipient@example.invalid\r\nBcc: injected@example.invalid"]
        do { _ = try GmailClient.mimeMessage(unsafe); fatalError("Accepted recipient header injection") } catch {}
        unsafe = plain
        unsafe.attachments = [.init(filename: "too-big", mimeType: "text/plain", data: Data(repeating: 0, count: 25_000_001))]
        do { _ = try GmailClient.mimeMessage(unsafe); fatalError("Accepted oversized attachment") } catch {}
        let result = ["multipart": try GmailClient.mimeMessage(full, boundary: "synthetic-boundary"),
                      "plain": try GmailClient.mimeMessage(plain)]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result))
    }
}
