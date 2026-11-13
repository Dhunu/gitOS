import Testing
@testable import GitOS

@Suite("Telling accounts apart")
struct AccountLabelTests {
    private func account(_ login: String, label: String = "") -> Account {
        Account(githubID: 1, login: login, displayName: "Maya", label: label, commitName: "Maya", commitEmail: "\(login)@x.dev")
    }

    @Test func badgeUsesTheLabelSoSamePersonAccountsDiffer() {
        let initials = [account("maya-northwind", label: "Work"), account("maya-makes", label: "Personal"), account("maya-acme", label: "Client")]
            .map(\.badgeInitial)
        #expect(initials == ["W", "P", "C"])
    }

    @Test func badgeFallsBackToLoginWithoutALabel() {
        #expect(account("maya").badgeInitial == "M")
        #expect(account("maya", label: "  ").badgeInitial == "M")
    }

    @Test func eachAccountGetsItsOwnColourSlot() {
        let list = [account("a"), account("b"), account("c")]
        #expect(list.map { Account.badgeIndex(of: $0.id, in: list) } == [0, 1, 2])
        #expect(Account.badgeIndex(of: account("stranger").id, in: list) == 0)
    }

    @Test func gitHubActionsNameTheAccount() {
        #expect(Account.titled("Create Pull Request", as: "maya-acme") == "Create Pull Request as @maya-acme")
        #expect(Account.titled("Create Issue", as: nil) == "Create Issue")
    }
}
