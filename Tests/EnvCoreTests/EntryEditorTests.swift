import Foundation
import Testing
@testable import EnvCore

struct EntryEditorTests {
    private func setUp() throws -> (ProjectFixture, EntryEditor) {
        var f = try ProjectFixture()
        f.setEntries([EnvEntry(key: "A", value: "1"), EnvEntry(key: "TOKEN", value: nil, isSecret: true)], target: f.cart, env: f.local)
        try f.secrets.write("t0", account: f.account(f.cart, f.local, "TOKEN"))
        return (f, EntryEditor(secrets: f.secrets))
    }

    @Test func readsPlainAndSecretValues() throws {
        let (f, editor) = try setUp()
        #expect(try editor.readValue(key: "A", in: f.project, targetId: f.cart.id, environmentId: f.local) == "1")
        #expect(try editor.readValue(key: "TOKEN", in: f.project, targetId: f.cart.id, environmentId: f.local) == "t0")
        #expect(throws: EntryEditor.EditError.unknownKey("X")) {
            try editor.readValue(key: "X", in: f.project, targetId: f.cart.id, environmentId: f.local)
        }
    }

    @Test func addsEntryAtEndAndRejectsDuplicateOrInvalidKey() throws {
        let (f, editor) = try setUp()
        let p = try editor.addEntry(key: "B", in: f.project, targetId: f.cart.id, environmentId: f.local)
        #expect(p.targets[0].entries(for: f.local).map(\.key) == ["A", "TOKEN", "B"])
        #expect(p.targets[0].entries(for: f.local).last == EnvEntry(key: "B", value: ""))
        #expect(throws: EntryEditor.EditError.duplicateKey("A")) {
            try editor.addEntry(key: "A", in: f.project, targetId: f.cart.id, environmentId: f.local)
        }
        #expect(throws: EntryEditor.EditError.invalidKey("1X")) {
            try editor.addEntry(key: "1X", in: f.project, targetId: f.cart.id, environmentId: f.local)
        }
    }

    @Test func setValueWritesPlainToStoreAndSecretToSecretStore() throws {
        let (f, editor) = try setUp()
        var p = try editor.setValue("2", key: "A", in: f.project, targetId: f.cart.id, environmentId: f.local)
        p = try editor.setValue("t1", key: "TOKEN", in: p, targetId: f.cart.id, environmentId: f.local)
        #expect(p.targets[0].entries(for: f.local) == [EnvEntry(key: "A", value: "2"), EnvEntry(key: "TOKEN", value: nil, isSecret: true)])
        #expect(f.secrets.snapshot[f.account(f.cart, f.local, "TOKEN")] == "t1")
    }

    @Test func setSecretMovesValueBetweenStores() throws {
        let (f, editor) = try setUp()
        var p = try editor.setSecret(true, key: "A", in: f.project, targetId: f.cart.id, environmentId: f.local)
        #expect(p.targets[0].entries(for: f.local)[0] == EnvEntry(key: "A", value: nil, isSecret: true))
        #expect(f.secrets.snapshot[f.account(f.cart, f.local, "A")] == "1")

        p = try editor.setSecret(false, key: "TOKEN", in: p, targetId: f.cart.id, environmentId: f.local)
        #expect(p.targets[0].entries(for: f.local)[1] == EnvEntry(key: "TOKEN", value: "t0"))
        #expect(f.secrets.snapshot[f.account(f.cart, f.local, "TOKEN")] == nil)
    }

    @Test func renameKeyMovesSecretAccount() throws {
        let (f, editor) = try setUp()
        let p = try editor.renameKey("TOKEN", to: "API_TOKEN", in: f.project, targetId: f.cart.id, environmentId: f.local)
        #expect(p.targets[0].entries(for: f.local).map(\.key) == ["A", "API_TOKEN"])
        #expect(f.secrets.snapshot == [f.account(f.cart, f.local, "API_TOKEN"): "t0"])
        #expect(throws: EntryEditor.EditError.duplicateKey("A")) {
            try editor.renameKey("API_TOKEN", to: "A", in: p, targetId: f.cart.id, environmentId: f.local)
        }
    }

    @Test func removeEntryDeletesSecret() throws {
        let (f, editor) = try setUp()
        let p = try editor.removeEntry(key: "TOKEN", in: f.project, targetId: f.cart.id, environmentId: f.local)
        #expect(p.targets[0].entries(for: f.local).map(\.key) == ["A"])
        #expect(f.secrets.snapshot.isEmpty)
    }

    @Test func copyEntriesOverwritesOrSkipsExistingKeys() throws {
        var (f, editor) = try setUp()
        f.setEntries([EnvEntry(key: "A", value: "test-a"), EnvEntry(key: "ONLY_TEST", value: "x")], target: f.cart, env: f.test)

        let skipped = try editor.copyEntries(from: f.local, to: f.test, targetId: f.cart.id, mode: .skipExisting, in: f.project)
        #expect(skipped.targets[0].entries(for: f.test) == [
            EnvEntry(key: "A", value: "test-a"),
            EnvEntry(key: "ONLY_TEST", value: "x"),
            EnvEntry(key: "TOKEN", value: nil, isSecret: true),
        ])
        #expect(f.secrets.snapshot[f.account(f.cart, f.test, "TOKEN")] == "t0")

        let overwritten = try editor.copyEntries(from: f.local, to: f.test, targetId: f.cart.id, mode: .overwrite, in: f.project)
        #expect(overwritten.targets[0].entries(for: f.test)[0] == EnvEntry(key: "A", value: "1"))
    }

    @Test func upsertAddsAMissingPlainKey() throws {
        let (f, editor) = try setUp()
        let p = try editor.upsertValue("2", key: "B", isSecret: false, in: f.project, targetId: f.cart.id, environmentId: f.test)
        #expect(p.targets[0].entries(for: f.test) == [EnvEntry(key: "B", value: "2")])
    }

    @Test func upsertAddsAMissingSecretKeyToTheSecretStore() throws {
        let (f, editor) = try setUp()
        let p = try editor.upsertValue("t1", key: "TOKEN", isSecret: true, in: f.project, targetId: f.cart.id, environmentId: f.test)
        #expect(p.targets[0].entries(for: f.test) == [EnvEntry(key: "TOKEN", value: nil, isSecret: true)])
        #expect(try f.secrets.read(account: f.account(f.cart, f.test, "TOKEN")) == "t1")
    }

    @Test func upsertChangesAnExistingKeyAndKeepsItsSecretFlag() throws {
        let (f, editor) = try setUp()
        var p = try editor.upsertValue("9", key: "A", isSecret: true, in: f.project, targetId: f.cart.id, environmentId: f.local)
        p = try editor.upsertValue("t9", key: "TOKEN", isSecret: false, in: p, targetId: f.cart.id, environmentId: f.local)
        #expect(p.targets[0].entries(for: f.local) == [
            EnvEntry(key: "A", value: "9"),
            EnvEntry(key: "TOKEN", value: nil, isSecret: true),
        ])
        #expect(try f.secrets.read(account: f.account(f.cart, f.local, "TOKEN")) == "t9")
    }

    @Test func upsertRejectsAnInvalidKey() throws {
        let (f, editor) = try setUp()
        #expect(throws: EntryEditor.EditError.invalidKey("1X")) {
            try editor.upsertValue("v", key: "1X", isSecret: false, in: f.project, targetId: f.cart.id, environmentId: f.local)
        }
    }

    @Test func planPasteSortsKeysByWhatChanges() throws {
        var (f, editor) = try setUp()
        f.setEntries([EnvEntry(key: "A", value: "1"), EnvEntry(key: "EMPTY", value: ""), EnvEntry(key: "SAME", value: "s")], target: f.cart, env: f.test)
        let pairs = [
            DotEnvPair(key: "A", value: "2"),
            DotEnvPair(key: "EMPTY", value: "e"),
            DotEnvPair(key: "SAME", value: "s"),
            DotEnvPair(key: "NEW", value: "n"),
        ]
        let plan = try editor.planPaste(pairs, in: f.project, targetId: f.cart.id, environmentId: f.test)
        #expect(plan.added == ["NEW"])
        #expect(plan.filled == ["EMPTY"])
        #expect(plan.conflicts == ["A"])
        #expect(plan.unchanged == ["SAME"])
    }

    @Test func planPasteReadsSecretValues() throws {
        let (f, editor) = try setUp()
        let plan = try editor.planPaste([DotEnvPair(key: "TOKEN", value: "t0")], in: f.project, targetId: f.cart.id, environmentId: f.local)
        #expect(plan.unchanged == ["TOKEN"])
    }

    @Test func pasteSkipExistingFillsEmptyAndAddsMissingOnly() throws {
        var (f, editor) = try setUp()
        f.setEntries([EnvEntry(key: "A", value: "1"), EnvEntry(key: "EMPTY", value: "")], target: f.cart, env: f.test)
        let pairs = [
            DotEnvPair(key: "A", value: "2"),
            DotEnvPair(key: "EMPTY", value: "e"),
            DotEnvPair(key: "NEW", value: "n"),
            DotEnvPair(key: "API_TOKEN", value: "secret"),
        ]
        let p = try editor.pasteEntries(pairs, mode: .skipExisting, in: f.project, targetId: f.cart.id, environmentId: f.test)
        #expect(p.targets[0].entries(for: f.test) == [
            EnvEntry(key: "A", value: "1"),
            EnvEntry(key: "EMPTY", value: "e"),
            EnvEntry(key: "NEW", value: "n"),
            EnvEntry(key: "API_TOKEN", value: nil, isSecret: true),
        ])
        #expect(try f.secrets.read(account: f.account(f.cart, f.test, "API_TOKEN")) == "secret")
    }

    @Test func pasteOverwriteChangesExistingValuesAndKeepsSecretFlag() throws {
        let (f, editor) = try setUp()
        let pairs = [DotEnvPair(key: "A", value: "2"), DotEnvPair(key: "TOKEN", value: "t1")]
        let p = try editor.pasteEntries(pairs, mode: .overwrite, in: f.project, targetId: f.cart.id, environmentId: f.local)
        #expect(p.targets[0].entries(for: f.local) == [
            EnvEntry(key: "A", value: "2"),
            EnvEntry(key: "TOKEN", value: nil, isSecret: true),
        ])
        #expect(try f.secrets.read(account: f.account(f.cart, f.local, "TOKEN")) == "t1")
    }
}
