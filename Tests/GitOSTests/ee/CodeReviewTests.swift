import Foundation
import Testing
@testable import GitOS

struct CodeReviewTests {
    // MARK: Parsing

    @Test func parsesCleanJSON() {
        let reply = """
        {"summary": "Solid fix with one hole.",
         "issueCompliance": "Does what #9 asks.",
         "findings": [
           {"severity": "warning", "confidence": "medium", "file": "B.swift", "line": 2,
            "title": "Inconsistent backoff", "detail": "Elsewhere it's exponential.", "suggestion": null},
           {"severity": "blocker", "confidence": "high", "file": "A.swift", "line": 84,
            "title": "Unbounded retry", "detail": "Loops forever.", "suggestion": "cap at 5"}
         ]}
        """
        let review = CodeReview.parse(reply)
        #expect(review.summary == "Solid fix with one hole.")
        #expect(review.issueCompliance == "Does what #9 asks.")
        #expect(review.findings.count == 2)
        // Blockers sort first regardless of reply order.
        #expect(review.findings[0].severity == .blocker)
        #expect(review.findings[0].file == "A.swift")
        #expect(review.findings[0].line == 84)
        #expect(review.findings[0].suggestion == "cap at 5")
        #expect(review.verdict == .block)
    }

    @Test func toleratesFencesAndProse() {
        let reply = """
        Here's my review:
        ```json
        {"summary": "Fine.", "issueCompliance": null, "findings": []}
        ```
        Hope that helps!
        """
        let review = CodeReview.parse(reply)
        #expect(review.summary == "Fine.")
        #expect(review.issueCompliance == nil)
        #expect(review.findings.isEmpty)
        #expect(review.verdict == .approve)
    }

    @Test func proseReplyBecomesSummaryOnly() {
        let review = CodeReview.parse("The change looks reasonable overall, nothing jumps out.")
        #expect(review.findings.isEmpty)
        #expect(review.summary.contains("looks reasonable"))
    }

    @Test func unknownFieldsGetSafeDefaults() {
        let reply = """
        {"summary": "s", "findings": [
          {"severity": "catastrophic", "file": "A.swift", "title": "Something"},
          {"file": "B.swift", "detail": "Only a detail, no title"},
          {"severity": "nit", "file": "C.swift"}
        ]}
        """
        let review = CodeReview.parse(reply)
        // The finding with neither title nor detail is dropped.
        #expect(review.findings.count == 2)
        let first = review.findings.first { $0.file == "A.swift" }
        #expect(first?.severity == .warning)        // unknown severity downgrades to warning
        #expect(first?.confidence == .medium)       // missing confidence defaults to medium
        let second = review.findings.first { $0.file == "B.swift" }
        #expect(second?.title == "Only a detail, no title")
    }

    @Test func verdictFollowsWorstFinding() {
        func finding(_ severity: CodeReview.Severity) -> CodeReview.Finding {
            .init(severity: severity, confidence: .high, file: "F", line: nil, title: "t", detail: "d", suggestion: nil)
        }
        #expect(CodeReview.Verdict.from([]) == .approve)
        #expect(CodeReview.Verdict.from([finding(.nit)]) == .approve)
        #expect(CodeReview.Verdict.from([finding(.nit), finding(.warning)]) == .caution)
        #expect(CodeReview.Verdict.from([finding(.warning), finding(.blocker)]) == .block)
    }

    // MARK: Prompt building

    @Test func oversizedFilesAreSkippedAndListed() {
        let small = CodeReview.File(path: "Small.swift", patch: "+let a = 1", content: nil)
        let huge = CodeReview.File(path: "Huge.generated.swift",
                                   patch: String(repeating: "+x\n", count: CodeReview.Budget.patches),
                                   content: nil)
        let (text, skipped) = CodeReview.prompt(for: .init(heading: "Test", files: [small, huge]))
        #expect(skipped == ["Huge.generated.swift"])
        #expect(text.contains("Small.swift"))
        #expect(text.contains("Not shown (too large): Huge.generated.swift"))
        #expect(text.count < CodeReview.Budget.patches + 5_000)
    }

    @Test func fullContentsRespectTheirBudget() {
        let withContent = CodeReview.File(path: "A.swift", patch: "+a", content: "struct A {}")
        let tooBig = CodeReview.File(path: "B.swift", patch: "+b",
                                     content: String(repeating: "x", count: CodeReview.Budget.perFileContent + 1))
        let (text, _) = CodeReview.prompt(for: .init(heading: "Test", files: [withContent, tooBig]))
        #expect(text.contains("=== A.swift"))
        #expect(!text.contains("=== B.swift"))
    }

    @Test func contextSectionsAppearWhenGiven() {
        let input = CodeReview.PromptInput(
            heading: "Pull request #7 into main",
            title: "Fix the thing",
            description: "It was broken.",
            issue: "#9 The thing is broken",
            rules: "Never force-unwrap.",
            files: [.init(path: "A.swift", patch: "+a", content: nil)])
        let (text, _) = CodeReview.prompt(for: input)
        #expect(text.contains("Pull request #7"))
        #expect(text.contains("Linked issue:\n#9"))
        #expect(text.contains("Review rules for this repository:\nNever force-unwrap."))
    }

    // MARK: Output

    @Test func markdownCarriesTheFindings() {
        let review = CodeReview.Review(
            summary: "One problem.",
            issueCompliance: "Matches the issue.",
            findings: [.init(severity: .blocker, confidence: .high, file: "Sync.swift", line: 84,
                             title: "Unbounded retry", detail: "Loops forever.", suggestion: "cap it")],
            skippedFiles: ["Big.swift"])
        let markdown = CodeReview.markdown(for: review, heading: "pull request #14")
        #expect(markdown.contains("**BLOCKER** `Sync.swift:84` — Unbounded retry"))
        #expect(markdown.contains("Matches the issue."))
        #expect(markdown.contains("Fix: cap it"))
        #expect(markdown.contains("Big.swift"))
        #expect(markdown.contains("Advisory only"))
    }

    @Test func fixPromptIsSelfContained() {
        let finding = CodeReview.Finding(severity: .warning, confidence: .medium, file: "Auth.swift", line: 31,
                                         title: "Timing-unsafe comparison", detail: "Token compared with ==.",
                                         suggestion: "use constant-time comparison")
        let prompt = CodeReview.fixPrompt(for: finding)
        #expect(prompt.contains("Auth.swift at line 31"))
        #expect(prompt.contains("Timing-unsafe comparison"))
        #expect(prompt.contains("constant-time comparison"))
    }

    @Test func dismissalKeySurvivesLineDriftAndCase() {
        func finding(line: Int?, title: String) -> CodeReview.Finding {
            .init(severity: .warning, confidence: .high, file: "A.swift", line: line,
                  title: title, detail: "d", suggestion: nil)
        }
        #expect(finding(line: 10, title: "Bad Retry").dismissalKey == finding(line: 99, title: "bad retry ").dismissalKey)
        #expect(finding(line: 10, title: "Bad Retry").dismissalKey != finding(line: 10, title: "Other").dismissalKey)
    }
}
