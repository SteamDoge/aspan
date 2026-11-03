// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

use aspan_core::{
    calendar::{Cycle, Schedule, date},
    *,
};
use serde_json::{Value, json};
fn day(s: &str) -> chrono::NaiveDate {
    date(s).unwrap()
}
fn now() -> chrono::NaiveDate {
    day("2026-10-25")
}
fn run(s: &mut State, m: &str, a: Value) -> Value {
    s.apply(m, a, now()).unwrap()
}
fn rule(s: &mut State, name: &str, initial: Option<&str>) -> String {
    let mut a = json!({"name":name,"schedule":{"anchor":"2026-10-15","next":"2026-11-15","cycle":{"kind":"monthly"}}});
    if let Some(n) = initial {
        a["new_account"] = json!({"name":name,"unit":{"kind":"money","code":"CNY","precision":2},"initial":n,"reference":null,"low":"20"});
    }
    run(s, "save_rule", a).as_str().unwrap().into()
}
fn merge(s: &mut State, ids: &[String], choices: Value) -> String {
    run(
        s,
        "merge",
        json!({"rules":ids,"name":"手机卡","project":null,"choices":choices}),
    )
    .as_str()
    .unwrap()
    .into()
}
fn resource(s: &mut State, aid: &str, action: &str, amount: &str, key: &str) -> Value {
    run(
        s,
        "resource",
        json!({"account":aid,"action":action,"amount":amount,"key":key}),
    )
}

