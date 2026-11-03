// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

use aspan_bridge::invoke;
use serde_json::{Value, json};
fn call(root: &std::path::Path, method: &str, args: Value, revision: Option<u64>) -> Value {
    invoke(
        &json!({"root":root,"method":method,"args":args,"revision":revision,"today":"2026-10-25"})
            .to_string(),
    )
}
fn state(root: &std::path::Path) -> Value {
    let r = call(root, "snapshot", json!({}), None);
    assert_eq!(r["ok"], true, "{r}");
    r["data"]["state"].clone()
}
#[test]
fn actual_sqlite_restart_and_revision_conflict() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path();
    assert_eq!(state(root)["revision"], 0);
    let r = call(root, "save_rule", json!({"name":"护照"}), Some(0));
    assert_eq!(r["ok"], true);
    assert_eq!(state(root)["rules"].as_object().unwrap().len(), 1);
    let stale = call(root, "save_rule", json!({"name":"过期写入"}), Some(0));
    assert_eq!(stale["ok"], false);
    assert_eq!(state(root)["rules"].as_object().unwrap().len(), 1);
    assert_eq!(state(root)["revision"], 1);
    let current = state(root)["revision"].as_u64();
    let next = call(
        root,
        "save_rule",
        json!({"name":"使用快照版本写入"}),
        current,
    );
    assert_eq!(next["ok"], true);
    assert_eq!(next["data"]["revision"], 2);
    assert_eq!(state(root)["revision"], next["data"]["revision"]);
    assert_eq!(state(root)["rules"].as_object().unwrap().len(), 2);
}
#[test]
fn backup_roundtrip_all_relations_and_checkpoint() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path();
    let tag = call(root, "save_tag", json!({"name":"生活"}), Some(0))["data"]["result"]
        .as_str()
        .unwrap()
        .to_string();
    call(
        root,
        "save_rule",
        json!({"name":"次卡","tags":[tag],"new_account":{"name":"游泳","unit":{"kind":"count","code":"次","precision":0},"initial":"20","reference":"20"}}),
        Some(1),
    );
    let original = state(root);
    let path = root.join("backup.json");
    assert_eq!(call(root, "export", json!({"path":path}), None)["ok"], true);
    assert_eq!(
        call(root, "export", json!({"path":path}), None)["ok"],
        false
    );
    call(root, "save_project", json!({"name":"临时项目"}), Some(2));
    assert_eq!(
        call(root, "restore", json!({"path":path}), Some(3))["ok"],
        true
    );
    let mut restored = state(root);
    assert_eq!(restored["revision"], 4);
    restored["revision"] = original["revision"].clone();
    assert_eq!(restored, original);
    let db = rusqlite::Connection::open(root.join("aspan.sqlite3")).unwrap();
    let checkpoints: u32 = db
        .query_row("SELECT count(*) FROM restore_checkpoints", [], |r| r.get(0))
        .unwrap();
    assert_eq!(checkpoints, 1);
}
#[test]
fn invalid_restore_keeps_current_data() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path();
    call(root, "save_rule", json!({"name":"保留"}), Some(0));
    let original = state(root);
    let mut corrupt = original.clone();
    corrupt["rules"]
        .as_object_mut()
        .unwrap()
        .values_mut()
        .next()
        .unwrap()["account"] = json!("missing");
    let path = root.join("invalid.json");
    std::fs::write(
        &path,
        json!({"format":"aspan-backup","version":1,"state":corrupt}).to_string(),
    )
    .unwrap();
    assert_eq!(
        call(root, "restore", json!({"path":path}), Some(1))["ok"],
        false
    );
    assert_eq!(state(root), original);
    std::fs::write(
        &path,
        json!({"format":"aspan-backup","version":2,"state":original}).to_string(),
    )
    .unwrap();
    assert_eq!(
        call(root, "restore", json!({"path":path}), Some(1))["ok"],
        false
    );
    assert_eq!(state(root), original);
}
#[test]
fn future_database_version_is_never_downgraded() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path();
    state(root);
    let db = rusqlite::Connection::open(root.join("aspan.sqlite3")).unwrap();
    db.pragma_update(None, "user_version", 99).unwrap();
    assert_eq!(call(root, "snapshot", json!({}), None)["ok"], false);
    let version: u32 = db
        .pragma_query_value(None, "user_version", |r| r.get(0))
        .unwrap();
    assert_eq!(version, 99);
}
#[test]
fn failed_multi_step_transaction_leaves_no_orphan_account() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path();
    let before = state(root);
    let r = call(
        root,
        "save_rule",
        json!({"name":"错误引用","tags":["missing"],"new_account":{"name":"余额","unit":{"kind":"money","code":"CNY","precision":2},"initial":"100"}}),
        Some(0),
    );
    assert_eq!(r["ok"], false);
    assert_eq!(state(root), before);
}
#[test]
fn concurrent_writers_cannot_lose_updates() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().to_path_buf();
    state(&root);
    let mut jobs = vec![];
    for i in 0..4 {
        let root = root.clone();
        jobs.push(std::thread::spawn(move || {
            call(&root, "save_rule", json!({"name":format!("R{i}")}), Some(0))
        }));
    }
    let winners = jobs
        .into_iter()
        .map(|j| j.join().unwrap())
        .filter(|r| r["ok"] == true)
        .count();
    assert_eq!(winners, 1);
    assert_eq!(state(&root)["rules"].as_object().unwrap().len(), 1);
}

