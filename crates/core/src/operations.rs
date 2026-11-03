// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

use crate::{calendar::date, *};
use chrono::{Duration, NaiveDate};
use serde::Deserialize;
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Deserialize)]
struct Draft {
    name: String,
    #[serde(default)]
    notes: String,
    #[serde(default = "default_icon")]
    icon: String,
    #[serde(default)]
    project: Option<String>,
    #[serde(default)]
    tags: BTreeSet<String>,
    #[serde(default)]
    schedule: Option<calendar::Schedule>,
    #[serde(default)]
    reminder: Reminder,
    #[serde(default)]
    account: Option<String>,
    #[serde(default)]
    new_account: Option<AccountDraft>,
    #[serde(default)]
    change: Option<String>,
    #[serde(default)]
    reset: Option<String>,
    #[serde(default)]
    pinned: bool,
}
#[derive(Deserialize)]
struct AccountDraft {
    name: String,
    unit: Unit,
    initial: String,
    reference: Option<String>,
    low: Option<String>,
}
fn default_icon() -> String {
    "schedule".into()
}
fn decode<T: serde::de::DeserializeOwned>(value: Value) -> Result<T> {
    serde_json::from_value(value).map_err(|e| format!("参数格式错误：{e}"))
}
fn text<'a>(a: &'a Value, key: &str) -> Result<&'a str> {
    a[key].as_str().ok_or(format!("缺少 {key}"))
}
fn name(s: &str) -> Result<String> {
    let s = s.trim();
    if s.is_empty() || s.chars().count() > 200 {
        Err("名称须为 1—200 个字符".into())
    } else {
        Ok(s.into())
    }
}
fn copy_name(s: &str) -> String {
    format!("{} 副本", s.chars().take(197).collect::<String>())
}