#[test]
fn exact_units_and_precision() {
    let u = Unit {
        kind: ResourceKind::Money,
        code: "CNY".into(),
        precision: 2,
    };
    assert_eq!(u.parse("0.10").unwrap() + u.parse("0.20").unwrap(), 30);
    assert!(u.parse("0.001").is_err());
    assert!(u.parse("1e3").is_err());
    assert!(u.parse("NaN").is_err());
    assert!(u.parse("92233720368547758.08").is_err());
    assert_eq!(u.format(i64::MIN), "-92233720368547758.08");
    assert!(
        Unit {
            kind: ResourceKind::Count,
            code: "次".into(),
            precision: 1
        }
        .validate()
        .is_err()
    );
}
#[test]
fn independent_rules_and_no_account_vs_zero() {
    let mut s = State::default();
    let a = rule(&mut s, "扣费", Some("0"));
    let b = rule(&mut s, "保活", None);
    assert!(s.rules[&a].account.is_some());
    assert!(s.rules[&b].account.is_none());
    assert_eq!(s.balance(s.rules[&a].account.as_ref().unwrap()).unwrap(), 0);
    assert_eq!(s.snapshot(now()).unwrap()["summary"]["rules"], 2);
}
#[test]
fn shared_balance_100_plus_50_minus_18_and_idempotent() {
    let mut s = State::default();
    let a = rule(&mut s, "扣费", Some("100"));
    let b = rule(&mut s, "保活", None);
    let g = merge(&mut s, &[a.clone(), b.clone()], json!({}));
    let aid = s.rules[&a].account.clone().unwrap();
    assert_eq!(s.rules[&b].account, Some(aid.clone()));
    resource(&mut s, &aid, "add", "50", "topup");
    resource(&mut s, &aid, "consume", "18", "charge");
    resource(&mut s, &aid, "consume", "18", "charge");
    assert_eq!(s.balance(&aid).unwrap(), 13200);
    assert_eq!(s.groups[&g].accounts.len(), 1);
}
#[test]
fn equal_balances_choose_one_and_archive_history() {
    let mut s = State::default();
    let a = rule(&mut s, "A", Some("100"));
    let b = rule(&mut s, "B", Some("100"));
    let g = merge(&mut s, &[a, b], json!({}));
    assert_eq!(s.groups[&g].accounts.len(), 1);
    assert_eq!(s.groups[&g].archived_accounts.len(), 1);
    assert_eq!(s.ledger.len(), 2);
    let aid = s.groups[&g].accounts.first().unwrap();
    assert_eq!(s.balance(aid).unwrap(), 10000);
}
#[test]
fn conflict_is_explicit_and_failed_merge_is_atomic() {
    let mut s = State::default();
    let a = rule(&mut s, "A", Some("100"));
    let b = rule(&mut s, "B", Some("200"));
    let before = serde_json::to_value(&s).unwrap();
    assert!(
        s.apply(
            "merge",
            json!({"rules":[a,b],"name":"G","project":null}),
            now()
        )
        .is_err()
    );
    assert_eq!(serde_json::to_value(&s).unwrap(), before);
    let aid = s.rules[&b].account.clone().unwrap();
    let unit = s.accounts[&aid].unit.key();
    let g = merge(&mut s, &[a, b], json!({unit:aid}));
    assert_eq!(
        s.balance(s.groups[&g].accounts.first().unwrap()).unwrap(),
        20000
    );
}
#[test]
fn mixed_currencies_remain_separate() {
    let mut s = State::default();
    let a = rule(&mut s, "A", Some("100"));
    let b=run(&mut s,"save_rule",json!({"name":"USD","new_account":{"name":"USD","unit":{"kind":"money","code":"USD","precision":2},"initial":"100"}})).as_str().unwrap().to_string();
    let g = merge(&mut s, &[a, b], json!({}));
    assert_eq!(s.groups[&g].accounts.len(), 2);
}
#[test]
fn complete_copy_then_delete_different_members_independent() {
    let mut s = State::default();
    let a = rule(&mut s, "A", Some("100"));
    let b = rule(&mut s, "B", None);
    let g = merge(&mut s, &[a.clone(), b.clone()], json!({}));
    let aid = s.rules[&a].account.clone().unwrap();
    resource(&mut s, &aid, "add", "50", "recharge");
    let copied = run(&mut s, "copy", json!({"id":g}))
        .as_str()
        .unwrap()
        .to_string();
    let members: Vec<_> = s
        .rules
        .values()
        .filter(|r| r.group.as_ref() == Some(&copied))
        .cloned()
        .collect();
    let copyaid = members[0].account.clone().unwrap();
    assert_ne!(aid, copyaid);
    assert_eq!(s.balance(&copyaid).unwrap(), 15000);
    run(&mut s, "delete_rule", json!({"id":a}));
    run(&mut s, "delete_rule", json!({"id":members[1].id}));
    assert!(s.rules[&b].group.is_none());
    assert!(s.rules[&members[0].id].group.is_none());
    resource(&mut s, &copyaid, "consume", "18", "copy-charge");
    assert_eq!(s.balance(&aid).unwrap(), 15000);
    assert_eq!(s.balance(&copyaid).unwrap(), 13200);
    s.validate().unwrap();
}
#[test]
fn archived_ledger_correction_never_changes_authoritative_balance() {
    let mut s = State::default();
    let a = rule(&mut s, "A", Some("100"));
    let b = rule(&mut s, "B", Some("100"));
    let g = merge(&mut s, &[a, b], json!({}));
    let old = s.groups[&g].archived_accounts.first().unwrap().clone();
    let active = s.groups[&g].accounts.first().unwrap().clone();
    let eid = s
        .ledger
        .values()
        .find(|e| e.account == old)
        .unwrap()
        .id
        .clone();
    run(
        &mut s,
        "correct_entry",
        json!({"id":eid,"delta":"150","reason":"录入纠正"}),
    );
    assert_eq!(s.balance(&old).unwrap(), 15000);
    assert_eq!(s.balance(&active).unwrap(), 10000);
    assert!(s.accounts[&old].archived);
}
#[test]
fn fixed_calendar_completion_does_not_drift_and_no_duplicate_charge() {
    let mut s = State::default();
    let a = rule(&mut s, "月费", Some("100"));
    s.rules.get_mut(&a).unwrap().change = Some(-1800);
    let request =
        json!({"rule":a,"planned":"2026-11-15","actual":"2026-11-18","status":"completed"});
    s.apply("event", request.clone(), day("2026-11-18"))
        .unwrap();
    let revision = s.revision;
    s.apply("event", request, day("2026-11-18")).unwrap();
    assert_eq!(s.revision, revision);
    assert_eq!(
        s.rules[&a].schedule.as_ref().unwrap().next,
        Some(day("2026-12-15"))
    );
    assert_eq!(
        s.balance(s.rules[&a].account.as_ref().unwrap()).unwrap(),
        8200
    );
}
#[test]
fn restart_uses_actual_date() {
    let mut s = State::default();
    let a = rule(&mut s, "保活", None);
    s.rules
        .get_mut(&a)
        .unwrap()
        .schedule
        .as_mut()
        .unwrap()
        .cycle = Cycle::Restart { days: 365 };
    s.apply(
        "event",
        json!({"rule":a,"planned":"2026-11-15","actual":"2026-11-18","status":"completed"}),
        day("2026-11-18"),
    )
    .unwrap();
    assert_eq!(
        s.rules[&a].schedule.as_ref().unwrap().next,
        Some(day("2027-11-18"))
    );
}
#[test]
fn month_end_and_leap_day_recover_anchor() {
    let s = Schedule {
        calendar_anchor: None,
        anchor: day("2024-01-31"),
        next: Some(day("2024-01-31")),
        cycle: Cycle::Monthly,
    };
    let feb = s.after(day("2024-01-31"), now()).unwrap().unwrap();
    assert_eq!(feb, day("2024-02-29"));
    assert_eq!(s.after(feb, now()).unwrap().unwrap(), day("2024-03-31"));
    let mut s = Schedule {
        calendar_anchor: None,
        anchor: day("2024-02-29"),
        next: None,
        cycle: Cycle::Yearly,
    };
    assert_eq!(
        s.after(day("2024-02-29"), now()).unwrap().unwrap(),
        day("2025-02-28")
    );
    assert_eq!(
        s.after(day("2027-02-28"), now()).unwrap().unwrap(),
        day("2028-02-29")
    );
    s.cycle = Cycle::Interval { days: 365 };
    assert_eq!(
        s.after(day("2023-03-01"), now()).unwrap().unwrap(),
        day("2024-02-29")
    );
    s.cycle = Cycle::Yearly;
    s.anchor = day("2023-03-01");
    assert_eq!(
        s.after(day("2023-03-01"), now()).unwrap().unwrap(),
        day("2024-03-01")
    );
}
#[test]
fn yearly_benefit_reset_and_use_history() {
    let mut s = State::default();
    let a=run(&mut s,"save_rule",json!({"name":"贵宾厅","new_account":{"name":"权益","unit":{"kind":"count","code":"次","precision":0},"initial":"6","reference":"6"},"reset":"6","schedule":{"anchor":"2025-11-01","next":"2026-11-01","cycle":{"kind":"yearly"}}})).as_str().unwrap().to_string();
    let aid = s.rules[&a].account.clone().unwrap();
    resource(&mut s, &aid, "consume", "1", "use");
    assert_eq!(s.balance(&aid).unwrap(), 5);
    run(
        &mut s,
        "event",
        json!({"rule":a,"planned":"2026-11-01","status":"completed"}),
    );
    assert_eq!(s.balance(&aid).unwrap(), 6);
    assert_eq!(s.ledger.len(), 3);
    assert_eq!(s.occurrences.len(), 1);
}
#[test]
fn count_cannot_overdraw_atomic() {
    let mut s = State::default();
    let a=run(&mut s,"save_rule",json!({"name":"游泳","new_account":{"name":"次卡","unit":{"kind":"count","code":"次","precision":0},"initial":"20","reference":"20"}})).as_str().unwrap().to_string();
    let aid = s.rules[&a].account.clone().unwrap();
    resource(&mut s, &aid, "consume", "1", "swim");
    assert_eq!(s.balance(&aid).unwrap(), 19);
    let before = s.ledger.len();
    assert!(
        s.apply(
            "resource",
            json!({"account":aid,"action":"consume","amount":"20","key":"excess"}),
            now()
        )
        .is_err()
    );
    assert_eq!(s.ledger.len(), before);
}
#[test]
fn annual_fee_grace_and_reminder_ends_for_completed_occurrence() {
    let mut s = State::default();
    let a = rule(&mut s, "年费", None);
    let r = s.rules.get_mut(&a).unwrap();
    r.reminder = Reminder {
        before: vec![30, 7, 1],
        on_day: true,
        grace_days: 90,
        repeat_days: Some(7),
    };
    r.schedule.as_mut().unwrap().cycle = Cycle::Yearly;
    r.schedule.as_mut().unwrap().anchor = day("2025-11-15");
    assert_eq!(
        s.snapshot(day("2026-11-20")).unwrap()["views"][&a]["phase"],
        "grace"
    );
    let window_end = day("2026-11-15") + chrono::Duration::days(90);
    assert_eq!(
        s.snapshot(window_end).unwrap()["views"][&a]["phase"],
        "grace"
    );
    assert_eq!(
        s.snapshot(window_end + chrono::Duration::days(1)).unwrap()["views"][&a]["phase"],
        "overdue"
    );
    s.apply(
        "event",
        json!({"rule":a,"planned":"2026-11-15","actual":"2026-11-15","status":"completed"}),
        day("2026-11-15"),
    )
    .unwrap();
    let plan = s.reminder_plan(day("2026-11-20"));
    assert_eq!(plan["notifications"].as_array().unwrap().len(), 0);
    assert_eq!(
        s.rules[&a].schedule.as_ref().unwrap().next,
        Some(day("2027-11-15"))
    );
}
#[test]
fn forecast_and_reopening_are_pure() {
    let mut s = State::default();
    let a = rule(&mut s, "云", Some("100"));
    s.rules.get_mut(&a).unwrap().change = Some(-1800);
    let aid = s.rules[&a].account.clone().unwrap();
    let before = serde_json::to_string(&s).unwrap();
    for _ in 0..3 {
        s.snapshot(now()).unwrap();
        s.forecast(&aid, now(), 24).unwrap();
        s.reminder_plan(now());
    }
    assert_eq!(serde_json::to_string(&s).unwrap(), before);
    assert_eq!(
        s.forecast(&aid, now(), 6).unwrap()["events"][5]["balance"],
        "-8.00"
    );
}
#[test]
fn set_balance_replay_and_key_collision() {
    let mut s = State::default();
    let a = rule(&mut s, "A", Some("100"));
    let aid = s.rules[&a].account.clone().unwrap();
    resource(&mut s, &aid, "set", "50", "set");
    resource(&mut s, &aid, "set", "50", "set");
    assert_eq!(s.balance(&aid).unwrap(), 5000);
    assert!(
        s.apply(
            "resource",
            json!({"account":aid,"action":"set","amount":"60","key":"set"}),
            now()
        )
        .is_err()
    );
}
#[test]
fn correction_reversal_and_replacement_audit() {
    let mut s = State::default();
    let a = rule(&mut s, "A", Some("100"));
    let aid = s.rules[&a].account.clone().unwrap();
    let e = resource(&mut s, &aid, "consume", "18", "bad");
    let replacement = run(
        &mut s,
        "correct_entry",
        json!({"id":e,"delta":"-8","reason":"录错金额"}),
    );
    assert_eq!(s.balance(&aid).unwrap(), 9200);
    assert_eq!(s.ledger.len(), 4);
    assert_eq!(
        s.ledger[e.as_str().unwrap()].corrected_by.as_deref(),
        replacement.as_str()
    );
}
#[test]
fn invalid_references_are_rejected() {
    let mut s = State::default();
    let a = rule(&mut s, "A", None);
    s.rules.get_mut(&a).unwrap().tags.insert("missing".into());
    assert!(s.validate().is_err());
}
#[test]
fn cross_project_merge_must_confirm() {
    let mut s = State::default();
    let a = rule(&mut s, "A", None);
    let b = rule(&mut s, "B", None);
    let p = run(&mut s, "save_project", json!({"name":"项目"}));
    run(&mut s, "move", json!({"id":a,"project":p}));
    assert!(
        s.apply(
            "merge",
            json!({"rules":[a,b],"name":"G","project":p}),
            now()
        )
        .is_err()
    );
    run(
        &mut s,
        "merge",
        json!({"rules":[a,b],"name":"G","project":p,"confirm_project":true}),
    );
}
#[test]
fn copied_completed_events_and_corrected_ledgers_are_independent() {
    let mut s = State::default();
    let a = rule(&mut s, "A", Some("100"));
    s.rules.get_mut(&a).unwrap().change = Some(-1800);
    run(
        &mut s,
        "event",
        json!({"rule":a,"planned":"2026-11-15","status":"completed"}),
    );
    let old = s
        .ledger
        .values()
        .find(|e| e.source == "confirmed")
        .unwrap()
        .id
        .clone();
    run(
        &mut s,
        "correct_entry",
        json!({"id":old,"delta":"-8","reason":"更正"}),
    );
    let b = run(&mut s, "copy", json!({"id":a}))
        .as_str()
        .unwrap()
        .to_string();
    let aid = s.rules[&a].account.as_ref().unwrap();
    let bid = s.rules[&b].account.as_ref().unwrap();
    assert_ne!(aid, bid);
    assert_eq!(s.balance(aid).unwrap(), s.balance(bid).unwrap());
    assert_eq!(s.occurrences.values().filter(|o| o.rule == b).count(), 1);
    s.validate().unwrap();
}

