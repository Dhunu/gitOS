import Testing
@testable import GitOS

@Suite("Commit button and push notice")
struct CommitUXTests {
    @Test func namesTheAccountThatWillCommit() {
        #expect(CommitButtonTitle.variants(staged: 3, hasChanges: true, login: "maya-makes")
            == ["Commit 3 files as @maya-makes", "Commit as @maya-makes", "Commit"])
    }

    @Test func singularFile() {
        #expect(CommitButtonTitle.variants(staged: 1, hasChanges: true, login: "maya")[0] == "Commit 1 file as @maya")
    }

    @Test func warnsWhenFallingBackToGlobalIdentity() {
        #expect(CommitButtonTitle.variants(staged: 2, hasChanges: true, login: nil)[0] == "Commit 2 files with global git identity")
    }

    @Test func explainsWhyNothingCanBeCommitted() {
        #expect(CommitButtonTitle.variants(staged: 0, hasChanges: true, login: "maya") == ["Stage changes to commit"])
        #expect(CommitButtonTitle.variants(staged: 0, hasChanges: false, login: "maya") == ["Nothing to commit"])
    }

    @Test func titlesGetShorterSoTheNarrowestAlwaysFits() {
        for login in ["maya", nil] as [String?] {
            let titles = CommitButtonTitle.variants(staged: 12, hasChanges: true, login: login)
            #expect(titles == titles.sorted { $0.count > $1.count })
        }
    }

    @Test func pushNoticeNamesAccountAndEmail() {
        let account = Account(githubID: 1, login: "maya-makes", displayName: "Maya", commitName: "Maya Chen", commitEmail: "maya@makes.dev")
        let notice = RepoModel.Notice.pushed(branch: "main", remote: "origin", account: account)
        #expect(notice.title == "Pushed main to origin")
        #expect(notice.detail == "as @maya-makes · maya@makes.dev")
    }

    @Test func pushNoticeWithoutAccountSaysSo() {
        let notice = RepoModel.Notice.pushed(branch: nil, remote: "upstream", account: nil)
        #expect(notice.title == "Pushed HEAD to upstream")
        #expect(notice.detail == "using your global git credentials")
    }
}