impl State {
    pub fn balance(&self, account: &str) -> Result<i64> {
        if !self.accounts.contains_key(account) {
            return Err("账户不存在".into());
        }
        let total = self
            .ledger
            .values()
            .filter(|e| e.account == account)
            .try_fold(0i128, |n, e| {
                n.checked_add(e.delta.into()).ok_or("余额超出范围")
            })?;
        i64::try_from(total).map_err(|_| "余额超出范围".into())
    }
    fn history(&mut self, subject: &str, action: &str, on: NaiveDate, detail: String) {
        self.history.push(History {
            id: id(),
            subject: subject.into(),
            action: action.into(),
            date: on,
            detail,
        });
    }
    fn insert_entry(&mut self, entry: Entry) -> Result<String> {
        if let Some(old) = self.ledger.values().find(|e| e.key == entry.key) {
            if old.account == entry.account
                && old.rule == entry.rule
                && old.occurrence == entry.occurrence
                && old.delta == entry.delta
                && old.date == entry.date
                && old.source == entry.source
                && old.note == entry.note
            {
                return Ok(old.id.clone());
            }
            return Err("同一操作标识不能用于不同流水".into());
        }
        let account = self.accounts.get(&entry.account).ok_or("账户不存在")?;
        let balance = self
            .balance(&entry.account)?
            .checked_add(entry.delta)
            .ok_or("余额超出范围")?;
        if account.unit.kind == ResourceKind::Count && balance < 0 {
            return Err("剩余次数不足".into());
        }
        let result = entry.id.clone();
        self.ledger.insert(entry.id.clone(), entry);
        Ok(result)
    }
    /// All commands are atomic even when called without the SQLite adapter.
    pub fn apply(&mut self, method: &str, args: Value, on: NaiveDate) -> Result<Value> {
        let mut candidate = self.clone();
        let result = candidate.execute(method, args, on)?;
        candidate.validate()?;
        if candidate == *self {
            return Ok(result);
        }
        candidate.revision = self.revision.checked_add(1).ok_or("版本超出范围")?;
        *self = candidate;
        Ok(result)
    }
    fn execute(&mut self, method: &str, a: Value, on: NaiveDate) -> Result<Value> {
        match method {
            "save_rule" => self.save_rule(a, on),
            "resource" => self.resource(a, on),
            "correct_entry" => self.correct_entry(a, on),
            "configure_account" => {
                let aid = text(&a, "id")?.to_string();
                let ac = self
                    .accounts
                    .get_mut(&aid)
                    .filter(|ac| !ac.archived)
                    .ok_or("账户不存在或已归档")?;
                ac.name = name(text(&a, "name")?)?;
                ac.reference = a["reference"]
                    .as_str()
                    .map(|s| ac.unit.parse(s))
                    .transpose()?;
                ac.low = a["low"].as_str().map(|s| ac.unit.parse(s)).transpose()?;
                self.history(
                    &aid,
                    "configure_account",
                    on,
                    "更新参考总量与不足阈值；不改变实际余额".into(),
                );
                Ok(Value::Null)
            }
            "event" => self.event(a, on),
            "merge" => self.merge(a, on),
            "copy" => self.copy(a, on),
            "delete_rule" => {
                let rid = text(&a, "id")?.to_string();
                let r = self.rules.get_mut(&rid).ok_or("规则不存在")?;
                if r.deleted {
                    return Ok(json!(rid));
                }
                r.deleted = true;
                let group = r.group.take();
                if let Some(gid) = group {
                    self.groups
                        .get_mut(&gid)
                        .ok_or("合并关系错误")?
                        .historical_members
                        .insert(rid.clone());
                    let members: Vec<_> = self
                        .rules
                        .values()
                        .filter(|r| !r.deleted && r.group.as_ref() == Some(&gid))
                        .map(|r| r.id.clone())
                        .collect();
                    if members.len() <= 1 {
                        self.groups.get_mut(&gid).ok_or("合并关系错误")?.deleted = true;
                        for member in members {
                            let r = self.rules.get_mut(&member).unwrap();
                            r.group = None;
                        }
                    }
                }
                self.history(&rid, "delete_rule", on, "移入历史，账户流水保留".into());
                Ok(json!(rid))
            }
            "rename_group" => {
                let gid = text(&a, "id")?;
                let group = self
                    .groups
                    .get_mut(gid)
                    .filter(|g| !g.deleted)
                    .ok_or("合并条目不存在")?;
                group.name = name(text(&a, "name")?)?;
                Ok(Value::Null)
            }
            "save_project" => {
                let pid = a["id"].as_str().map(String::from).unwrap_or_else(id);
                if a["id"].is_string() && !self.projects.contains_key(&pid) {
                    return Err("项目不存在".into());
                }
                let order = self
                    .projects
                    .get(&pid)
                    .map(|p| p.order)
                    .unwrap_or(self.projects.len() as i64);
                self.projects.insert(
                    pid.clone(),
                    Project {
                        id: pid.clone(),
                        name: name(text(&a, "name")?)?,
                        order,
                    },
                );
                Ok(json!(pid))
            }
            "save_tag" => {
                let tid = a["id"].as_str().map(String::from).unwrap_or_else(id);
                if a["id"].is_string() && !self.tags.contains_key(&tid) {
                    return Err("标签不存在".into());
                }
                let color = a["color"].as_str().unwrap_or("2164C7").to_string();
                if color.len() != 6 || !color.bytes().all(|b| b.is_ascii_hexdigit()) {
                    return Err("标签颜色须为六位十六进制".into());
                }
                self.tags.insert(
                    tid.clone(),
                    Tag {
                        id: tid.clone(),
                        name: name(text(&a, "name")?)?,
                        color,
                    },
                );
                Ok(json!(tid))
            }
            "delete_tag" => {
                let tid = text(&a, "id")?;
                self.tags.remove(tid).ok_or("标签不存在")?;
                for r in self.rules.values_mut() {
                    r.tags.remove(tid);
                }
                for t in self.templates.values_mut() {
                    if let Some(tags) = t.config["tags"].as_array_mut() {
                        tags.retain(|v| v.as_str() != Some(tid));
                    }
                }
                Ok(Value::Null)
            }
            "save_template" => {
                let tid = a["id"].as_str().map(String::from).unwrap_or_else(id);
                let config = a["config"].clone();
                let _: Draft = decode(config.clone())?;
                self.templates.insert(
                    tid.clone(),
                    Template {
                        id: tid.clone(),
                        name: name(text(&a, "name")?)?,
                        config,
                    },
                );
                Ok(json!(tid))
            }
            "delete_template" => {
                self.templates.remove(text(&a, "id")?).ok_or("模板不存在")?;
                Ok(Value::Null)
            }
            "setting" => {
                let key = text(&a, "key")?;
                if !["theme", "palette", "sort", "descending"].contains(&key) {
                    return Err("设置项不存在".into());
                }
                let value = text(&a, "value")?;
                let valid = match key {
                    "theme" => ["system", "light", "dark"].contains(&value),
                    "palette" => ["lucent", "folio", "edition", "nocturne"].contains(&value),
                    "sort" => ["manual", "reminder", "event", "remaining"].contains(&value),
                    "descending" => ["true", "false"].contains(&value),
                    _ => false,
                };
                if !valid {
                    return Err("设置值无效".into());
                }
                self.settings.insert(key.into(), value.into());
                Ok(Value::Null)
            }
            "reorder" => {
                let ids: Vec<String> = decode(a["ids"].clone())?;
                if ids.iter().collect::<BTreeSet<_>>().len() != ids.len() {
                    return Err("排序包含重复条目".into());
                }
                // Reorder only the selected slots in the complete top-level list.
                // Filtering must never move unrelated entries or introduce ties.
                let mut full: Vec<_> = self
                    .rules
                    .values()
                    .filter(|r| !r.deleted && r.group.is_none())
                    .map(|r| (r.order, r.id.clone()))
                    .chain(
                        self.groups
                            .values()
                            .filter(|g| !g.deleted)
                            .map(|g| (g.order, g.id.clone())),
                    )
                    .collect();
                full.sort();
                if ids
                    .iter()
                    .any(|id| !full.iter().any(|(_, entity)| entity == id))
                {
                    return Err("排序条目不存在或不是独立条目".into());
                }
                let selected: BTreeSet<_> = ids.iter().collect();
                let mut reordered = ids.iter();
                for (_, entity) in &mut full {
                    if selected.contains(entity) {
                        *entity = reordered.next().unwrap().clone();
                    }
                }
                for (i, (_, entity)) in full.iter().enumerate() {
                    if let Some(r) = self.rules.get_mut(entity) {
                        r.order = i as i64;
                    } else if let Some(g) = self.groups.get_mut(entity) {
                        g.order = i as i64;
                    } else {
                        return Err("排序条目不存在".into());
                    }
                }
                Ok(Value::Null)
            }
            "move" => {
                let entity = text(&a, "id")?;
                let project: Option<String> = decode(a["project"].clone())?;
                if let Some(p) = &project
                    && !self.projects.contains_key(p)
                {
                    return Err("项目不存在".into());
                }
                if let Some(g) = self.groups.get_mut(entity) {
                    g.project = project.clone();
                    for r in self
                        .rules
                        .values_mut()
                        .filter(|r| r.group.as_deref() == Some(entity))
                    {
                        r.project = project.clone();
                    }
                } else {
                    let r = self.rules.get_mut(entity).ok_or("规则不存在")?;
                    if r.group.is_some() {
                        return Err("请移动整个合并条目".into());
                    }
                    r.project = project;
                }
                Ok(Value::Null)
            }
            _ => Err(format!("未知操作：{method}")),
        }
    }
    fn save_rule(&mut self, a: Value, on: NaiveDate) -> Result<Value> {
        let mut d: Draft = decode(a.clone())?;
        let rid = a["id"].as_str().map(String::from).unwrap_or_else(id);
        let old = self.rules.get(&rid).cloned();
        if a["id"].is_string() && old.is_none() {
            return Err("规则不存在".into());
        }
        if old.as_ref().is_some_and(|r| r.deleted) {
            return Err("已删除规则不能编辑".into());
        }
        if let Some(schedule) = &mut d.schedule {
            // The UI sends dates; preserving a monthly/yearly anchor is a core rule.
            if a["schedule"].get("calendar_anchor").is_none() {
                schedule.calendar_anchor = old
                    .as_ref()
                    .and_then(|r| r.schedule.as_ref())
                    .filter(|previous| {
                        previous.next == schedule.next && previous.cycle == schedule.cycle
                    })
                    .map(|previous| previous.calendar_anchor.unwrap_or(previous.anchor))
                    .or(schedule.next);
            }
            if schedule.next.is_some_and(|planned| {
                self.occurrences
                    .get(&format!("{rid}@{planned}"))
                    .is_some_and(|o| o.status.closed())
            }) {
                return Err("该计划日期已结束，请选择未处理的日期".into());
            }
        }
        if let Some(old) = &old
            && let Some(planned) = old.schedule.as_ref().and_then(|s| s.next)
        {
            let open = self
                .occurrences
                .get(&format!("{}@{planned}", old.id))
                .is_some_and(|o| !o.status.closed());
            if open
                && serde_json::to_value(&old.schedule).unwrap()
                    != serde_json::to_value(&d.schedule).unwrap()
            {
                return Err("本期正在处理，请先结束本期再修改周期".into());
            }
        }
        if d.account.is_some() && d.new_account.is_some() {
            return Err("不能同时选择账户和新建账户".into());
        }
        let account = if let Some(n) = d.new_account {
            if old.as_ref().is_some_and(|r| r.group.is_some()) {
                return Err("合并成员请使用共享账户".into());
            }
            n.unit.validate()?;
            let aid = id();
            let initial = n.unit.parse(&n.initial)?;
            let reference = n.reference.map(|v| n.unit.parse(&v)).transpose()?;
            let low = n.low.map(|v| n.unit.parse(&v)).transpose()?;
            self.accounts.insert(
                aid.clone(),
                Account {
                    id: aid.clone(),
                    name: name(&n.name)?,
                    unit: n.unit,
                    reference,
                    low,
                    archived: false,
                },
            );
            self.insert_entry(Entry {
                id: id(),
                key: format!("initial:{aid}"),
                account: aid.clone(),
                rule: Some(rid.clone()),
                occurrence: None,
                delta: initial,
                date: on,
                source: "initial".into(),
                note: "初始余量基准".into(),
                corrected_by: None,
                origin: None,
            })?;
            Some(aid)
        } else {
            d.account
        };
        if let Some(ref aid) = account {
            let ac = self.accounts.get(aid).ok_or("账户不存在")?;
            if ac.archived {
                return Err("归档账户不能重新关联".into());
            }
            if let Some(gid) = old.as_ref().and_then(|r| r.group.as_ref())
                && !self.groups[gid].accounts.contains(aid)
            {
                return Err("成员只能使用所属合并条目的账户".into());
            }
            // Sharing is intentional and only available through Group.
            if self.rules.values().any(|r| {
                !r.deleted
                    && r.id != rid
                    && r.account.as_ref() == Some(aid)
                    && r.group != old.as_ref().and_then(|o| o.group.clone())
            }) {
                return Err("请先合并规则，再共享账户".into());
            }
        }
        let parse = |s: Option<String>| -> Result<Option<i64>> {
            s.map(|v| {
                self.accounts
                    .get(account.as_ref().ok_or("请先启用资源账户")?)
                    .ok_or("账户不存在")?
                    .unit
                    .parse(&v)
            })
            .transpose()
        };
        let change = parse(d.change)?;
        let reset = parse(d.reset)?;
        if change.is_some() && reset.is_some() {
            return Err("周期变化和额度重置只能启用一个".into());
        }
        let group = old.as_ref().and_then(|r| r.group.clone());
        let project = if let Some(g) = &group {
            self.groups[g].project.clone()
        } else {
            d.project
        };
        let order = old
            .as_ref()
            .map(|r| r.order)
            .unwrap_or((self.rules.len() + self.groups.len()) as i64);
        self.rules.insert(
            rid.clone(),
            Rule {
                id: rid.clone(),
                name: name(&d.name)?,
                notes: d.notes,
                icon: d.icon,
                project,
                group,
                tags: d.tags,
                schedule: d.schedule,
                reminder: d.reminder,
                account,
                change,
                reset,
                pinned: d.pinned,
                order,
                deleted: false,
            },
        );
        self.history(
            &rid,
            if old.is_some() {
                "edit_rule"
            } else {
                "create_rule"
            },
            on,
            "保存规则配置；既有事件与流水保留".into(),
        );
        Ok(json!(rid))
    }
    fn resource(&mut self, a: Value, on: NaiveDate) -> Result<Value> {
        let aid = text(&a, "account")?.to_string();
        let ac = self.accounts.get(&aid).ok_or("账户不存在")?;
        if ac.archived {
            return Err("归档账户只允许审计纠正".into());
        }
        let key = text(&a, "key")?.to_string();
        if key.is_empty() {
            return Err("操作标识不能为空".into());
        }
        let amount = ac.unit.parse(text(&a, "amount")?)?;
        let action = text(&a, "action")?;
        let rule: Option<String> = decode(a["rule"].clone())?;
        if let Some(r) = &rule
            && self
                .rules
                .get(r)
                .is_none_or(|r| r.deleted || r.account.as_ref() != Some(&aid))
        {
            return Err("规则与账户不匹配".into());
        }
        // Setting an absolute balance must replay the first result, not compute another delta.
        let note = a["note"].as_str().unwrap_or("").to_string();
        let fingerprint = format!("{action}:{amount}:{note}");
        if let Some(e) = self.ledger.values().find(|e| e.key == key) {
            if e.account == aid && e.rule == rule && e.note == fingerprint && e.source == "manual" {
                return Ok(json!(e.id));
            }
            return Err("操作标识已用于其他请求".into());
        }
        let delta = match action {
            "add" if amount > 0 => amount,
            "consume" if amount > 0 => amount.checked_neg().ok_or("数值超出范围")?,
            "set" => amount
                .checked_sub(self.balance(&aid)?)
                .ok_or("数值超出范围")?,
            _ => return Err("增加或消耗必须大于零".into()),
        };
        let eid = self.insert_entry(Entry {
            id: id(),
            key,
            account: aid.clone(),
            rule,
            occurrence: None,
            delta,
            date: on,
            source: "manual".into(),
            note: fingerprint,
            corrected_by: None,
            origin: None,
        })?;
        self.history(&aid, "resource", on, eid.clone());
        Ok(json!(eid))
    }
    fn correct_entry(&mut self, a: Value, on: NaiveDate) -> Result<Value> {
        let eid = text(&a, "id")?;
        let e = self.ledger.get(eid).ok_or("流水不存在")?.clone();
        if e.source == "correction_reverse" {
            return Err("系统反向流水不能再次纠正，请纠正替代流水".into());
        }
        let reason = name(text(&a, "reason")?)?;
        let value = self.accounts[&e.account].unit.parse(text(&a, "delta")?)?;
        if let Some(replacement) = &e.corrected_by {
            let old = &self.ledger[replacement];
            if old.delta == value && old.note == reason {
                return Ok(json!(replacement));
            }
            return Err("该流水已纠正，请编辑替代流水".into());
        }
        let replacement = id();
        // Reverse and replace together. Count accounts may temporarily go below zero;
        // validate the final state, never commit the intermediate reversal.
        let reverse = Entry {
            id: id(),
            key: format!("reverse:{eid}"),
            account: e.account.clone(),
            rule: e.rule.clone(),
            occurrence: e.occurrence.clone(),
            delta: e.delta.checked_neg().ok_or("数值超出范围")?,
            date: on,
            source: "correction_reverse".into(),
            note: reason.clone(),
            corrected_by: None,
            origin: Some(eid.into()),
        };
        self.ledger.insert(reverse.id.clone(), reverse);
        let entry = Entry {
            id: replacement.clone(),
            key: format!("replace:{eid}"),
            account: e.account.clone(),
            rule: e.rule,
            occurrence: e.occurrence,
            delta: value,
            date: e.date,
            source: "correction".into(),
            note: reason,
            corrected_by: None,
            origin: Some(eid.into()),
        };
        self.ledger.insert(replacement.clone(), entry);
        self.ledger.get_mut(eid).unwrap().corrected_by = Some(replacement.clone());
        self.history(
            &e.account,
            "correct_entry",
            on,
            format!("{eid} → {replacement}"),
        );
        Ok(json!(replacement))
    }
    fn event(&mut self, a: Value, on: NaiveDate) -> Result<Value> {
        let rid = text(&a, "rule")?.to_string();
        let r = self
            .rules
            .get(&rid)
            .filter(|r| !r.deleted)
            .ok_or("规则不存在")?
            .clone();
        let planned = date(text(&a, "planned")?)?;
        let oid = format!("{rid}@{planned}");
        let status: Status = decode(a["status"].clone())?;
        if let Some(old) = self.occurrences.get(&oid)
            && old.status.closed()
        {
            if old.status == status {
                return Ok(json!(old));
            }
            return Err("该期已结束，历史流水请使用纠正操作".into());
        }
        let schedule = r.schedule.as_ref().ok_or("此规则没有时间周期")?;
        if schedule.next != Some(planned) {
            return Err("计划日期已变化，请刷新".into());
        }
        let actual = if let Some(s) = a["actual"].as_str() {
            date(s)?
        } else {
            on
        };
        if actual < schedule.anchor {
            return Err("实际日期不能早于周期起点".into());
        }
        if actual > on {
            return Err("实际日期不能晚于今天".into());
        }
        let window_end = planned
            .checked_add_signed(Duration::days(r.reminder.grace_days.into()))
            .ok_or("日期超出范围")?;
        let o = Occurrence {
            id: oid.clone(),
            rule: rid.clone(),
            planned,
            actual: if status == Status::Completed {
                Some(actual)
            } else {
                None
            },
            completed: if status.closed() { Some(on) } else { None },
            window_end,
            status: status.clone(),
        };
        self.occurrences.insert(oid.clone(), o.clone());
        if status == Status::Completed
            && a["record"].as_bool().unwrap_or(true)
            && let Some(aid) = &r.account
        {
            let delta = if let Some(target) = r.reset {
                Some(
                    target
                        .checked_sub(self.balance(aid)?)
                        .ok_or("数值超出范围")?,
                )
            } else {
                r.change
            };
            if let Some(delta) = delta {
                self.insert_entry(Entry {
                    id: id(),
                    key: format!("event:{oid}"),
                    account: aid.clone(),
                    rule: Some(rid.clone()),
                    occurrence: Some(oid),
                    delta,
                    date: actual,
                    source: "confirmed".into(),
                    note: "用户确认的本地事件记录".into(),
                    corrected_by: None,
                    origin: None,
                })?;
            }
        }
        if status.closed() {
            let next = schedule.after(
                planned,
                if status == Status::Completed {
                    actual
                } else {
                    planned
                },
            )?;
            self.rules
                .get_mut(&rid)
                .unwrap()
                .schedule
                .as_mut()
                .unwrap()
                .next = next;
        }
        self.history(&rid, "event", on, format!("{planned} {status:?}"));
        Ok(json!(o))
    }
    pub fn merge_plan(&self, ids: &[String]) -> Result<Value> {
        if ids.len() < 2 || ids.iter().collect::<BTreeSet<_>>().len() != ids.len() {
            return Err("请选择至少两条不同的独立规则".into());
        }
        let mut units: BTreeMap<String, Vec<Value>> = BTreeMap::new();
        let mut seen = BTreeSet::new();
        let mut projects = BTreeSet::new();
        for rid in ids {
            let r = self
                .rules
                .get(rid)
                .filter(|r| !r.deleted && r.group.is_none())
                .ok_or("只能合并独立规则")?;
            projects.insert(r.project.clone());
            if let Some(aid) = &r.account {
                if self.rules.values().any(|other| {
                    !other.deleted
                        && other.account.as_ref() == Some(aid)
                        && !ids.contains(&other.id)
                }) {
                    return Err("账户已被其他条目使用，请先整理关联".into());
                }
                if seen.insert(aid.clone()) {
                    let ac = &self.accounts[aid];
                    units.entry(ac.unit.key()).or_default().push(json!({"id":aid,"name":ac.name,"unit":ac.unit,"balance":self.balance(aid)?,"formatted":ac.unit.format(self.balance(aid)?)}));
                }
            }
        }
        let buckets: Vec<_> = units
            .into_iter()
            .map(|(unit, accounts)| {
                let balances: BTreeSet<_> = accounts
                    .iter()
                    .map(|a| a["balance"].as_i64().unwrap())
                    .collect();
                json!({"unit_key":unit,"conflict":balances.len()>1,"accounts":accounts})
            })
            .collect();
        Ok(
            json!({"buckets":buckets,"projects":projects,"requires_project_confirmation":projects.len()>1}),
        )
    }
    fn merge(&mut self, a: Value, on: NaiveDate) -> Result<Value> {
        let ids: Vec<String> = decode(a["rules"].clone())?;
        let plan = self.merge_plan(&ids)?;
        let project: Option<String> = if a.get("project").is_some() {
            decode(a["project"].clone())?
        } else {
            self.rules[&ids[0]].project.clone()
        };
        if ids.iter().any(|rid| self.rules[rid].project != project) && a["confirm_project"] != true
        {
            return Err("跨项目合并需要确认归属变化".into());
        }
        let gid = id();
        let mut accounts = BTreeSet::new();
        let mut archives = BTreeSet::new();
        let mut redirect = BTreeMap::new();
        for bucket in plan["buckets"].as_array().unwrap() {
            let options = bucket["accounts"].as_array().unwrap();
            let key = bucket["unit_key"].as_str().unwrap();
            let selected = if bucket["conflict"] == true {
                a["choices"][key]
                    .as_str()
                    .ok_or("余额不同，请明确选择一份已有余额")?
            } else {
                a["choices"][key]
                    .as_str()
                    .unwrap_or(options[0]["id"].as_str().unwrap())
            };
            if !options.iter().any(|o| o["id"] == selected) {
                return Err("选定账户不在合并范围内".into());
            }
            accounts.insert(selected.to_string());
            for option in options {
                let aid = option["id"].as_str().unwrap();
                redirect.insert(aid.to_string(), selected.to_string());
                if aid != selected {
                    archives.insert(aid.to_string());
                    self.accounts.get_mut(aid).unwrap().archived = true;
                }
            }
        }
        let order = ids.iter().map(|i| self.rules[i].order).min().unwrap();
        self.groups.insert(
            gid.clone(),
            Group {
                id: gid.clone(),
                name: name(text(&a, "name")?)?,
                project: project.clone(),
                order,
                accounts: accounts.clone(),
                archived_accounts: archives,
                historical_members: BTreeSet::new(),
                deleted: false,
            },
        );
        for rid in ids {
            let r = self.rules.get_mut(&rid).unwrap();
            r.group = Some(gid.clone());
            r.project = project.clone();
            r.account = match &r.account {
                Some(a) => Some(redirect[a].clone()),
                None if accounts.len() == 1 => accounts.first().cloned(),
                _ => None,
            };
        }
        self.history(&gid, "merge", on, plan.to_string());
        Ok(json!(gid))
    }
    fn copy(&mut self, a: Value, on: NaiveDate) -> Result<Value> {
        let entity = text(&a, "id")?;
        let group = self.groups.get(entity).filter(|g| !g.deleted).cloned();
        let mut rules: Vec<_> = if group.is_some() {
            self.rules
                .values()
                .filter(|r| !r.deleted && r.group.as_deref() == Some(entity))
                .cloned()
                .collect()
        } else {
            vec![
                self.rules
                    .get(entity)
                    .filter(|r| !r.deleted)
                    .ok_or("条目不存在")?
                    .clone(),
            ]
        };
        if let Some(g) = &group {
            for rid in &g.historical_members {
                rules.push(self.rules[rid].clone());
            }
        }
        let mut map: BTreeMap<String, String> =
            rules.iter().map(|r| (r.id.clone(), id())).collect();
        let mut aids: BTreeSet<_> = rules.iter().filter_map(|r| r.account.clone()).collect();
        for e in self
            .ledger
            .values()
            .filter(|e| e.rule.as_ref().is_some_and(|r| map.contains_key(r)))
        {
            aids.insert(e.account.clone());
        }
        if let Some(g) = &group {
            aids.extend(g.accounts.iter().chain(&g.archived_accounts).cloned());
        }
        // Keep historical source rules/occurrences for the copied ledger, including
        // deleted members. Extra sources are audit tombstones, never visible rules.
        let historical: BTreeSet<_> = self
            .ledger
            .values()
            .filter(|e| aids.contains(&e.account))
            .filter_map(|e| e.rule.clone())
            .filter(|rid| !map.contains_key(rid))
            .collect();
        for rid in historical {
            let mut r = self.rules[&rid].clone();
            r.deleted = true;
            r.group = None;
            if r.account.as_ref().is_some_and(|a| !aids.contains(a)) {
                r.account = None;
                r.change = None;
                r.reset = None;
            }
            map.insert(rid, id());
            rules.push(r);
        }
        for aid in &aids {
            map.insert(aid.clone(), id());
        }
        let gid = group.as_ref().map(|g| {
            let new = id();
            map.insert(g.id.clone(), new.clone());
            new
        });
        let occurrences: Vec<_> = self
            .occurrences
            .values()
            .filter(|o| map.contains_key(&o.rule))
            .cloned()
            .collect();
        for o in &occurrences {
            map.insert(o.id.clone(), format!("{}@{}", map[&o.rule], o.planned));
        }
        let entries: Vec<_> = self
            .ledger
            .values()
            .filter(|e| aids.contains(&e.account))
            .cloned()
            .collect();
        for e in &entries {
            map.insert(e.id.clone(), id());
        }
        let copy_key = id();
        for aid in aids {
            let mut ac = self.accounts[&aid].clone();
            ac.id = map[&aid].clone();
            self.accounts.insert(ac.id.clone(), ac);
        }
        for mut e in entries {
            let old = e.id.clone();
            e.id = map[&old].clone();
            e.account = map[&e.account].clone();
            e.rule = e.rule.and_then(|i| map.get(&i).cloned());
            e.occurrence = e.occurrence.and_then(|i| map.get(&i).cloned());
            e.corrected_by = e.corrected_by.and_then(|i| map.get(&i).cloned());
            e.origin = Some(format!("复制来源 {old}；{}", e.origin.unwrap_or_default()));
            e.key = format!("copy:{copy_key}:{}", e.key);
            self.ledger.insert(e.id.clone(), e);
        }
        for mut o in occurrences {
            o.id = map[&o.id].clone();
            o.rule = map[&o.rule].clone();
            self.occurrences.insert(o.id.clone(), o);
        }
        let first = map[&rules[0].id].clone();
        for mut r in rules {
            r.id = map[&r.id].clone();
            r.group = if r.deleted { None } else { gid.clone() };
            r.account = r.account.map(|i| map[&i].clone());
            r.order = (self.rules.len() + self.groups.len()) as i64;
            if group.is_none() {
                r.name = copy_name(&r.name);
            }
            self.rules.insert(r.id.clone(), r);
        }
        if let Some(mut g) = group {
            g.id = gid.clone().unwrap();
            g.name = copy_name(&g.name);
            g.accounts = g.accounts.into_iter().map(|i| map[&i].clone()).collect();
            g.historical_members = g
                .historical_members
                .into_iter()
                .map(|i| map[&i].clone())
                .collect();
            g.archived_accounts = g
                .archived_accounts
                .into_iter()
                .map(|i| map[&i].clone())
                .collect();
            g.order = (self.rules.len() + self.groups.len()) as i64;
            self.groups.insert(g.id.clone(), g);
        }
        let histories: Vec<_> = self
            .history
            .iter()
            .filter(|h| map.contains_key(&h.subject))
            .cloned()
            .collect();
        for mut h in histories {
            h.id = id();
            h.subject = map[&h.subject].clone();
            self.history.push(h);
        }
        let result = gid.unwrap_or(first);
        self.history(
            &result,
            "copy",
            on,
            format!("完整复制自 {entity}；未重放交易"),
        );
        Ok(json!(result))
    }
    pub fn validate(&self) -> Result<()> {
        if self.schema != 1 {
            return Err("不支持的数据版本，原数据保留".into());
        }
        let mut identities = BTreeSet::new();
        macro_rules! identities {
            ($items:expr) => {
                for (key, item) in $items {
                    if key != &item.id || key.is_empty() || !identities.insert(key.clone()) {
                        return Err("实体标识重复或不匹配".into());
                    }
                }
            };
        }
        identities!(&self.rules);
        identities!(&self.groups);
        identities!(&self.accounts);
        identities!(&self.projects);
        identities!(&self.tags);
        identities!(&self.ledger);
        identities!(&self.occurrences);
        identities!(&self.templates);
        for h in &self.history {
            if !identities.contains(&h.subject)
                || !identities.insert(h.id.clone())
                || h.id.is_empty()
            {
                return Err("历史标识重复".into());
            }
        }
        for r in self.rules.values() {
            name(&r.name)?;
            if let Some(p) = &r.project
                && !self.projects.contains_key(p)
            {
                return Err("项目引用无效".into());
            }
            if r.tags.iter().any(|t| !self.tags.contains_key(t)) {
                return Err("标签引用无效".into());
            }
            if let Some(s) = &r.schedule {
                s.validate()?;
            }
            if r.reminder.before.iter().any(|d| *d > 36500)
                || r.reminder.grace_days > 36500
                || r.reminder.repeat_days == Some(0)
                || r.reminder.repeat_days.is_some_and(|d| d > 36500)
            {
                return Err("提醒窗口无效".into());
            }
            if r.reminder.before.iter().collect::<BTreeSet<_>>().len() != r.reminder.before.len() {
                return Err("提醒节点重复".into());
            }
            if r.change.is_some() && r.reset.is_some() || r.reset.is_some_and(|n| n < 0) {
                return Err("资源变化配置无效".into());
            }
            if r.account.is_none() && (r.change.is_some() || r.reset.is_some()) {
                return Err("资源变化缺少账户".into());
            }
            if let Some(a) = &r.account {
                let ac = self.accounts.get(a).ok_or("账户引用无效")?;
                if !r.deleted && ac.archived {
                    return Err("有效规则关联了归档账户".into());
                }
            }
            if let Some(gid) = &r.group {
                let g = self.groups.get(gid).ok_or("合并条目引用无效")?;
                if !r.deleted
                    && (g.deleted
                        || r.project != g.project
                        || r.account.as_ref().is_some_and(|a| !g.accounts.contains(a)))
                {
                    return Err("合并成员关系无效".into());
                }
            }
        }
        for g in self.groups.values() {
            if g.historical_members
                .iter()
                .any(|rid| self.rules.get(rid).is_none_or(|r| !r.deleted))
            {
                return Err("历史成员引用无效".into());
            }
            name(&g.name)?;
            if g.project
                .as_ref()
                .is_some_and(|p| !self.projects.contains_key(p))
            {
                return Err("合并项目引用无效".into());
            }
            if !g.deleted
                && self
                    .rules
                    .values()
                    .filter(|r| !r.deleted && r.group.as_ref() == Some(&g.id))
                    .count()
                    < 2
            {
                return Err("合并条目至少有两个成员".into());
            }
            // Dissolved groups retain historical authority references even after those accounts are archived.
            for aid in &g.accounts {
                if self
                    .accounts
                    .get(aid)
                    .is_none_or(|ac| !g.deleted && ac.archived)
                {
                    return Err("共享账户引用无效".into());
                }
            }
            for aid in &g.archived_accounts {
                if self.accounts.get(aid).is_none_or(|ac| !ac.archived) {
                    return Err("历史账户引用无效".into());
                }
            }
        }
        let balances = self.balances()?;
        for ac in self.accounts.values() {
            ac.unit.validate()?;
            if ac.reference.is_some_and(|n| n <= 0) || ac.low.is_some_and(|n| n < 0) {
                return Err("参考总量须大于零，低余量阈值须非负".into());
            }
            if ac.unit.kind == ResourceKind::Count && balances[&ac.id] < 0 {
                return Err("剩余次数不能为负".into());
            }
        }
        let mut account_users: BTreeMap<&String, Vec<&Rule>> = BTreeMap::new();
        for r in self.rules.values().filter(|r| !r.deleted) {
            if let Some(aid) = &r.account {
                account_users.entry(aid).or_default().push(r);
            }
        }
        for users in account_users.values() {
            if users.len() > 1
                && (users[0].group.is_none() || users.iter().any(|r| r.group != users[0].group))
            {
                return Err("账户共享必须归属同一个合并条目".into());
            }
        }
        let mut keys = BTreeSet::new();
        for e in self.ledger.values() {
            if let Some(oid) = &e.occurrence {
                let o = self.occurrences.get(oid).ok_or("流水事件引用无效")?;
                if e.rule.as_ref() != Some(&o.rule) {
                    return Err("流水与事件所属规则不一致".into());
                }
            }
            if let Some(replacement) = &e.corrected_by {
                let corrected = self.ledger.get(replacement).ok_or("替代流水不存在")?;
                if corrected.account != e.account || corrected.source != "correction" {
                    return Err("纠正流水关系无效".into());
                }
            }
            if e.key.is_empty()
                || !keys.insert(&e.key)
                || !self.accounts.contains_key(&e.account)
                || e.rule.as_ref().is_some_and(|r| !self.rules.contains_key(r))
                || e.occurrence
                    .as_ref()
                    .is_some_and(|o| !self.occurrences.contains_key(o))
                || e.corrected_by
                    .as_ref()
                    .is_some_and(|i| !self.ledger.contains_key(i))
            {
                return Err("账本引用或幂等标识无效".into());
            }
        }
        for o in self.occurrences.values() {
            if !self.rules.contains_key(&o.rule)
                || o.id != format!("{}@{}", o.rule, o.planned)
                || o.window_end < o.planned
                || o.status.closed() != o.completed.is_some()
                || o.status == Status::Completed && o.actual.is_none()
            {
                return Err("事件历史引用或状态无效".into());
            }
        }
        for p in self.projects.values() {
            name(&p.name)?;
        }
        for t in self.tags.values() {
            name(&t.name)?;
            if t.color.len() != 6 || !t.color.bytes().all(|b| b.is_ascii_hexdigit()) {
                return Err("标签颜色无效".into());
            }
        }
        for t in self.templates.values() {
            name(&t.name)?;
            let d: Draft = decode(t.config.clone())?;
            name(&d.name)?;
            if d.account.is_some() {
                return Err("模板不能引用可变账户".into());
            }
            if let Some(s) = d.schedule {
                s.validate()?;
            }
            if d.tags.iter().any(|t| !self.tags.contains_key(t)) {
                return Err("模板标签无效".into());
            }
        }
        Ok(())
    }
}