#[test]
fn long_reminder_window_keeps_current_repeat_nodes() {
    let mut s = State::default();
    let a = rule(&mut s, "长期事项", None);
    s.rules.get_mut(&a).unwrap().reminder = Reminder {
        before: vec![1000],
        on_day: true,
        grace_days: 90,
        repeat_days: Some(1),
    };
    let plan = s.reminder_plan(day("2026-11-20"));
    assert!(
        plan["notifications"]
            .as_array()
            .unwrap()
            .iter()
            .any(|n| n["date"] == "2026-11-20")
    );
    assert_eq!(
        s.snapshot(day("2026-11-20")).unwrap()["views"][&a]["next_reminder"],
        "2026-11-20"
    );
}
#[test]
fn visual_start_and_calendar_anchor_are_independent() {
    let s = Schedule {
        anchor: day("2026-10-25"),
        calendar_anchor: Some(day("2026-11-15")),
        next: Some(day("2026-11-15")),
        cycle: Cycle::Monthly,
    };
    s.validate().unwrap();
    assert_eq!(
        s.after(day("2026-11-15"), day("2026-11-18")).unwrap(),
        Some(day("2026-12-15"))
    );
}
#[test]
fn group_copy_preserves_deleted_time_only_member_events() {
    let mut s = State::default();
    let a = rule(&mut s, "A", None);
    let b = rule(&mut s, "B", None);
    let c = rule(&mut s, "C", None);
    let g = merge(&mut s, &[a.clone(), b, c], json!({}));
    run(
        &mut s,
        "event",
        json!({"rule":a,"planned":"2026-11-15","status":"completed"}),
    );
    run(&mut s, "delete_rule", json!({"id":a}));
    let copy = run(&mut s, "copy", json!({"id":g}))
        .as_str()
        .unwrap()
        .to_string();
    let old = s.groups[&copy].historical_members.first().unwrap();
    assert_ne!(old, &a);
    assert!(s.rules[old].deleted);
    assert_eq!(s.occurrences.values().filter(|o| &o.rule == old).count(), 1);
    s.validate().unwrap();
}
#[test]
fn tag_union_and_independent_maintenance() {
    let mut s = State::default();
    let a = rule(&mut s, "滤芯A", None);
    let b = rule(&mut s, "滤芯B", None);
    let tag = run(&mut s, "save_tag", json!({"name":"设备"}))
        .as_str()
        .unwrap()
        .to_string();
    s.rules.get_mut(&a).unwrap().tags.insert(tag.clone());
    let g = merge(&mut s, &[a.clone(), b.clone()], json!({}));
    assert_eq!(s.snapshot(now()).unwrap()["group_tags"][&g], json!([tag]));
    run(
        &mut s,
        "event",
        json!({"rule":a,"planned":"2026-11-15","status":"completed"}),
    );
    assert_eq!(
        s.rules[&b].schedule.as_ref().unwrap().next,
        Some(day("2026-11-15"))
    );
}

