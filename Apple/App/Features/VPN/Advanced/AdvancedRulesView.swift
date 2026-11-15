import SwiftUI
import VPNProfile

/// Ordered rules; the first match wins.
struct AdvancedRulesView: View {
    @ObservedObject var model: AdvancedVPNModel
    @State private var kind = AdvancedRule.Kind.domainSuffix
    @State private var value = ""
    @State private var action = AdvancedRule.Action.direct

    var body: some View {
        Form {
            Section {
                ForEach(model.profile.rules) { rule in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(verbatim: rule.value)
                            Text(AdvancedLabels.kind(rule.kind)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(AdvancedLabels.action(rule.action)).foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in model.update { $0.rules.remove(atOffsets: offsets) } }
                .onMove { from, to in model.update { $0.rules.move(fromOffsets: from, toOffset: to) } }
            } header: {
                InfoSectionHeader("Rules, in order") {
                    Text("The first rule that matches decides. What matches none follows “Everything else”. Country rules use the country database below.")
                }
            }
            newRuleSection
            AdvancedGeoIPSection(model: model)
            if !skipped.isEmpty {
                Section { Text("\(skipped.count) country rules are not used.").foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .screenTitle("Rules")
    }

    private var skipped: [AdvancedRule] {
        AdvancedXrayConfiguration.skippedRules(model.profile)
    }

    private var newRuleSection: some View {
        Section("New rule") {
            Picker("Type", selection: $kind) {
                ForEach(AdvancedRule.Kind.allCases, id: \.self) { Text(AdvancedLabels.kind($0)).tag($0) }
            }
            TextField("Value", text: $value)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            Picker("Action", selection: $action) {
                ForEach(AdvancedRule.Action.allCases, id: \.self) { Text(AdvancedLabels.action($0)).tag($0) }
            }
            Button("Add rule") {
                model.update { $0.rules.append(AdvancedRule(kind: kind, value: value.trimmingCharacters(in: .whitespaces), action: action)) }
                value = ""
                if !model.missingCountries.isEmpty { Task { await model.refreshGeoIP() } }
            }
            .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
