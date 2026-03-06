// Copyright 2023–2025 Skip
import SwiftUI
#if canImport(SkipKeychain)
import SkipKeychain
#endif

struct KeychainPlayground: View {
#if canImport(SkipKeychain)
    @State var allKeys: [String] = []

    var body: some View {
        List {
            Section {
                ForEach(allKeys, id: \.self) { key in
                    NavigationLink {
                        KeychainValueEditor(key: key, isNewKey: false)
                    } label: {
                        Text(key)
                    }
                }
                .onDelete { indices in
                    for keyIndex in indices {
                        try? Keychain.shared.removeValue(forKey: allKeys[keyIndex])
                    }
                    loadKeys()
                }
            }

            Section {
                NavigationLink {
                    KeychainValueEditor(key: "", isNewKey: true)
                } label: {
                    Text("New Key")
                }
            }
        }
        .onAppear {
            loadKeys()
        }
    }

    /// load all the keys from the keychain
    func loadKeys() {
        allKeys = ((try? Keychain.shared.keys()) ?? []).sorted()
    }
#else
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "key")
                .font(.largeTitle)
            Text("Requires SkipKeychain")
                .font(.title2)
            Text("Add skip-keychain dependency to enable keychain operations.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
#endif
}

#if canImport(SkipKeychain)
struct KeychainValueEditor: View {
    @State var key: String
    let isNewKey: Bool
    @State var value = ""
    @State var keychainResult = ""

    var body: some View {
        VStack {
            Form {
                TextField("Key", text: $key)
                    .disabled(!isNewKey || !value.isEmpty)

                TextField("Keychain value", text: $value)
                    .disabled(key.isEmpty)
                    .onChange(of: value) { oldValue, newValue in
                        saveToKeychain()
                    }
            }

            Divider()
            Text(keychainResult)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            loadFromKeychain()
        }
        .navigationTitle("Key: \(key)")
    }

    func saveToKeychain() {
        do {
            try Keychain.shared.set(value, forKey: key, access: .unlocked)
            keychainResult = "Saved to keychain: \(key)=\(value)"
        } catch {
            keychainResult = "Error: \(error)"
        }
    }

    func loadFromKeychain() {
        if key.isEmpty {
            return
        }
        do {
            try value = Keychain.shared.string(forKey: key) ?? ""
            keychainResult = "Loaded from keychain"
        } catch {
            keychainResult = "Error: \(error)"
        }
    }
}
#endif
