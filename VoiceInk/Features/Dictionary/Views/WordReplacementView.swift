import SwiftData
import SwiftUI

enum SortMode: String {
    case originalAsc = "originalAsc"
    case originalDesc = "originalDesc"
    case replacementAsc = "replacementAsc"
    case replacementDesc = "replacementDesc"
}

enum SortColumn {
    case original
    case replacement
}

enum WordReplacementSorting {
    static func sorted(_ items: [WordReplacement], by mode: SortMode) -> [WordReplacement] {
        let ascending = mode == .originalAsc || mode == .replacementAsc
        let key: (WordReplacement) -> String =
            (mode == .originalAsc || mode == .originalDesc) ? \.originalText : \.replacementText
        return items.sorted {
            let order = key($0).localizedCaseInsensitiveCompare(key($1))
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }
}

struct WordReplacementView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var originalWord = ""
    @State private var replacementWord = ""
    @State private var showInfoPopover = false

    private var shouldShowAddButton: Bool {
        !originalWord.isEmpty || !replacementWord.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("", text: $originalWord, prompt: Text("Original text (use commas for multiple)"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .labelsHidden()

                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                    .font(.system(size: 10))
                    .frame(width: 10)

                TextField("", text: $replacementWord, prompt: Text("Replacement text"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .onSubmit { addReplacement() }
                    .labelsHidden()

                if shouldShowAddButton {
                    AddIconButton(
                        helpText: "Add word replacement",
                        isDisabled: originalWord.isEmpty || replacementWord.isEmpty,
                        action: addReplacement
                    )
                }

                Button {
                    showInfoPopover.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help("Word replacement examples")
                .popover(isPresented: $showInfoPopover) {
                    WordReplacementInfoPopover()
                }
            }
            .animation(.easeInOut(duration: 0.2), value: shouldShowAddButton)

            // The list is a separate view so a keystroke in the fields above cannot
            // invalidate it. Re-sorting every row on every character is what made
            // typing here unusable.
            WordReplacementList()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert("Word Replacement", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func addReplacement() {
        let original = originalWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = replacementWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = (try? modelContext.fetch(FetchDescriptor<WordReplacement>())) ?? []
        if let error = DictionaryService.addWordReplacement(
            original: original, replacement: replacement, existing: existing, context: modelContext)
        {
            alertMessage = error
            showAlert = true
            return
        }
        originalWord = ""
        replacementWord = ""
    }
}

struct WordReplacementList: View {
    @Query private var wordReplacements: [WordReplacement]
    @Environment(\.modelContext) private var modelContext
    @State private var sortMode: SortMode = .originalAsc
    @State private var editingReplacement: WordReplacement? = nil
    @State private var showAlert = false
    @State private var alertMessage = ""

    init() {
        if let savedSort = UserDefaults.standard.string(forKey: "wordReplacementSortMode"),
            let mode = SortMode(rawValue: savedSort)
        {
            _sortMode = State(initialValue: mode)
        }
    }

    private func toggleSort(for column: SortColumn) {
        switch column {
        case .original:
            sortMode = (sortMode == .originalAsc) ? .originalDesc : .originalAsc
        case .replacement:
            sortMode = (sortMode == .replacementAsc) ? .replacementDesc : .replacementAsc
        }
        UserDefaults.standard.set(sortMode.rawValue, forKey: "wordReplacementSortMode")
    }

    var body: some View {
        if !wordReplacements.isEmpty {
            let rows = WordReplacementSorting.sorted(wordReplacements, by: sortMode)
            let lastID = rows.last?.persistentModelID

            VStack(spacing: 0) {
                header

                Divider()

                LazyVStack(spacing: 0) {
                    ForEach(rows, id: \.persistentModelID) { replacement in
                        ReplacementRow(
                            original: replacement.originalText,
                            replacement: replacement.replacementText,
                            onDelete: { removeReplacement(replacement) },
                            onEdit: { editingReplacement = replacement }
                        )

                        if replacement.persistentModelID != lastID {
                            Divider()
                        }
                    }
                }
            }
            .padding(.top, 4)
            .sheet(isPresented: isEditingReplacement) {
                if let editingReplacement {
                    EditReplacementSheet(replacement: editingReplacement, modelContext: modelContext)
                }
            }
            .alert("Word Replacement", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: { toggleSort(for: .original) }) {
                HStack(spacing: 4) {
                    Text("Original")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    if sortMode == .originalAsc || sortMode == .originalDesc {
                        Image(systemName: sortMode == .originalAsc ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help("Sort by original")

            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
                .font(.system(size: 10))
                .frame(width: 10)

            Button(action: { toggleSort(for: .replacement) }) {
                HStack(spacing: 4) {
                    Text("Replacement")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    if sortMode == .replacementAsc || sortMode == .replacementDesc {
                        Image(systemName: sortMode == .replacementAsc ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help("Sort by replacement")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    private func removeReplacement(_ replacement: WordReplacement) {
        modelContext.delete(replacement)

        do {
            try modelContext.save()
        } catch {
            // Rollback the delete to restore UI consistency
            modelContext.rollback()
            alertMessage = String(
                format: String(localized: "Failed to remove replacement: %@"), error.localizedDescription)
            showAlert = true
        }
    }

    private var isEditingReplacement: Binding<Bool> {
        Binding(
            get: { editingReplacement != nil },
            set: { isPresented in
                if !isPresented {
                    editingReplacement = nil
                }
            }
        )
    }
}

struct WordReplacementInfoPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How to use Word Replacements")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Separate multiple originals with commas:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Voicing, Voice ink, Voiceing")
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(6)
            }

            Divider()

            Text("Examples")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Original:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("my website link")
                            .font(.callout)
                    }

                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Replacement:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(verbatim: "https://tryvoiceink.com")
                            .font(.callout)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.textBackgroundColor))
                .cornerRadius(6)

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Original:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Voicing, Voice ink")
                            .font(.callout)
                    }

                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Replacement:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("VoiceInk")
                            .font(.callout)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.textBackgroundColor))
                .cornerRadius(6)
            }
        }
        .padding()
        .frame(width: 380)
    }
}

struct ReplacementRow: View {
    let original: String
    let replacement: String
    let onDelete: () -> Void
    let onEdit: () -> Void
    @State private var isEditHovered = false
    @State private var isDeleteHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(original)
                .font(.system(size: 13))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
                .font(.system(size: 10))
                .frame(width: 10)

            ZStack(alignment: .trailing) {
                Text(replacement)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 50)

                HStack(spacing: 6) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(isEditHovered ? AppTheme.Accent.primary : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.borderless)
                    .help("Edit replacement")
                    .onHover { hover in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditHovered = hover
                        }
                    }

                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(isDeleteHovered ? AppTheme.Status.error : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.borderless)
                    .help("Remove replacement")
                    .onHover { hover in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isDeleteHovered = hover
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}
