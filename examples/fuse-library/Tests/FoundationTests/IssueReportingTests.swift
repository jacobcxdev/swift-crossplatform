#if !SKIP
import IssueReporting
import Testing

// IR-01: reportIssue with string message causes test failure
@Test func reportIssueStringMessage() {
    withKnownIssue {
        reportIssue("Something went wrong")
    }
}

// IR-02: reportIssue with Error causes test failure
@Test func reportIssueErrorInstance() {
    struct TestError: Error, CustomStringConvertible {
        var description: String { "test error occurred" }
    }
    withKnownIssue {
        reportIssue(TestError())
    }
}

// IR-03: withErrorReporting catches synchronous errors and reports them
@Test func withErrorReportingSyncCatchesErrors() {
    struct TestError: Error {}
    withKnownIssue {
        withErrorReporting {
            throw TestError()
        }
    }
}

// IR-04: withErrorReporting catches async errors and reports them
@Test func withErrorReportingAsyncCatchesErrors() async {
    struct TestError: Error {}
    await withKnownIssue {
        await withErrorReporting {
            throw TestError()
        }
    }
}

// Verify reportIssue with fileID/line captures source location
@Test func reportIssueIncludesSourceLocation() {
    withKnownIssue {
        reportIssue("location test")
    }
}

// Verify withErrorReporting returns nil on error
@Test func withErrorReportingReturnsNilOnError() {
    struct TestError: Error {}
    withKnownIssue {
        let result: Int? = withErrorReporting {
            throw TestError()
        }
        #expect(result == nil)
    }
}
#endif
