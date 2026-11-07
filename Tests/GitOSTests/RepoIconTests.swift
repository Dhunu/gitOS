import Foundation
import Testing
@testable import GitOS

@Suite struct RepoIconTests {
    private let base = URL(string: "https://example.com/docs/index.html")!

    @Test func findsIconLinksAndResolvesRelativePaths() {
        let html = """
        <html><head>
        <link rel="stylesheet" href="/style.css">
        <LINK REL="ICON" HREF="/favicon-32.png" sizes="32x32">
        <link rel='shortcut icon' href='images/fav.ico'>
        </head></html>
        """
        let urls = RepoIconLoader.iconLinks(inHTML: html, base: base)
        #expect(urls == [URL(string: "https://example.com/favicon-32.png")!,
                         URL(string: "https://example.com/docs/images/fav.ico")!])
    }

    @Test func prefersAppleTouchIconAndSkipsJunk() {
        let html = """
        <link rel="icon" href="data:image/png;base64,AAAA">
        <link rel="icon" href="">
        <link rel="mask-icon" href="/mask.svg" color="#000">
        <link rel="icon" href="/small.png">
        <link rel="apple-touch-icon" href="/touch.png">
        <link rel="apple-touch-icon" href="/touch.png">
        """
        let urls = RepoIconLoader.iconLinks(inHTML: html, base: base)
        #expect(urls == [URL(string: "https://example.com/touch.png")!,
                         URL(string: "https://example.com/small.png")!])
    }

    @Test func readsUnquotedAttributes() {
        let html = "<link rel=icon href=/fav.png>"
        let urls = RepoIconLoader.iconLinks(inHTML: html, base: base)
        #expect(urls == [URL(string: "https://example.com/fav.png")!])
    }
}
