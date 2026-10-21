import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct JonesAccountAggregateTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func visible(
        _ alias: String,
        email: String? = nil,
        workspace: String? = "workspace") -> CodexVisibleAccount
    {
        CodexVisibleAccount(
            id: alias,
            email: email ?? "\(alias)@example.test",
            workspaceAccountID: workspace,
            storedAccountID: nil,
            selectionSource: .profileHome(path: "/synthetic/\(alias)"),
            isActive: alias == "malcolm",
            isLive: false,
            canReauthenticate: false,
            canRemove: false)
    }

    private func projection(
        _ accounts: [CodexVisibleAccount],
        aliases: [String] = JonesAccountAggregate.codexAliases) -> CodexVisibleAccountProjection
    {
        CodexVisibleAccountProjection(
            visibleAccounts: accounts,
            activeVisibleAccountID: accounts.first?.id,
            liveVisibleAccountID: nil,
            hasUnreadableAddedAccountStore: false,
            fleetProfileHomePaths: aliases.map { "/synthetic/\($0)" })
    }

    private func row(
        _ alias: String,
        remaining: Double? = 50,
        provider: UsageProvider = .codex,
        error: String? = nil,
        email: String? = nil,
        accountID: String? = nil,
        organization: String? = nil,
        tertiaryRemaining: Double? = nil,
        windowMinutes: Int? = 300,
        resetsAt: Date? = nil,
        secondary: RateWindow? = nil) -> ProviderAccountUsageSnapshot
    {
        ProviderAccountUsageSnapshot(
            id: ProviderAccountIdentity(
                source: provider == .codex ? "codex-account" : "claude-native-profile",
                opaqueID: alias),
            provider: provider,
            displayLabel: "Display label only",
            isActive: false,
            snapshot: remaining.map {
                UsageSnapshot(
                    primary: RateWindow(
                        usedPercent: 100 - $0,
                        windowMinutes: windowMinutes,
                        resetsAt: resetsAt,
                        resetDescription: nil),
                    secondary: secondary,
                    tertiary: tertiaryRemaining.map {
                        RateWindow(usedPercent: 100 - $0, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
                    },
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    identity: ProviderIdentitySnapshot(
                        providerID: provider.instanceID,
                        accountEmail: email,
                        accountOrganization: organization,
                        loginMethod: nil,
                        accountID: accountID))
            },
            error: error,
            sourceLabel: "Synthetic")
    }

    @Test
    func `selected Codex sample sums displayed headroom over fixed denominator`() throws {
        let aliases = JonesAccountAggregate.codexAliases
        let projection = self.projection(aliases.map { self.visible($0) })
        let rows = zip(aliases, [98.0, 59, 97, 24, 79]).map { self.row($0, remaining: $1) }
        let total = try #require(JonesAccountAggregate.codex(projection: projection, accounts: rows))
        #expect(total.summedRemainingPercent == 357)
        #expect(total.maximumPercent == 500)
        #expect(total.normalizedPercent == 71.4)
        #expect(total.reportingCount == 5)
        #expect(!total.isPartial)
        #expect(total.detailLabel.contains("357% / 500%"))
    }

    @Test(arguments: [true, false])
    func `missing or failed retained Umesh snapshot remains an unknown selected slot`(retainedError: Bool) throws {
        let aliases = JonesAccountAggregate.codexAliases
        let projection = self.projection(aliases.map { self.visible($0) })
        var rows = zip(aliases, [98.0, 59, 97, 24, 79]).map { self.row($0, remaining: $1) }
        if retainedError {
            rows[2] = self.row("umich", remaining: 97, error: "Unavailable")
        } else {
            rows.remove(at: 2)
        }
        let total = try #require(JonesAccountAggregate.codex(projection: projection, accounts: rows))
        #expect(total.summedRemainingPercent == 260)
        #expect(total.maximumPercent == 500)
        #expect(total.normalizedPercent == 52)
        #expect(total.reportingCount == 4)
        #expect(total.normalizedLabel == "≥52%")
        #expect(total.detailLabel.contains("≥260% / 500%"))
        #expect(total.accessibilityText.contains("At least"))
    }

    @Test
    func `extra enrollment and default duplicate cannot inflate selected capacity`() throws {
        let aliases = JonesAccountAggregate.codexAliases + ["extra", "default"]
        let accounts = aliases.map { self.visible($0) }
        let rows = aliases.map { self.row($0, remaining: 100) }
        let total = try #require(JonesAccountAggregate.codex(
            projection: self.projection(accounts, aliases: aliases), accounts: rows))
        #expect(total.selectedCount == 5)
        #expect(total.reportingCount == 5)
        #expect(total.summedRemainingPercent == 500)
        #expect(JonesAccountAggregate.codex(
            projection: self.projection(accounts, aliases: ["extra", "default"]), accounts: rows) == nil)
    }

    @Test
    func `selected duplicate credentials count once while different email seats remain distinct`() throws {
        let accounts = [
            self.visible("malcolm", email: " SAME@example.test ", workspace: " SHARED "),
            self.visible("jace", email: "same@example.test", workspace: "shared"),
            self.visible("umich", email: "other@example.test", workspace: "shared"),
        ]
        let total = try #require(JonesAccountAggregate.codex(
            projection: self.projection(accounts),
            accounts: accounts.map { self.row($0.id, remaining: 80) }))
        #expect(total.reportingCount == 2)
        #expect(total.summedRemainingPercent == 160)
        #expect(total.maximumPercent == 500)
    }

    @Test
    func `missing identity enrollment row and loading never become confirmed zero`() throws {
        let accounts = [self.visible("malcolm", workspace: nil), self.visible("jace")]
        let total = try #require(JonesAccountAggregate.codex(
            projection: self.projection(accounts),
            accounts: [self.row("malcolm"), self.row("jace", remaining: nil)]))
        #expect(total.reportingCount == 0)
        #expect(total.normalizedPercent == nil)
        #expect(total.normalizedLabel == "Unavailable")
        #expect(!total.detailLabel.contains("0%"))
        #expect(JonesAccountAggregate.codex(projection: self.projection(accounts, aliases: []), accounts: []) == nil)
    }

    @Test
    func `rounding and tertiary constraint match compact account rows`() throws {
        let account = self.visible("malcolm")
        let row = self.row("malcolm", remaining: 98.9, tertiaryRemaining: 24.6)
        let total = try #require(JonesAccountAggregate.codex(
            projection: self.projection([account]), accounts: [row]))
        let headroom = try #require(AccountMenuLayoutPlanner.headroomPercent(for: row))
        #expect(total.summedRemainingPercent == Int(headroom.rounded()))
        #expect(total.summedRemainingPercent == 25)
        #expect(total.normalizedPercent == 5)
    }

    @Test
    func `Claude uses account identity before email fallback with fixed two account denominator`() throws {
        let rows = [
            self.row("default", remaining: 90, provider: .claude, email: "same@example.test", accountID: "one"),
            self.row("jace", remaining: 60, provider: .claude, email: "same@example.test", accountID: "two"),
            self.row("extra", remaining: 100, provider: .claude, accountID: "extra"),
        ]
        let total = try #require(JonesAccountAggregate.claude(
            enrolledAliases: ["default", "jace", "extra"], accounts: rows))
        #expect(total.maximumPercent == 200)
        #expect(total.summedRemainingPercent == 150)
        #expect(total.normalizedPercent == 75)
        #expect(total.reportingCount == 2)
        let loading = try #require(JonesAccountAggregate.claude(
            enrolledAliases: ["default", "jace"], accounts: rows, refreshingAliases: ["jace"]))
        #expect(loading.reportingCount == 1)
        #expect(loading.normalizedPercent == 45)
        #expect(loading.heightFingerprint != total.heightFingerprint)
    }

    @Test
    func `Claude mixed account ID and email fallback for one account count once`() throws {
        let total = try #require(JonesAccountAggregate.claude(
            enrolledAliases: ["default", "jace"],
            accounts: [
                self.row("default", remaining: 90, provider: .claude, email: "SAME@example.test", accountID: "one"),
                self.row("jace", remaining: 60, provider: .claude, email: "same@example.test"),
            ]))
        #expect(total.reportingCount == 1)
        #expect(total.summedRemainingPercent == 90)
        #expect(total.maximumPercent == 200)
    }

    @Test
    func `Claude fallback normalizes email and organization and excludes retained errors`() throws {
        let rows = [
            self.row("default", remaining: 90, provider: .claude, email: " SAME@example.test ", organization: " ORG "),
            self.row("jace", remaining: 60, provider: .claude, email: "same@example.test", organization: "org"),
        ]
        let total = try #require(JonesAccountAggregate.claude(enrolledAliases: ["default", "jace"], accounts: rows))
        #expect(total.reportingCount == 1)
        #expect(total.summedRemainingPercent == 90)
        let unavailable = try #require(JonesAccountAggregate.claude(
            enrolledAliases: ["default", "jace"],
            accounts: [
                self.row("default", provider: .claude),
                self.row("jace", provider: .claude, error: "Unavailable", accountID: "known"),
            ]))
        #expect(unavailable.normalizedPercent == nil)
        #expect(unavailable.maximumPercent == 200)
    }

    @Test
    func `complete Codex weekly targets sum to 400 of 500 without changing actual totals`() throws {
        let aliases = JonesAccountAggregate.codexAliases
        let rows = zip(aliases, [98.0, 59, 97, 24, 79]).map {
            self.row(
                $0,
                remaining: $1,
                windowMinutes: 10080,
                resetsAt: Self.now.addingTimeInterval(10080 * 60 * 0.8))
        }
        let total = try #require(JonesAccountAggregate.codex(
            projection: self.projection(aliases.map { self.visible($0) }), accounts: rows, now: Self.now))
        #expect(total.summedRemainingPercent == 357)
        #expect(total.paceTargetPercent == 400)
        #expect(total.paceMarkerPercent == 80)
        #expect(total.accessibilityText.contains("On-pace target 400 of 500 percent"))
        #expect(total.countLabel == "5 accounts")
        #expect(total.remainingLabel == "357% / 500%")
    }

    @Test
    func `Claude target sums account schedules over the fixed two slot capacity`() throws {
        let rows = ["default", "jace"].map {
            self.row(
                $0,
                provider: .claude,
                accountID: $0,
                windowMinutes: 10080,
                resetsAt: Self.now.addingTimeInterval(10080 * 60 * 0.75))
        }
        let total = try #require(JonesAccountAggregate.claude(
            enrolledAliases: ["default", "jace"], accounts: rows, now: Self.now))
        #expect(total.paceTargetPercent == 150)
        #expect(total.paceMarkerPercent == 75)
        let refreshing = try #require(JonesAccountAggregate.claude(
            enrolledAliases: ["default", "jace"], accounts: rows, refreshingAliases: ["jace"], now: Self.now))
        #expect(refreshing.paceTargetPercent == nil)
        #expect(refreshing.maximumPercent == 200)
    }

    @Test
    func `mixed limiting windows sum their targets instead of averaging reset times`() throws {
        let aliases = JonesAccountAggregate.codexAliases
        let weekly = RateWindow(
            usedPercent: 10,
            windowMinutes: 10080,
            resetsAt: Self.now.addingTimeInterval(10080 * 60 * 0.8),
            resetDescription: nil)
        let rows = aliases.enumerated().map { index, alias in
            self.row(
                alias,
                remaining: 50,
                windowMinutes: index == 0 ? 300 : 10080,
                resetsAt: Self.now.addingTimeInterval(index == 0 ? 9000 : 10080 * 60 * 0.8),
                secondary: weekly)
        }
        let total = try #require(JonesAccountAggregate.codex(
            projection: self.projection(aliases.map { self.visible($0) }), accounts: rows, now: Self.now))
        #expect(total.paceTargetPercent == 370)
        #expect(total.paceMarkerPercent == 74)
        #expect(total.summedRemainingPercent == 250)
    }

    @Test(arguments: ["missing-reset", "past-reset", "future-reset", "missing-duration", "zero-duration", "credit"])
    func `invalid limiting timing hides pacing without changing actual coverage`(kind: String) throws {
        let aliases = JonesAccountAggregate.codexAliases
        var rows = aliases.map {
            self.row($0, resetsAt: Self.now.addingTimeInterval(9000))
        }
        rows[0] = self.row(
            aliases[0],
            tertiaryRemaining: kind == "credit" ? 20 : nil,
            windowMinutes: kind == "missing-duration" ? nil : kind == "zero-duration" ? 0 : 300,
            resetsAt: kind == "missing-reset" ? nil : Self.now.addingTimeInterval(
                kind == "past-reset" ? -1 : kind == "future-reset" ? 18001 : 9000))
        let total = try #require(JonesAccountAggregate.codex(
            projection: self.projection(aliases.map { self.visible($0) }), accounts: rows, now: Self.now))
        #expect(total.reportingCount == 5)
        #expect(total.maximumPercent == 500)
        #expect(total.paceTargetPercent == nil)
        #expect(total.paceMarkerPercent == nil)
        #expect(total.accessibilityText.contains("Pacing unavailable"))
    }

    @Test(arguments: ["missing", "failed", "duplicate"])
    func `partial or duplicate selected identities cannot produce a target`(kind: String) throws {
        let aliases = JonesAccountAggregate.codexAliases
        var visible = aliases.map { self.visible($0) }
        var rows = aliases.map { self.row($0, resetsAt: Self.now.addingTimeInterval(9000)) }
        if kind == "missing" {
            rows.removeLast()
        } else if kind == "failed" {
            rows[4] = self.row(aliases[4], error: "Unavailable", resetsAt: Self.now.addingTimeInterval(9000))
        } else {
            visible[4] = self.visible(aliases[4], email: visible[0].email)
        }
        let total = try #require(JonesAccountAggregate.codex(
            projection: self.projection(visible), accounts: rows, now: Self.now))
        #expect(total.reportingCount == 4)
        #expect(total.maximumPercent == 500)
        #expect(total.normalizedLabel.hasPrefix("≥"))
        #expect(total.paceTargetPercent == nil)
    }

    @Test(arguments: [false, true])
    func `tied limits use the latest valid reset and planner order for equal resets`(equalReset: Bool) throws {
        let aliases = JonesAccountAggregate.codexAliases
        let reset = Self.now.addingTimeInterval(9000)
        let weekly = RateWindow(
            usedPercent: 50,
            windowMinutes: 10080,
            resetsAt: equalReset ? reset : Self.now.addingTimeInterval(10080 * 60 * 0.8),
            resetDescription: nil)
        let rows = aliases.map {
            self.row($0, resetsAt: reset, secondary: weekly)
        }
        let total = try #require(JonesAccountAggregate.codex(
            projection: self.projection(aliases.map { self.visible($0) }), accounts: rows, now: Self.now))
        #expect(total.paceTargetPercent == (equalReset ? 250 : 400))
        let missingSession = aliases.map { self.row($0, secondary: weekly) }
        let fallback = try #require(JonesAccountAggregate.codex(
            projection: self.projection(aliases.map { self.visible($0) }), accounts: missingSession, now: Self.now))
        #expect(fallback.paceTargetPercent != nil)
    }

    @Test
    func `workday schedule matches UsagePace and time never changes the height fingerprint`() throws {
        let aliases = JonesAccountAggregate.codexAliases
        let reset = Self.now.addingTimeInterval(4 * 86400)
        let rows = aliases.map { self.row($0, windowMinutes: 10080, resetsAt: reset) }
        let projection = self.projection(aliases.map { self.visible($0) })
        let total = try #require(JonesAccountAggregate.codex(
            projection: projection, accounts: rows, now: Self.now, workDays: 5))
        let window = try #require(rows[0].snapshot?.primary)
        let pace = try #require(UsagePace.weekly(
            window: window, now: Self.now, defaultWindowMinutes: 10080, workDays: 5))
        #expect(total.paceTargetPercent == Int((100 - pace.expectedUsedPercent).rounded()) * 5)
        let later = try #require(JonesAccountAggregate.codex(
            projection: projection, accounts: rows, now: Self.now.addingTimeInterval(86400), workDays: 5))
        let expired = try #require(JonesAccountAggregate.codex(
            projection: projection, accounts: rows, now: reset, workDays: 5))
        #expect(total.heightFingerprint == later.heightFingerprint)
        #expect(total.heightFingerprint == expired.heightFingerprint)
        #expect(expired.paceTargetPercent == nil)
    }

    @Test(arguments: [(340, 20), (285, -35), (320, 0)])
    func `balance uses raw capacity points and strict sign tones`(remaining: Int, balance: Int) throws {
        let aliases = JonesAccountAggregate.codexAliases
        let rows = aliases.enumerated().map { index, alias in
            self.row(
                alias,
                remaining: Double(remaining / 5 + (index < remaining % 5 ? 1 : 0)),
                resetsAt: Self.now.addingTimeInterval(18000 * 0.64))
        }
        let total = try #require(JonesAccountAggregate.codex(
            projection: self.projection(aliases.map { self.visible($0) }), accounts: rows, now: Self.now))
        #expect(total.paceTargetPercent == 320)
        #expect(total.balancePoints == balance)
        #expect(total.balanceTone == (balance > 0 ? .reserve : balance < 0 ? .deficit : .neutral))
        #expect(total.expandedLines.first?.tone == total.balanceTone)
        #expect(total.accessibilityText(isExpanded: true).contains("\(balance) percentage points of 500"))
        if balance == 20 {
            #expect(total.expandedLines.first?.text == "Reserve +20% (of 500%)")
        }
    }

    @Test
    func `verified Claude UUID seats contribute 155 of 200 without identity disclosure`() throws {
        let rows = [
            self.row(
                "default",
                remaining: 65,
                provider: .claude,
                email: "secret@example.test",
                accountID: "00000000-0000-0000-0000-000000000001",
                resetsAt: Self.now.addingTimeInterval(18000 * 0.72)),
            self.row(
                "jace",
                remaining: 90,
                provider: .claude,
                email: "secret@example.test",
                accountID: "00000000-0000-0000-0000-000000000002",
                resetsAt: Self.now.addingTimeInterval(18000 * 0.60)),
        ]
        let total = try #require(JonesAccountAggregate.claude(
            enrolledAliases: ["default", "jace"], accounts: rows, now: Self.now))
        #expect(total.summedRemainingPercent == 155)
        #expect(total.maximumPercent == 200)
        #expect(total.balancePoints == 23)
        let text = total.accessibilityText(isExpanded: true)
        #expect(!text.contains("secret@"))
        #expect(!text.contains("00000000-"))
        let duplicate = self.row(
            "jace",
            remaining: 90,
            provider: .claude,
            accountID: "00000000-0000-0000-0000-000000000001")
        let partial = try #require(JonesAccountAggregate.claude(
            enrolledAliases: ["default", "jace"], accounts: [rows[0], duplicate], now: Self.now))
        #expect(partial.reportingCount == 1)
        #expect(partial.balancePoints == nil)
        #expect(partial.exhaustion == .unknown(.partialRoster))
    }

    @Test(arguments: [20.0, 80.0])
    func `pooled forecast distinguishes before first reset from ignored refills`(remaining: Double) throws {
        let aliases = JonesAccountAggregate.codexAliases
        let rows = aliases.map { self.row($0, remaining: remaining, resetsAt: Self.now.addingTimeInterval(9000)) }
        let total = try #require(JonesAccountAggregate.codex(
            projection: self.projection(aliases.map { self.visible($0) }), accounts: rows, now: Self.now))
        guard case let .runsOut(date, beforeFirstReset) = total.exhaustion else {
            Issue.record("Expected pooled forecast")
            return
        }
        #expect(abs(date.timeIntervalSince(Self.now) - remaining / (100 - remaining) * 9000) < 0.001)
        #expect(beforeFirstReset == (remaining == 20))
        #expect(total.expandedLines.contains { $0.text == "Estimate ignores refills" } == (remaining == 80))
        #expect(total.expandedLines.contains { $0.text == "Assumes demand moves across accounts" })
    }

    @Test(arguments: ["zero-activity", "all-zero", "too-early", "missing-timing", "partial"])
    func `forecast handles unavailable and boundary states`(kind: String) throws {
        let aliases = JonesAccountAggregate.codexAliases
        var rows = aliases.map {
            self.row(
                $0,
                remaining: kind == "zero-activity" ? 100 : kind == "all-zero" ? 0 : 50,
                resetsAt: Self.now.addingTimeInterval(kind == "too-early" ? 17900 : 9000))
        }
        if kind == "missing-timing" { rows[0] = self.row(aliases[0]) }
        if kind == "partial" { rows.removeLast() }
        let total = try #require(JonesAccountAggregate.codex(
            projection: self.projection(aliases.map { self.visible($0) }), accounts: rows, now: Self.now))
        let expected: JonesAccountAggregate.Exhaustion = switch kind {
        case "zero-activity": .noUsage
        case "all-zero": .exhaustedNow
        case "too-early": .unknown(.tooEarly)
        case "partial": .unknown(.partialRoster)
        default: .unknown(.missingTiming)
        }
        #expect(total.exhaustion == expected)
        if kind == "missing-timing" || kind == "partial" { #expect(total.balancePoints == nil) }
    }

    @Test
    func `exhausted accounts still contribute demand to pooled rate`() throws {
        let aliases = JonesAccountAggregate.codexAliases
        let rows = aliases.enumerated().map { index, alias in
            self.row(alias, remaining: index == 0 ? 0 : 80, resetsAt: Self.now.addingTimeInterval(9000))
        }
        let total = try #require(JonesAccountAggregate.codex(
            projection: self.projection(aliases.map { self.visible($0) }), accounts: rows, now: Self.now))
        guard case let .runsOut(date, _) = total.exhaustion else {
            Issue.record("Expected pooled forecast")
            return
        }
        #expect(abs(date.timeIntervalSince(Self.now) - 320 / (180.0 / 9000)) < 0.001)
    }

    @Test
    func `workday forecast skips weekend and mixed windows use wall clock`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-16T12:00:00Z"))
        let reset = now.addingTimeInterval(4.5 * 86400)
        let aliases = JonesAccountAggregate.codexAliases
        let rows = aliases.map { self.row($0, remaining: 30, windowMinutes: 10080, resetsAt: reset) }
        let total = try #require(JonesAccountAggregate.codex(
            projection: self.projection(aliases.map { self.visible($0) }),
            accounts: rows,
            now: now,
            workDays: 5,
            calendar: calendar))
        guard case let .runsOut(date, _) = total.exhaustion else {
            Issue.record("Expected workday forecast")
            return
        }
        #expect(calendar.component(.weekday, from: date) == 2)
        var mixed = rows
        mixed[0] = self.row(aliases[0], remaining: 30, windowMinutes: 300, resetsAt: now.addingTimeInterval(9000))
        let mixedTotal = try #require(JonesAccountAggregate.codex(
            projection: self.projection(aliases.map { self.visible($0) }),
            accounts: mixed,
            now: now,
            workDays: 5,
            calendar: calendar))
        guard case let .runsOut(mixedDate, _) = mixedTotal.exhaustion else {
            Issue.record("Expected mixed-clock forecast")
            return
        }
        let rate = 70 / 9000.0 + 4 * 70 / (2.5 * 86400)
        #expect(abs(mixedDate.timeIntervalSince(now) - 150 / rate) < 0.001)
    }

    @Test
    func `expanded fingerprint records line shapes but no dates or identities`() {
        var total = JonesAccountAggregate(
            selectedCount: 5,
            reportingCount: 5,
            summedRemainingPercent: 340,
            paceTargetPercent: 320,
            exhaustion: .runsOut(at: Self.now, beforeFirstReset: false),
            firstReset: Self.now)
        let expanded = total.heightFingerprint(isExpanded: true)
        #expect(expanded != total.heightFingerprint(isExpanded: false))
        total.firstReset = Self.now.addingTimeInterval(60)
        total.exhaustion = .runsOut(at: Self.now.addingTimeInterval(60), beforeFirstReset: false)
        #expect(total.heightFingerprint(isExpanded: true) == expanded)
        total.exhaustion = .noUsage
        #expect(total.heightFingerprint(isExpanded: true) != expanded)
        total.paceTargetPercent = nil
        #expect(total.heightFingerprint(isExpanded: true).contains("bal=false"))
    }

    @Test(arguments: [
        ("2026-07-01T16:00:00Z", "Wed Jul 1 12:00 PM EDT"),
        ("2026-01-01T17:00:00Z", "Thu Jan 1 12:00 PM EST")
    ])
    func `aggregate dates use Eastern seasonal abbreviations`(input: String, expected: String) throws {
        let date = try #require(ISO8601DateFormatter().date(from: input))
        #expect(JonesAccountAggregate.easternDateLabel(date) == expected)
    }
}
