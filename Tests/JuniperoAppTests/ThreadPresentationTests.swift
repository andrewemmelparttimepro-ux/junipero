#if canImport(Testing)
import Testing
@testable import JuniperoApp

struct ThreadPresentationTests {
    @Test
    func presentableErrorMessageCollapsesRawTimeoutDump() {
        let raw = """
        Primary and fallback both failed. Primary: Error Domain=NSURLErrorDomain Code=-1001 "The request timed out." UserInfo={_kCFStreamErrorCodeKey=-2102, NSErrorFailingURLStringKey=http://127.0.0.1:18789/v1/chat/completions} | Fallback: Error Domain=NSURLErrorDomain Code=-1001 "The request timed out." UserInfo={NSErrorFailingURLStringKey=http://127.0.0.1:11434/api/chat}
        """

        let cleaned = ChatThread.presentableErrorMessage(raw)

        #expect(cleaned == "The reply took too long and timed out. Retry, or pick a faster model in Setup.")
    }
}
#endif
