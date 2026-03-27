//
//  DictionaryRepository.swift
//  W5-03 / W5-07
//

import Combine
import Foundation
import GRDB
import SwiftUI

final class DictionaryRepository: ObservableObject {
    @Published var entries: [DictionaryRecord] = []

    func load() {
        Task { await loadAsync() }
    }

    private func loadAsync() async {
        guard let pool = try? AppDatabase.shared.dbPool else { return }
        let items = (try? await pool.read { db in
            try DictionaryRecord.order(Column("created_at").desc).fetchAll(db)
        }) ?? []
        await MainActor.run { self.entries = items }
    }

    func add(word: String, context: String?) {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty else { return }
        let created = ISO8601DateFormatter().string(from: Date())
        let record = DictionaryRecord(
            word: w,
            context: context,
            pinyin: PinyinHelper.toPinyin(w),
            source: "manual",
            createdAt: created
        )
        Task {
            guard let pool = try? AppDatabase.shared.dbPool else { return }
            var r = record
            try? await pool.write { db in try r.insert(db) }
            await loadAsync()
        }
    }

    func delete(id: Int64) {
        Task {
            guard let pool = try? AppDatabase.shared.dbPool else { return }
            try? await pool.write { db in
                _ = try DictionaryRecord.filter(Column("id") == id).deleteAll(db)
            }
            await loadAsync()
        }
    }
}

final class CandidateRepository: ObservableObject {
    @Published var candidates: [ProfileService.DictionaryCandidate] = []

    func load() {
        Task { await loadAsync() }
    }

    private func loadAsync() async {
        let items = ProfileService.getCandidates()
        await MainActor.run {
            self.candidates = items
            AppState.shared.candidatesCount = items.count
            AppState.shared.dictionaryBadgeCount = items.count
        }
    }

    func approve(id: Int64) {
        Task {
            await ProfileService.approveCandidate(id: id)
            await loadAsync()
        }
    }

    func dismiss(id: Int64) {
        Task {
            await ProfileService.dismissCandidate(id: id)
            await loadAsync()
        }
    }
}
