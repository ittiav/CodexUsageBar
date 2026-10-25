import Foundation

var count = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    count += 1
}
func parse(_ json: String) throws -> UsageSnapshot {
    try ClaudeUsageParser.snapshot(from: JSONSerialization.jsonObject(with: Data(json.utf8)), now: 1_800_000_000)
}
func rejects(_ json: String, _ name: String) {
    do { _ = try parse(json); fatalError("Accepted invalid data: \(name)") }
    catch { count += 1 }
}
check(UsageProvider(bundleIdentifier: "com.openai.codex") == .codex, "Codex identity")
check(UsageProvider(bundleIdentifier: "com.anthropic.claudefordesktop") == .claude, "Claude identity")
check(UsageProvider(bundleIdentifier: "com.google.Chrome") == nil, "Unrelated apps stay hidden")
check(UsageProvider(bundleIdentifier: nil) == nil, "Unknown frontmost app stays hidden")
check(UsageProvider.codex.cacheKey != UsageProvider.claude.cacheKey, "Provider caches are separate")
let full = try parse(#"{"five_hour":{"utilization":23.5,"resets_at":"2027-01-15T08:00:00Z"},"seven_day":{"utilization":41.2,"resets_at":"2027-01-18T08:00:00.123Z"}}"#)
check(full.fiveHour?.usedPercent == 23.5 && full.weekly?.usedPercent == 41.2, "Preserve fractional percentages")
check(full.fiveHour?.resetsAt != nil && full.weekly?.resetsAt != nil, "Both ISO date formats")
let partial = try parse(#"{"five_hour":{"utilization":0,"resets_at":1800000500},"seven_day":null}"#)
check(partial.fiveHour?.usedPercent == 0, "Zero used is real data")
check(partial.weekly == nil, "Missing weekly data is not 100% remaining")
let weekly = try parse(#"{"seven_day":{"utilization":100}}"#)
check(weekly.fiveHour == nil && weekly.weekly?.usedPercent == 100, "Weekly-only account")
check(weekly.weekly?.resetsAt == nil, "Unknown reset is kept unknown")
rejects(#"{"five_hour":{"utilization":true}}"#, "Boolean percentage")
rejects(#"{"five_hour":{"utilization":-1}}"#, "Negative percentage")
rejects(#"{"five_hour":{"utilization":101}}"#, "Over 100 percentage")
rejects(#"{"five_hour":{"utilization":"23"}}"#, "String percentage")
rejects(#"{"five_hour":{"utilization":23,"resets_at":"invalid"}}"#, "Invalid reset")
rejects(#"{"five_hour":{"utilization":23,"resets_at":true}}"#, "Boolean reset")
rejects(#"{"five_hour":{"utilization":23,"resets_at":-1}}"#, "Negative reset")
rejects(#"{"error":"not authenticated"}"#, "Service error is not quota")
rejects(#"{"context_window":{"used_percentage":24}}"#, "Context occupancy is not plan quota")
rejects(#"{"five_hour":null,"seven_day":null}"#, "No available windows")
rejects(#"[]"#, "Unexpected response shape")
let oldCodex = Data(#"{"fiveHour":{"usedPercent":18,"resetsAt":1800000000},"weekly":{"usedPercent":3,"resetsAt":1800001000},"fetchedAt":1800000000}"#.utf8)
let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: oldCodex)
check(decoded.fiveHour?.usedPercent == 18, "Read existing Codex integer cache")
check(decoded.canUseCache(at: 1_800_000_030), "Recent cache")
check(!decoded.canUseCache(at: 1_800_100_000), "Old cache expires")
check(!decoded.canUseCache(at: 1_799_900_000), "Future cache rejected")
for host in ["claude.ai", "accounts.google.com", "appleid.apple.com", "auth.claude.com"] {
    check(ClaudeNavigationPolicy.allowsEmbeddedNavigation(to: URL(string: "https://\(host)/login")!), "Known auth host")
}
for raw in ["http://claude.ai/login", "https://claude.ai.evil.example/login", "file:///tmp/login", "javascript:alert(1)", "https://user:password@claude.ai/login", "https://localhost/login"] {
    check(!ClaudeNavigationPolicy.allowsEmbeddedNavigation(to: URL(string: raw)!), "Reject unsupported navigation")
}
print("\(count) usage model and navigation checks passed")
