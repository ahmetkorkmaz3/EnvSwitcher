import Testing
@testable import EnvCore

struct DotEnvParserTests {
    private func pairs(_ text: String) -> [DotEnvPair] { DotEnvParser.parse(text).pairs }
    private func pair(_ key: String, _ value: String) -> DotEnvPair { DotEnvPair(key: key, value: value) }

    @Test func readsSimplePairs() {
        #expect(pairs("A=1\nB=two\n") == [pair("A", "1"), pair("B", "two")])
    }

    @Test func readsExportPrefix() {
        #expect(pairs("export A=1") == [pair("A", "1")])
    }

    @Test func skipsCommentsAndBlankLines() {
        #expect(pairs("# comment\n\n   # indented\nA=1") == [pair("A", "1")])
    }

    @Test func keepsEqualsSignsInValue() {
        #expect(pairs("URL=a=b") == [pair("URL", "a=b")])
    }

    @Test func readsEmptyValue() {
        #expect(pairs("A=") == [pair("A", "")])
    }

    @Test func trimsSpacesAroundKeyAndValue() {
        #expect(pairs("  A =  1  ") == [pair("A", "1")])
    }

    @Test func stripsInlineCommentAfterWhitespace() {
        #expect(pairs("A=value # note") == [pair("A", "value")])
        #expect(pairs("A= # only comment") == [pair("A", "")])
    }

    @Test func keepsHashWithoutLeadingWhitespace() {
        #expect(pairs("URL=https://a.com/#/b") == [pair("URL", "https://a.com/#/b")])
        #expect(pairs("A=#abc") == [pair("A", "#abc")])
    }

    @Test func singleQuotedValueIsLiteral() {
        #expect(pairs(#"A='x\ny # z'"#) == [pair("A", #"x\ny # z"#)])
    }

    @Test func doubleQuotedValueResolvesEscapes() {
        #expect(pairs(#"A="line1\nline2 \"q\" \\ end""#) == [pair("A", "line1\nline2 \"q\" \\ end")])
    }

    @Test func doubleQuotedValueResolvesCarriageReturn() {
        #expect(pairs(#"A="x\ry""#) == [pair("A", "x\ry")])
    }

    @Test func doubleQuotedValueCanSpanLines() {
        #expect(pairs("A=\"first\nsecond\"\nB=2") == [pair("A", "first\nsecond"), pair("B", "2")])
    }

    @Test func reportsUnterminatedQuote() {
        let parsed = DotEnvParser.parse("A=\"open\nB=2")
        #expect(parsed.pairs.isEmpty)
        #expect(parsed.warnings == [.unterminatedQuote(line: 1)])
    }

    @Test func reportsInvalidLines() {
        let parsed = DotEnvParser.parse("not a pair\n1BAD=x\nGOOD=1")
        #expect(parsed.pairs == [pair("GOOD", "1")])
        #expect(parsed.warnings == [.invalidLine(line: 1), .invalidLine(line: 2)])
    }

    @Test func lastDuplicateWinsAndWarns() {
        let parsed = DotEnvParser.parse("A=1\nB=2\nA=3")
        #expect(parsed.pairs == [pair("A", "3"), pair("B", "2")])
        #expect(parsed.warnings == [.duplicateKey(key: "A", line: 3)])
    }

    @Test func handlesWindowsLineEndings() {
        #expect(pairs("A=1\r\nB=2\r\n") == [pair("A", "1"), pair("B", "2")])
    }

    @Test func ignoresByteOrderMark() {
        #expect(pairs("\u{FEFF}A=1\nB=2") == [pair("A", "1"), pair("B", "2")])
    }

    @Test func acceptsDotsAndDashesInKeys() {
        #expect(pairs("my.key-1=x") == [pair("my.key-1", "x")])
    }

    @Test func validatesKeys() {
        #expect(DotEnvParser.isValidKey("NEXT_PUBLIC_API"))
        #expect(DotEnvParser.isValidKey("_x"))
        #expect(!DotEnvParser.isValidKey("1A"))
        #expect(!DotEnvParser.isValidKey(""))
        #expect(!DotEnvParser.isValidKey("A B"))
        #expect(!DotEnvParser.isValidKey("ÇOK"))
    }
}