#[test]
fn scale_2000_rules_20000_entries_and_events() {
    let mut seed = State::default();
    let source = rule(&mut seed, "规模", Some("100"));
    let rule = seed.rules[&source].clone();
    let account = seed.accounts[rule.account.as_ref().unwrap()].clone();
    let mut s = State::default();
    for n in 0..2000 {
        let mut r = rule.clone();
        r.id = format!("load-rule-{n}");
        let mut ac = account.clone();
        ac.id = format!("load-account-{n}");
        r.account = Some(ac.id.clone());
        s.accounts.insert(ac.id.clone(), ac.clone());
        for i in 0..10 {
            let planned = day("2025-01-01") + chrono::Duration::days(i);
            let oid = format!("{}@{planned}", r.id);
            s.occurrences.insert(
                oid.clone(),
                Occurrence {
                    id: oid.clone(),
                    rule: r.id.clone(),
                    planned,
                    actual: Some(planned),
                    completed: Some(planned),
                    window_end: planned,
                    status: Status::Completed,
                },
            );
            let eid = format!("load-entry-{n}-{i}");
            s.ledger.insert(
                eid.clone(),
                Entry {
                    id: eid.clone(),
                    key: eid,
                    account: ac.id.clone(),
                    rule: Some(r.id.clone()),
                    occurrence: Some(oid),
                    delta: 10,
                    date: planned,
                    source: "confirmed".into(),
                    note: String::new(),
                    corrected_by: None,
                    origin: None,
                },
            );
        }
        s.rules.insert(r.id.clone(), r);
    }
    let start = std::time::Instant::now();
    s.validate().unwrap();
    let validation_ms = start.elapsed().as_millis();
    let start = std::time::Instant::now();
    let snapshot = s.snapshot(now()).unwrap();
    let snapshot_ms = start.elapsed().as_millis();
    assert_eq!(snapshot["summary"]["rules"], 2000);
    assert_eq!(
        snapshot["account_views"]["load-account-0"]["formatted"],
        "1.00"
    );
    assert!(
        validation_ms < 5000,
        "validation regressed: {validation_ms}ms"
    );
    assert!(snapshot_ms < 10000, "snapshot regressed: {snapshot_ms}ms");
    println!(
        "scale: 2000 rules / 20000 entries / 20000 events; validate={validation_ms}ms snapshot={snapshot_ms}ms; profile=debug"
    );
}

