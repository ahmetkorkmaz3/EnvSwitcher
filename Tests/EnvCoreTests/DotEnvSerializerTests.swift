import Testing
@testable import EnvCore

struct DotEnvSerializerTests {
    @Test func writesPlainValuesWithoutQuotes() {
        let text = DotEnvSerializer.serialize([
            DotEnvPair(key: "A", value: "1"),
            DotEnvPair(key: "B", value: "https://x.com/a?b=c"),
        ])
        #expect(text == "A=1\nB=https://x.com/a?b=c\n")
    }

    @Test func writesHeaderAsComments() {
        let text = DotEnvSerializer.serialize([DotEnvPair(key: "A", value: "1")], headerLines: ["h1", "h2"])
        #expect(text == "# h1\n# h2\nA=1\n")
    }

    @Test func quotesValuesThatNeedIt() {
        #expect(DotEnvSerializer.encode("a b") == "\"a b\"")
        #expect(DotEnvSerializer.encode("x#y") == "\"x#y\"")
        #expect(DotEnvSerializer.encode("multi\nline") == "\"multi\\nline\"")
        #expect(DotEnvSerializer.encode(#"q"x"#) == #""q\"x""#)
        #expect(DotEnvSerializer.encode(#"c:\path"#) == #""c:\\path""#)
        #expect(DotEnvSerializer.encode("") == "")
    }

    @Test func roundTripsAwkwardValues() {
        let values = [
            "plain", "", "with space", " lead", "trail ", "a#b", "x #y", "q\"uote", "it's",
            "'single'", "back\\slash", "multi\nline", "url=a=b", "tab\there", "\\n literal",
        ]
        let pairs = values.enumerated().map { DotEnvPair(key: "K\($0.offset)", value: $0.element) }
        let text = DotEnvSerializer.serialize(pairs, headerLines: ["header"])
        #expect(DotEnvParser.parse(text).pairs == pairs)
    }
}