#[test]
fn read_methods_do_not_reserve_a_writer_and_noop_does_not_rewrite_payload() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path();
    state(root);
    let db = rusqlite::Connection::open(root.join("aspan.sqlite3")).unwrap();
    db.execute_batch("BEGIN IMMEDIATE").unwrap();
    let read = call(root, "snapshot", json!({}), None);
    assert_eq!(read["ok"], true, "{read}");
    db.execute_batch("ROLLBACK").unwrap();
    call(
        root,
        "setting",
        json!({"key":"theme","value":"dark"}),
        Some(0),
    );
    db.execute_batch("CREATE TRIGGER no_update BEFORE UPDATE ON app_state BEGIN SELECT RAISE(ABORT, 'unexpected write'); END;").unwrap();
    let replay = call(
        root,
        "setting",
        json!({"key":"theme","value":"dark"}),
        Some(1),
    );
    assert_eq!(replay["ok"], true, "{replay}");
    assert_eq!(replay["data"]["revision"], 1);
}

#[test]
fn atomic_export_overwrite_is_explicit_and_protects_database_files() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path();
    state(root);
    let path = root.join("backup.json");
    std::fs::write(&path, b"existing file").unwrap();
    assert_eq!(
        call(root, "export", json!({"path":path}), None)["ok"],
        false
    );
    assert_eq!(std::fs::read(&path).unwrap(), b"existing file");
    assert_eq!(
        call(root, "export", json!({"path":path,"overwrite":true}), None)["ok"],
        true
    );
    assert_eq!(
        call(root, "validate_backup", json!({"path":path}), None)["ok"],
        true
    );
    for file in [
        "aspan.sqlite3",
        "ASPAN.SQLITE3",
        "aspan.sqlite3-journal",
        "aspan.sqlite3-wal",
    ] {
        assert_eq!(
            call(
                root,
                "export",
                json!({"path":root.join(file),"overwrite":true}),
                None
            )["ok"],
            false
        );
    }
    assert_eq!(std::fs::read_dir(root).unwrap().count(), 2);
    assert_eq!(state(root)["revision"], 0);
}

#[test]
fn damaged_state_has_raw_rescue_and_validated_restore_without_softening_gates() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path();
    call(root, "save_rule", json!({"name":"保留"}), Some(0));
    let backup = root.join("good.json");
    call(root, "export", json!({"path":backup}), None);
    let db = rusqlite::Connection::open(root.join("aspan.sqlite3")).unwrap();
    let mut damaged = state(root);
    let rid = damaged["rules"]
        .as_object()
        .unwrap()
        .keys()
        .next()
        .unwrap()
        .clone();
    damaged["rules"][&rid]["project"] = json!("missing");
    let payload = damaged.to_string();
    db.execute("UPDATE app_state SET payload=?1", [&payload])
        .unwrap();
    assert_eq!(call(root, "snapshot", json!({}), None)["ok"], false);
    assert_eq!(
        call(root, "validate_backup", json!({"path":backup}), None)["ok"],
        true
    );
    let rescue = root.join("rescue.json");
    assert_eq!(
        call(root, "export_raw", json!({"path":rescue}), None)["ok"],
        true
    );
    let raw: Value = serde_json::from_slice(&std::fs::read(&rescue).unwrap()).unwrap();
    assert_eq!(raw["payload"], payload);
    assert_eq!(
        call(root, "validate_backup", json!({"path":rescue}), None)["ok"],
        false
    );
    assert_eq!(
        call(root, "restore", json!({"path":backup}), Some(1))["ok"],
        true
    );
    assert_eq!(state(root)["rules"][&rid]["project"], Value::Null);
    let checkpoint: String = db
        .query_row("SELECT payload FROM restore_checkpoints", [], |r| r.get(0))
        .unwrap();
    assert_eq!(checkpoint, payload);
}