#[test]
fn processing_schedule_edits_are_explicitly_blocked() {
    let mut s = State::default();
    let a = rule(&mut s, "A", None);
    run(
        &mut s,
        "event",
        json!({"rule":a,"planned":"2026-11-15","status":"processing"}),
    );
    assert!(
        s.apply(
            "save_rule",
            json!({"id":a,"name":"A","schedule":null}),
            now()
        )
        .is_err()
    );
    assert_eq!(
        s.rules[&a].schedule.as_ref().unwrap().next,
        Some(day("2026-11-15"))
    );
}
#[test]
fn deleted_accounts_stop_home_attention_and_configuration_does_not_change_balance() {
    let mut s = State::default();
    let a = rule(&mut s, "A", Some("10"));
    let aid = s.rules[&a].account.clone().unwrap();
    run(
        &mut s,
        "configure_account",
        json!({"id":aid,"name":"余额","low":"15","reference":"100"}),
    );
    assert_eq!(s.balance(&aid).unwrap(), 1000);
    assert_eq!(s.snapshot(now()).unwrap()["summary"]["low_accounts"], 1);
    run(&mut s, "delete_rule", json!({"id":a}));
    assert_eq!(s.snapshot(now()).unwrap()["summary"]["low_accounts"], 0);
    assert_eq!(s.balance(&aid).unwrap(), 1000);
}

