// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

use aspan_core::{Result, State, calendar::date};
use rusqlite::{Connection, TransactionBehavior, params};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    ffi::{CStr, CString, c_char},
    io::{Read, Write},
    path::{Path, PathBuf},
    time::Duration,
};

#[derive(Deserialize)]
struct Request {
    root: PathBuf,
    method: String,
    #[serde(default)]
    args: Value,
    today: String,
    revision: Option<u64>,
}
const BACKUP_LIMIT: u64 = 50 * 1024 * 1024;
const REVISION_CONFLICT: &str = "数据已变化或未提供版本，请关闭编辑后重新载入再试";

#[derive(Deserialize)]
struct Backup {
    format: String,
    version: u32,
    state: State,
}

pub fn invoke(input: &str) -> Value {
    match std::panic::catch_unwind(|| dispatch(input)) {
        Ok(Ok(data)) => json!({"ok":true,"data":data}),
        Ok(Err(error)) => {
            json!({"ok":false,"code":if error == REVISION_CONFLICT {"revision_conflict"} else {"operation_failed"},"error":error})
        }
        Err(_) => {
            json!({"ok":false,"code":"core_panic","error":"核心异常，事务已回滚；原数据保留"})
        }
    }
}
fn dispatch(input: &str) -> Result<Value> {
    let req: Request = serde_json::from_str(input).map_err(|e| format!("请求无效：{e}"))?;
    let today = date(&req.today)?;
    if !req.root.is_absolute() {
        return Err("数据库目录必须为绝对路径".into());
    }
    // Validation is independent of the currently open database, including a damaged one.
    if req.method == "validate_backup" {
        let backup = read_backup(&absolute(&req.args, "path")?)?;
        return Ok(
            json!({"rules":backup.rules.values().filter(|r|!r.deleted).count(),"accounts":backup.accounts.len(),"history":backup.history.len(),"revision":backup.revision}),
        );
    }
    // Parse and fully validate before reserving the write lock.
    let restore = if req.method == "restore" {
        Some(read_backup(&absolute(&req.args, "path")?)?)
    } else {
        None
    };
    std::fs::create_dir_all(&req.root).map_err(|e| e.to_string())?;
    let mut db = Connection::open(req.root.join("aspan.sqlite3")).map_err(|e| e.to_string())?;
    db.busy_timeout(Duration::from_secs(5))
        .map_err(|e| e.to_string())?;
    db.pragma_update(None, "synchronous", "FULL")
        .map_err(|e| e.to_string())?;
    let version: u32 = db
        .pragma_query_value(None, "user_version", |row| row.get(0))
        .map_err(|e| e.to_string())?;
    if version > 1 {
        return Err("数据库来自更高版本，未修改原数据".into());
    }
    let read_only = matches!(
        req.method.as_str(),
        "snapshot" | "forecast" | "reminder_plan" | "merge_plan" | "export" | "export_raw"
    );
    let tx = db
        .transaction_with_behavior(if version == 0 || !read_only {
            TransactionBehavior::Immediate
        } else {
            TransactionBehavior::Deferred
        })
        .map_err(|e| e.to_string())?;
    if version == 0 {
        tx.execute_batch("CREATE TABLE IF NOT EXISTS app_state (singleton INTEGER PRIMARY KEY CHECK(singleton=1), payload TEXT NOT NULL); CREATE TABLE IF NOT EXISTS restore_checkpoints (id INTEGER PRIMARY KEY, payload TEXT NOT NULL); PRAGMA user_version=1;").map_err(|e|e.to_string())?;
        tx.execute(
            "INSERT OR IGNORE INTO app_state VALUES (1,?1)",
            params![serde_json::to_string(&State::default()).unwrap()],
        )
        .map_err(|e| e.to_string())?;
    }
    let payload: String = tx
        .query_row("SELECT payload FROM app_state WHERE singleton=1", [], |r| {
            r.get(0)
        })
        .map_err(|e| e.to_string())?;
    if req.method == "export_raw" {
        let dest = export_destination(&req.args, &req.root)?;
        let bytes = serde_json::to_vec_pretty(
            &json!({"format":"aspan-rescue","version":1,"payload":payload}),
        )
        .map_err(|e| e.to_string())?;
        write_backup(&dest, &bytes, false)?;
        tx.commit().map_err(|e| e.to_string())?;
        return Ok(json!({"path":dest,"bytes":bytes.len(),"validated":false}));
    }
    let mut state: State =
        serde_json::from_str(&payload).map_err(|e| format!("数据无法读取，原文件保留：{e}"))?;
    // Recovery may bypass damaged references, never a newer payload schema.
    if state.schema != 1 {
        return Err("不支持的数据版本，原数据保留".into());
    }
    if req.method != "restore" {
        state.validate()?;
    }
    let result = match req.method.as_str() {
        "snapshot" => state.snapshot(today)?,
        "reminder_plan" => state.reminder_plan(today),
        "forecast" => state.forecast(
            req.args["account"].as_str().ok_or("缺少账户")?,
            today,
            req.args["limit"].as_u64().unwrap_or(24) as usize,
        )?,
        "merge_plan" => state.merge_plan(
            &serde_json::from_value::<Vec<String>>(req.args["rules"].clone())
                .map_err(|e| e.to_string())?,
        )?,
        "export" => {
            let dest = export_destination(&req.args, &req.root)?;
            let backup = json!({"format":"aspan-backup","version":1,"state":state});
            let bytes = serde_json::to_vec_pretty(&backup).map_err(|e| e.to_string())?;
            write_backup(&dest, &bytes, req.args["overwrite"] == true)?;
            json!({"path":dest,"bytes":bytes.len()})
        }
        "restore" => {
            check_revision(req.revision, state.revision)?;
            let mut backup = restore.ok_or("缺少已校验备份")?;
            backup.revision = state.revision.checked_add(1).ok_or("版本超出范围")?;
            tx.execute(
                "INSERT INTO restore_checkpoints(payload) VALUES (?1)",
                params![payload],
            )
            .map_err(|e| e.to_string())?;
            state = backup;
            tx.execute(
                "UPDATE app_state SET payload=?1 WHERE singleton=1",
                params![serde_json::to_string(&state).map_err(|e| e.to_string())?],
            )
            .map_err(|e| e.to_string())?;
            state.snapshot(today)?
        }
        method => {
            check_revision(req.revision, state.revision)?;
            let previous_revision = state.revision;
            let output = state.apply(method, req.args, today)?;
            if state.revision != previous_revision {
                tx.execute(
                    "UPDATE app_state SET payload=?1 WHERE singleton=1",
                    params![serde_json::to_string(&state).map_err(|e| e.to_string())?],
                )
                .map_err(|e| e.to_string())?;
            }
            json!({"result":output,"revision":state.revision})
        }
    };
    tx.commit().map_err(|e| e.to_string())?;
    Ok(result)
}
fn check_revision(expected: Option<u64>, current: u64) -> Result<()> {
    if expected == Some(current) {
        Ok(())
    } else {
        Err(REVISION_CONFLICT.into())
    }
}
fn absolute(a: &Value, key: &str) -> Result<PathBuf> {
    let p = PathBuf::from(a[key].as_str().ok_or("缺少文件路径")?);
    if !p.is_absolute() {
        return Err("文件路径必须为绝对路径".into());
    }
    Ok(p)
}
fn read_backup(path: &Path) -> Result<State> {
    let file = std::fs::File::open(path).map_err(|e| e.to_string())?;
    if file.metadata().map_err(|e| e.to_string())?.len() > BACKUP_LIMIT {
        return Err("备份超过当前 50MB 导入上限".into());
    }
    let mut bytes = Vec::new();
    file.take(BACKUP_LIMIT + 1)
        .read_to_end(&mut bytes)
        .map_err(|e| e.to_string())?;
    if bytes.len() as u64 > BACKUP_LIMIT {
        return Err("备份超过当前 50MB 导入上限".into());
    }
    let data: Backup = serde_json::from_slice(&bytes).map_err(|e| format!("备份无效：{e}"))?;
    if data.format != "aspan-backup" || data.version != 1 {
        return Err("不支持的备份格式或版本".into());
    }
    let state = data.state;
    state.validate()?;
    Ok(state)
}

