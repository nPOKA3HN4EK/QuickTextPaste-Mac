import SwiftUI

/// Список пунктов вместо строк MenuName: в тексте.
/// В файл пишется тем же текстом с MenuName:, поэтому старые меню и новые списки — одно и то же.
struct ListEditor: View {
    @Binding var text: String
    @State private var rows: [Row]

    struct Row: Identifiable, Equatable {
        let id = UUID()
        var def: MenuDef
    }

    init(text: Binding<String>) {
        _text = text
        // берём из текста один раз; дальше текст пишется только когда ты что-то меняешь
        _rows = State(initialValue: (TextProcessor.parseMenu(text.wrappedValue) ?? []).map { Row(def: $0) })
    }

    var body: some View {
        Group {
            ForEach($rows) { $row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if row.def.isSeparator {
                        Text("──────  разделитель  ──────")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    } else {
                        TextField("Название", text: $row.def.label, prompt: Text("название"))
                            .labelsHidden()
                            .frame(width: 160)
                        TextField("Текст", text: $row.def.text, prompt: Text("что вставить"), axis: .vertical)
                            .labelsHidden()
                            .lineLimit(1...8)
                    }
                    Button { move(row.id, -1) } label: { Image(systemName: "arrow.up") }
                        .disabled(rows.first?.id == row.id)
                        .help("Выше")
                    Button { move(row.id, 1) } label: { Image(systemName: "arrow.down") }
                        .disabled(rows.last?.id == row.id)
                        .help("Ниже")
                    Button { rows.removeAll { $0.id == row.id } } label: { Image(systemName: "minus.circle") }
                        .help("Убрать пункт")
                }
                .buttonStyle(.borderless)
            }
            HStack {
                Button("+ Пункт") {
                    rows.append(Row(def: MenuDef(label: "Пункт \(rows.filter { !$0.def.isSeparator }.count + 1)", text: "")))
                }
                Button("+ Разделитель") { rows.append(Row(def: MenuDef(label: "", text: "", isSeparator: true))) }
                Spacer()
            }
            Text("По горячей клавише или сокращению откроется меню из этих пунктов. В тексте пункта работают все команды, и `---` для случайного варианта тоже.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: rows) { _, new in text = TextProcessor.menuText(new.map(\.def)) }
    }

    private func move(_ id: UUID, _ d: Int) {
        guard let i = rows.firstIndex(where: { $0.id == id }), rows.indices.contains(i + d) else { return }
        rows.swapAt(i, i + d)
    }
}