#[test]
fn dissolved_group_can_merge_again_and_archive_old_authority() {
    let mut s = State::default();
    let a = rule(&mut s, "A", Some("100"));
    let b = rule(&mut s, "B", None);
    let c = rule(&mut s, "C", Some("200"));
    let old = merge(&mut s, &[a.clone(), b.clone()], json!({}));
    run(&mut s, "delete_rule", json!({"id":b}));
    let chosen = s.rules[&c].account.clone().unwrap();
    let unit = s.accounts[&chosen].unit.key();
    let group = merge(&mut s, &[a, c], json!({unit:chosen}));
    assert!(s.groups[&old].deleted);
    assert_eq!(
        s.balance(s.groups[&group].accounts.first().unwrap())
            .unwrap(),
        20000
    );
    s.validate().unwrap();
}
#[test]
fn full_length_names_can_be_copied_without_losing_data() {
    let mut s = State::default();
    let a = rule(&mut s, &"名".repeat(200), Some("100"));
    let copied = run(&mut s, "copy", json!({"id":a}))
        .as_str()
        .unwrap()
        .to_string();
    assert_eq!(s.rules[&copied].name.chars().count(), 200);
    assert_eq!(
        s.balance(s.rules[&copied].account.as_ref().unwrap())
            .unwrap(),
        10000
    );
}

#[test]
fn closed_events_without_recording_never_change_resources() {
    for resource_mode in ["change", "reset"] {
        for (status, record) in [("skipped", true), ("failed", true), ("completed", false)] {
            let mut s = State::default();
            let mut draft = json!({
                "name":"月度额度",
                "schedule":{"anchor":"2026-10-15","next":"2026-11-15","cycle":{"kind":"monthly"}},
                "new_account":{"name":"余额","unit":{"kind":"money","code":"CNY","precision":2},"initial":"100"}
            });
            draft[resource_mode] = json!(if resource_mode == "change" {
                "-20"
            } else {
                "200"
            });
            let rid = run(&mut s, "save_rule", draft)
                .as_str()
                .unwrap()
                .to_string();
            let aid = s.rules[&rid].account.clone().unwrap();
            let ledger_before = serde_json::to_value(&s.ledger).unwrap();
            let request =
                json!({"rule":rid,"planned":"2026-11-15","status":status,"record":record});
            s.apply("event", request.clone(), day("2026-11-20"))
                .unwrap();
            s.apply("event", request, day("2026-11-20")).unwrap();
            assert_eq!(s.balance(&aid).unwrap(), 10000, "{resource_mode}: {status}");
            assert_eq!(serde_json::to_value(&s.ledger).unwrap(), ledger_before);
            assert_eq!(s.occurrences.len(), 1);
            assert_eq!(
                s.rules[&rid].schedule.as_ref().unwrap().next,
                Some(day("2026-12-15"))
            );
        }
    }
}

#[test]
fn copied_classification_survives_source_and_tag_deletion() {
    let mut s = State::default();
    let project = run(&mut s, "save_project", json!({"name":"固定支出"}))
        .as_str()
        .unwrap()
        .to_string();
    let tag = run(&mut s, "save_tag", json!({"name":"订阅"}))
        .as_str()
        .unwrap()
        .to_string();
    let draft = json!({"name":"云盘","project":project,"tags":[tag]});
    let rid = run(&mut s, "save_rule", draft.clone())
        .as_str()
        .unwrap()
        .to_string();
    let template = run(
        &mut s,
        "save_template",
        json!({"name":"云盘模板","config":draft}),
    )
    .as_str()
    .unwrap()
    .to_string();
    let copied = run(&mut s, "copy", json!({"id":rid}))
        .as_str()
        .unwrap()
        .to_string();
    run(&mut s, "delete_rule", json!({"id":rid}));
    run(&mut s, "delete_tag", json!({"id":tag}));
    assert!(s.rules[&rid].tags.is_empty());
    assert!(s.rules[&copied].tags.is_empty());
    assert_eq!(s.templates[&template].config["tags"], json!([]));
    assert_eq!(s.rules[&copied].project.as_deref(), Some(project.as_str()));
    assert!(s.projects.contains_key(&project));
    let before = serde_json::to_value(&s).unwrap();
    assert!(
        s.apply("delete_project", json!({"id":project}), now())
            .is_err()
    );
    assert_eq!(serde_json::to_value(&s).unwrap(), before);
    run(&mut s, "copy", json!({"id":copied}));
    s.validate().unwrap();
}