fn export_destination(args: &Value, root: &Path) -> Result<PathBuf> {
    let dest = absolute(args, "path")?;
    let parent = dest
        .parent()
        .ok_or("导出目录无效")?
        .canonicalize()
        .map_err(|e| e.to_string())?;
    let normalized = parent.join(dest.file_name().ok_or("文件名无效")?);
    let db = root.canonicalize().map_err(|e| e.to_string())?;
    if normalized.parent() == Some(db.as_path())
        && normalized.file_name().is_some_and(|n| {
            n.to_string_lossy()
                .to_ascii_lowercase()
                .starts_with("aspan.sqlite3")
        })
    {
        return Err("不能覆盖数据库及其事务文件".into());
    }
    Ok(normalized)
}

fn write_backup(dest: &Path, bytes: &[u8], overwrite: bool) -> Result<()> {
    let mut file = tempfile::NamedTempFile::new_in(dest.parent().ok_or("导出目录无效")?)
        .map_err(|e| e.to_string())?;
    file.write_all(bytes)
        .and_then(|_| file.as_file().sync_all())
        .map_err(|e| e.to_string())?;
    if overwrite {
        file.persist(dest)
    } else {
        file.persist_noclobber(dest)
    }
    .map_err(|e| e.to_string())?;
    Ok(())
}

/// # Safety
/// `input` must point to a valid NUL-terminated UTF-8 string for the call duration.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn aspan_invoke_json(input: *const c_char) -> *mut c_char {
    let response = if input.is_null() {
        json!({"ok":false,"error":"空请求"})
    } else {
        match unsafe { CStr::from_ptr(input) }.to_str() {
            Ok(s) => invoke(s),
            Err(_) => json!({"ok":false,"error":"请求不是 UTF-8"}),
        }
    };
    CString::new(response.to_string())
        .expect("JSON has no NUL bytes")
        .into_raw()
}
/// # Safety
/// `pointer` must be a live pointer returned by aspan_invoke_json, freed exactly once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn aspan_free_json(pointer: *mut c_char) {
    if !pointer.is_null() {
        drop(unsafe { CString::from_raw(pointer) });
    }
}
