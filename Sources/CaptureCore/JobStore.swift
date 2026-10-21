import Foundation
import CSQLite

public actor JobStore {
    private var db: OpaquePointer?
    private let owner = UUID().uuidString
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(paths: StoragePaths) throws {
        guard sqlite3_open_v2(paths.database.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw CaptureError.unavailable("无法打开本地任务数据库。")
        }
        sqlite3_busy_timeout(db, 5000)
        let sql = """
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS jobs (
            id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL, payload TEXT NOT NULL,
            status TEXT NOT NULL, created_at REAL NOT NULL, lease_owner TEXT,
            lease_until REAL NOT NULL DEFAULT 0, retry_at REAL NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS jobs_fingerprint ON jobs(fingerprint);
        CREATE INDEX IF NOT EXISTS jobs_pending ON jobs(status, retry_at, created_at);
        PRAGMA user_version=1;
        """
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &message) == SQLITE_OK else {
            let error = message.map { String(cString: $0) } ?? "SQLite error"
            sqlite3_free(message); sqlite3_close(db); db = nil
            throw CaptureError.unavailable(error)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.database.path)
    }
    deinit { sqlite3_close(db) }

    private func execute(_ sql: String, _ values: [String] = []) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
    }
    private func prepare(_ sql: String, _ values: [String]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw databaseError() }
        for (index, value) in values.enumerated() {
            guard sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) == SQLITE_OK else {
                sqlite3_finalize(statement); throw databaseError()
            }
        }
        return statement
    }
    private func databaseError() -> CaptureError {
        .unavailable(L10n.format("任务数据库错误：%@", String(cString: sqlite3_errmsg(db))))
    }
    private func query(_ sql: String, _ values: [String] = []) throws -> [CaptureJob] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var result: [CaptureJob] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW, let bytes = sqlite3_column_text(statement, 0) else { throw databaseError() }
            let data = Data(String(cString: bytes).utf8)
            result.append(try JSONDecoder().decode(CaptureJob.self, from: data))
        }
        return result
    }
    private func persist(_ job: CaptureJob, release: Bool = false, retryAt: TimeInterval = 0) throws {
        let payload = String(decoding: try JSONEncoder().encode(job), as: UTF8.self)
        if release {
            try execute("UPDATE jobs SET payload=?, status=?, lease_owner=NULL, lease_until=0, retry_at=? WHERE id=?",
                        [payload, job.status.rawValue, String(retryAt), job.id])
        } else {
            try execute("UPDATE jobs SET payload=?, status=? WHERE id=?", [payload, job.status.rawValue, job.id])
        }
    }
    public func enqueue(_ input: CaptureInput, config: AppConfiguration) throws -> CaptureJob {
        guard !config.deck.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CaptureError.invalid("请先选择目标 Anki 牌组。")
        }
        try execute("BEGIN IMMEDIATE")
        defer { try? execute("ROLLBACK") }
        let fingerprint = input.fingerprint(deck: config.deck, noteType: config.noteType)
        if let existing = try query("SELECT payload FROM jobs WHERE fingerprint=? AND status NOT IN ('failed','undone') ORDER BY created_at DESC LIMIT 1", [fingerprint]).first {
            try execute("COMMIT"); return existing
        }
        let now = Date()
        let job = CaptureJob(id: UUID().uuidString, input: input, deck: config.deck, noteType: config.noteType,
                             provider: config.provider, model: config.model, autoSave: config.autoSave, status: .queued,
                             createdAt: now, updatedAt: now, attempts: 0,
                             explanationLanguage: config.resolvedExplanationLanguage)
        let payload = String(decoding: try JSONEncoder().encode(job), as: UTF8.self)
        try execute("INSERT INTO jobs(id,fingerprint,payload,status,created_at) VALUES(?,?,?,?,?)",
                    [job.id, fingerprint, payload, job.status.rawValue, String(now.timeIntervalSince1970)])
        try execute("COMMIT")
        return job
    }
    public func list(limit: Int = 100) throws -> [CaptureJob] {
        try query("SELECT payload FROM jobs ORDER BY created_at DESC LIMIT ?", [String(max(1, min(limit, 1000)))])
    }
    public func get(_ id: String) throws -> CaptureJob? {
        try query("SELECT payload FROM jobs WHERE id=?", [id]).first
    }
    public func claimNext(now: Date = Date()) throws -> CaptureJob? {
        try execute("BEGIN IMMEDIATE")
        defer { try? execute("ROLLBACK") }
        let time = String(now.timeIntervalSince1970)
        let sql = """
        SELECT payload FROM jobs WHERE
          ((status IN ('queued','ready','waitingForAnki') AND retry_at<=?)
           OR status IN ('generating','saving'))
          AND (lease_owner IS NULL OR lease_until<?)
        ORDER BY created_at ASC LIMIT 1
        """
        guard var job = try query(sql, [time, time]).first else { try execute("COMMIT"); return nil }
        job.status = job.card == nil ? .generating : .saving
        job.updatedAt = now; job.attempts += 1
        try persist(job)
        try execute("UPDATE jobs SET lease_owner=?,lease_until=? WHERE id=?", [owner, String(now.timeIntervalSince1970 + 600), job.id])
        try execute("COMMIT")
        return job
    }
    public func generated(_ id: String, card: VocabularyCard, review: Bool) throws {
        guard var job = try get(id) else { throw CaptureError.invalid("找不到任务。") }
        job.card = card; job.status = review ? .review : .saving; job.updatedAt = Date(); job.error = nil
        try persist(job, release: review)
    }
    public func finish(_ id: String, status: JobStatus, noteID: Int64? = nil, error: String? = nil, retryAfter: Double = 0) throws {
        guard var job = try get(id) else { throw CaptureError.invalid("找不到任务。") }
        job.status = status; job.noteID = noteID ?? job.noteID; job.error = error; job.updatedAt = Date()
        if status == .undone { job.noteID = nil }
        try persist(job, release: true, retryAt: retryAfter > 0 ? Date().timeIntervalSince1970 + retryAfter : 0)
    }
    public func retry(_ id: String) throws {
        guard var job = try get(id) else { throw CaptureError.invalid("找不到任务。") }
        guard [.failed, .waitingForAnki, .review].contains(job.status) else {
            throw CaptureError.invalid("这个任务当前不需要重试。")
        }
        job.status = job.card == nil ? .queued : .ready; job.error = nil; job.updatedAt = Date()
        try persist(job, release: true)
    }
    public func replaceReviewCard(_ id: String, card: VocabularyCard) throws {
        guard var job = try get(id), job.status == .review else { throw CaptureError.invalid("只有待确认的字卡可以在这里编辑。") }
        job.card = try card.validated(); job.updatedAt = Date()
        try persist(job, release: true)
    }
}