#[test]
fn restart_early_completion_is_atomic_and_cannot_reopen_a_closed_period() {
    let mut s = State::default();
    let rid = rule(&mut s, "重置", Some("100"));
    s.rules
        .get_mut(&rid)
        .unwrap()
        .schedule
        .as_mut()
        .unwrap()
        .cycle = Cycle::Restart { days: 26 };
    let before = s.clone();
    assert!(
        s.apply(
            "event",
            json!({"rule":rid,"planned":"2026-11-15","actual":"2026-10-20","status":"completed"}),
            now()
        )
        .is_err()
    );
    assert_eq!(s, before);
    s.apply(
        "event",
        json!({"rule":rid,"planned":"2026-11-15","actual":"2026-11-15","status":"completed"}),
        day("2026-11-15"),
    )
    .unwrap();
    let before = s.clone();
    assert!(s.apply("save_rule", json!({"id":rid,"name":"重置","schedule":{"anchor":"2026-10-15","next":"2026-11-15","cycle":{"kind":"restart","days":26}}}), day("2026-11-15")).is_err());
    assert_eq!(s, before);
}

#[test]
fn old_stuck_schedule_can_be_edited_forward_without_rewriting_history() {
    let mut s = State::default();
    let rid = rule(&mut s, "旧规则", None);
    s.apply(
        "event",
        json!({"rule":rid,"planned":"2026-11-15","status":"completed"}),
        day("2026-11-15"),
    )
    .unwrap();
    s.rules
        .get_mut(&rid)
        .unwrap()
        .schedule
        .as_mut()
        .unwrap()
        .next = Some(day("2026-11-15"));
    s.validate().unwrap(); // Legacy snapshots remain readable; new commands enforce the invariant.
    let history = s.occurrences.clone();
    s.apply("save_rule", json!({"id":rid,"name":"已修复","schedule":{"anchor":"2026-10-15","next":"2026-12-15","cycle":{"kind":"monthly"}}}), day("2026-11-15")).unwrap();
    assert_eq!(s.occurrences, history);
}

#[test]
fn future_actual_and_reversing_a_reversal_are_rejected_atomically() {
    let mut s = State::default();
    let rid = rule(&mut s, "余额", Some("100"));
    let before = s.clone();
    assert!(
        s.apply(
            "event",
            json!({"rule":rid,"planned":"2026-11-15","actual":"2030-01-01","status":"completed"}),
            now()
        )
        .is_err()
    );
    assert_eq!(s, before);
    let aid = s.rules[&rid].account.clone().unwrap();
    let eid = resource(&mut s, &aid, "consume", "30", "use");
    run(
        &mut s,
        "correct_entry",
        json!({"id":eid,"delta":"-20","reason":"修正"}),
    );
    let reverse = s
        .ledger
        .values()
        .find(|e| e.source == "correction_reverse")
        .unwrap()
        .id
        .clone();
    let before = s.clone();
    assert!(
        s.apply(
            "correct_entry",
            json!({"id":reverse,"delta":"0","reason":"不应允许"}),
            now()
        )
        .is_err()
    );
    assert_eq!(s, before);
    assert_eq!(s.balance(&aid).unwrap(), 8000);
}

#[test]
fn manual_replay_across_midnight_and_noop_settings_preserve_revision() {
    let mut s = State::default();
    let rid = rule(&mut s, "余额", Some("100"));
    let aid = s.rules[&rid].account.clone().unwrap();
    let request =
        json!({"account":aid,"action":"set","amount":"50","key":"set-once","note":"对账"});
    let first = run(&mut s, "resource", request.clone());
    let before = s.clone();
    assert_eq!(
        s.apply("resource", request, day("2026-10-26")).unwrap(),
        first
    );
    assert_eq!(s, before);
    run(&mut s, "setting", json!({"key":"theme","value":"dark"}));
    let revision = s.revision;
    run(&mut s, "setting", json!({"key":"theme","value":"dark"}));
    assert_eq!(s.revision, revision);
    assert!(
        s.apply("setting", json!({"key":"theme","value":"invalid"}), now())
            .is_err()
    );
}

