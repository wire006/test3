//
//  HistoryView.swift
//  DrowsinessWatch Watch App
//
//  居眠り検知の発報履歴を一覧表示する画面。
//

import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: AlertHistoryStore

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm:ss"
        return formatter
    }()

    var body: some View {
        Group {
            if store.records.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "moon.zzz")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("履歴なし")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.records) { record in
                        recordRow(record)
                    }
                    Section {
                        Button(role: .destructive) {
                            store.clear()
                        } label: {
                            Label("履歴を削除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("発報履歴")
    }

    @ViewBuilder
    private func recordRow(_ record: AlertRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Self.timeFormatter.string(from: record.triggeredAt))
                .font(.caption)
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                if let hr = record.heartRate {
                    Label(String(format: "%.0f", hr), systemImage: "heart.fill")
                        .foregroundStyle(.red)
                }
                if let base = record.baselineHeartRate {
                    Text("/ 基\(String(format: "%.0f", base))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption2)

            Text(String(format: "活動 %.3f", record.activityLevel))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    let store = AlertHistoryStore()
    store.append(AlertRecord(
        triggeredAt: Date(),
        heartRate: 58,
        baselineHeartRate: 72,
        activityLevel: 0.018
    ))
    return HistoryView(store: store)
}