#[test]
fn ffi_errors_and_revision_code_are_stable() {
    assert_eq!(invoke("{")["ok"], false);
    assert_eq!(
        invoke(r#"{"root":"relative","method":"snapshot","today":"2026-10-25"}"#)["ok"],
        false
    );
    let dir = tempfile::tempdir().unwrap();
    state(dir.path());
    assert_eq!(
        call(dir.path(), "save_rule", json!({"name":"旧版本"}), Some(3))["code"],
        "revision_conflict"
    );
    unsafe {
        let result = aspan_bridge::aspan_invoke_json(std::ptr::null());
        let value: Value =
            serde_json::from_str(std::ffi::CStr::from_ptr(result).to_str().unwrap()).unwrap();
        assert_eq!(value["ok"], false);
        aspan_bridge::aspan_free_json(result);
        let bytes = [255u8, 0];
        let result = aspan_bridge::aspan_invoke_json(bytes.as_ptr().cast());
        let value: Value =
            serde_json::from_str(std::ffi::CStr::from_ptr(result).to_str().unwrap()).unwrap();
        assert_eq!(value["ok"], false);
        aspan_bridge::aspan_free_json(result);
    }
}

#[test]
fn future_payload_schema_is_never_overwritten_by_restore() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path();
    let mut payload = state(root);
    let backup = root.join("backup.json");
    assert_eq!(
        call(root, "export", json!({"path":backup}), None)["ok"],
        true
    );
    payload["schema"] = json!(2);
    let original = payload.to_string();
    let db = rusqlite::Connection::open(root.join("aspan.sqlite3")).unwrap();
    db.execute("UPDATE app_state SET payload=?1", [&original])
        .unwrap();
    assert_eq!(
        call(root, "restore", json!({"path":backup}), Some(0))["ok"],
        false
    );
    let after: String = db
        .query_row("SELECT payload FROM app_state", [], |row| row.get(0))
        .unwrap();
    assert_eq!(after, original);
}

#[test]
fn scale_backup_validation_and_restore_are_bounded_and_keep_all_records() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path();
    let mut data = serde_json::to_value(aspan_core::State::default()).unwrap();
    for i in 0..2000 {
        let rid = format!("r{i}");
        let aid = format!("a{i}");
        data["rules"][&rid] = json!({"id":rid,"name":"规模","notes":"","icon":"schedule","project":null,"group":null,"tags":[],"schedule":null,"reminder":{"before":[],"on_day":true,"grace_days":0,"repeat_days":null},"account":aid,"change":null,"reset":null,"pinned":false,"order":i,"deleted":false});
        data["accounts"][&aid] = json!({"id":aid,"name":"账户","unit":{"kind":"count","code":"次","precision":0},"reference":null,"low":null,"archived":false});
        for j in 0..10 {
            let eid = format!("e{i}-{j}");
            data["ledger"][&eid] = json!({"id":eid,"key":format!("key-{eid}"),"account":aid,"rule":rid,"occurrence":null,"delta":1,"date":"2026-10-01","source":"manual","note":"add:1:规模测试","corrected_by":null,"origin":null});
            data["history"].as_array_mut().unwrap().push(json!({"id":format!("h{i}-{j}"),"subject":aid,"action":"resource","date":"2026-10-01","detail":eid}));
        }
    }
    let backup = root.join("scale.json");
    let bytes =
        serde_json::to_vec_pretty(&json!({"format":"aspan-backup","version":1,"state":data}))
            .unwrap();
    assert!(bytes.len() > 8 * 1024 * 1024);
    std::fs::write(&backup, bytes).unwrap();
    for method in ["validate_backup", "restore"] {
        let start = std::time::Instant::now();
        let result = call(root, method, json!({"path":backup}), Some(0));
        assert_eq!(result["ok"], true, "{result}");
        let elapsed = start.elapsed();
        println!("scale {method}: {}ms", elapsed.as_millis());
        assert!(
            elapsed < std::time::Duration::from_secs(10),
            "{method} regressed: {elapsed:?}"
        );
    }
    let restored = state(root);
    assert_eq!(restored["ledger"].as_object().unwrap().len(), 20000);
    assert_eq!(restored["history"].as_array().unwrap().len(), 20000);
    let too_big = root.join("too-big.json");
    std::fs::File::create(&too_big)
        .unwrap()
        .set_len(50 * 1024 * 1024 + 1)
        .unwrap();
    assert_eq!(
        call(root, "restore", json!({"path":too_big}), Some(1))["ok"],
        false
    );
    assert_eq!(state(root), restored);
}