#[test]
fn merge_preserves_common_project_and_confirms_every_destination_change() {
    let mut s = State::default();
    let pid = run(&mut s, "save_project", json!({"name":"家庭"}));
    let a = run(&mut s, "save_rule", json!({"name":"甲","project":pid}));
    let b = run(&mut s, "save_rule", json!({"name":"乙","project":pid}));
    assert!(
        s.apply(
            "merge",
            json!({"rules":[a,b],"name":"移出","project":null}),
            now()
        )
        .is_err()
    );
    let gid = run(&mut s, "merge", json!({"rules":[a,b],"name":"保留归属"}));
    assert_eq!(
        s.groups[gid.as_str().unwrap()].project.as_deref(),
        pid.as_str()
    );
    let mut t = State::default();
    let pid = run(&mut t, "save_project", json!({"name":"家庭"}));
    let a = run(&mut t, "save_rule", json!({"name":"甲","project":pid}));
    let b = run(&mut t, "save_rule", json!({"name":"乙","project":pid}));
    let gid = run(
        &mut t,
        "merge",
        json!({"rules":[a,b],"name":"确认移出","project":null,"confirm_project":true}),
    );
    assert_eq!(t.groups[gid.as_str().unwrap()].project, None);
}

#[test]
fn filtered_reorder_preserves_unselected_slots_and_rejects_invalid_items() {
    let mut s = State::default();
    let ids: Vec<_> = (0..5)
        .map(|i| {
            run(&mut s, "save_rule", json!({"name":format!("规则{i}")}))
                .as_str()
                .unwrap()
                .to_string()
        })
        .collect();
    run(&mut s, "reorder", json!({"ids":[ids[3],ids[1]]}));
    let mut ordered: Vec<_> = s.rules.values().collect();
    ordered.sort_by_key(|r| r.order);
    assert_eq!(
        ordered.iter().map(|r| r.id.clone()).collect::<Vec<_>>(),
        vec![
            ids[0].clone(),
            ids[3].clone(),
            ids[2].clone(),
            ids[1].clone(),
            ids[4].clone()
        ]
    );
    let before = s.clone();
    for list in [json!([ids[1], ids[1]]), json!(["missing"])] {
        assert!(s.apply("reorder", json!({"ids":list}), now()).is_err());
        assert_eq!(s, before);
    }
}

#[test]
fn canonical_dates_and_forecast_exact_boundary() {
    for invalid in [
        " 2026-1-01",
        "+2026-1-01",
        "0000-01-01",
        "9999-01-01",
        "2026-02-29",
    ] {
        assert!(date(invalid).is_err(), "{invalid}");
    }
    assert!(date("0001-01-01").is_ok());
    let mut s = State::default();
    let rid = rule(&mut s, "一次", Some("100"));
    let r = s.rules.get_mut(&rid).unwrap();
    r.schedule.as_mut().unwrap().cycle = Cycle::Once;
    r.change = Some(-100);
    let aid = s.rules[&rid].account.clone().unwrap();
    assert_eq!(s.forecast(&aid, now(), 0).unwrap()["truncated"], true);
    assert_eq!(s.forecast(&aid, now(), 1).unwrap()["truncated"], false);
    let before = s.clone();
    s.forecast(&aid, now(), 241).unwrap();
    assert_eq!(s, before);
}

#[test]
fn catalog_commands_keep_classifications_and_templates_consistent() {
    let mut s = State::default();
    let p = run(&mut s, "save_project", json!({"name":"原名"}));
    run(&mut s, "save_project", json!({"id":p,"name":"新名"}));
    let tag = run(&mut s, "save_tag", json!({"name":"分类","color":"123ABC"}));
    assert!(
        s.apply("save_tag", json!({"name":"无效","color":"xyz"}), now())
            .is_err()
    );
    let a = run(&mut s, "save_rule", json!({"name":"甲","tags":[tag]}));
    let b = run(&mut s, "save_rule", json!({"name":"乙"}));
    let template = run(
        &mut s,
        "save_template",
        json!({"name":"模板","config":{"name":"规则","tags":[tag]}}),
    );
    let g = run(&mut s, "merge", json!({"rules":[a,b],"name":"组合"}));
    run(&mut s, "move", json!({"id":g,"project":p}));
    assert_eq!(s.rules[a.as_str().unwrap()].project.as_deref(), p.as_str());
    assert!(
        s.apply("move", json!({"id":a,"project":null}), now())
            .is_err()
    );
    run(&mut s, "rename_group", json!({"id":g,"name":"新组合"}));
    run(&mut s, "delete_tag", json!({"id":tag}));
    assert!(s.rules[a.as_str().unwrap()].tags.is_empty());
    assert_eq!(
        s.templates[template.as_str().unwrap()].config["tags"],
        json!([])
    );
    run(&mut s, "delete_template", json!({"id":template}));
    s.validate().unwrap();
}
