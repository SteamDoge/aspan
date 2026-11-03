// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

use crate::{calendar::Schedule, *};
use chrono::{Duration, NaiveDate};
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet};

impl State {
    pub fn balances(&self) -> Result<BTreeMap<String, i64>> {
        let mut totals: BTreeMap<_, i128> = self.accounts.keys().map(|a| (a.clone(), 0)).collect();
        for e in self.ledger.values() {
            let n = totals.get_mut(&e.account).ok_or("账本账户不存在")?;
            *n = n.checked_add(e.delta.into()).ok_or("余额超出范围")?;
        }
        totals
            .into_iter()
            .map(|(id, n)| Ok((id, i64::try_from(n).map_err(|_| "余额超出范围")?)))
            .collect()
    }
    pub fn snapshot(&self, today: NaiveDate) -> Result<Value> {
        let balances = self.balances()?;
        let active_accounts: BTreeSet<_> = self
            .rules
            .values()
            .filter(|r| !r.deleted)
            .filter_map(|r| r.account.as_ref())
            .chain(
                self.groups
                    .values()
                    .filter(|g| !g.deleted)
                    .flat_map(|g| g.accounts.iter()),
            )
            .collect();
        let mut accounts = BTreeMap::new();
        for ac in self.accounts.values() {
            let balance = balances[&ac.id];
            accounts.insert(ac.id.clone(),json!({"active":active_accounts.contains(&ac.id),"balance":balance,"formatted":ac.unit.format(balance),"unit":ac.unit.code,"low":ac.low.is_some_and(|n|balance<=n),"progress":ac.reference.map(|total|(balance as f64/total as f64).clamp(0.,1.))}));
        }
        let mut previous_events: BTreeMap<&str, NaiveDate> = BTreeMap::new();
        for o in self.occurrences.values().filter(|o| o.status.closed()) {
            let Some(r) = self.rules.get(&o.rule) else {
                continue;
            };
            if r.schedule
                .as_ref()
                .and_then(|s| s.next)
                .is_some_and(|p| o.planned < p)
            {
                let value = if matches!(
                    r.schedule.as_ref().map(|s| &s.cycle),
                    Some(calendar::Cycle::Restart { .. })
                ) {
                    o.actual.unwrap_or(o.planned)
                } else {
                    o.planned
                };
                previous_events
                    .entry(&o.rule)
                    .and_modify(|d| *d = (*d).max(value))
                    .or_insert(value);
            }
        }
        let mut views = BTreeMap::new();
        for r in self.rules.values().filter(|r| !r.deleted) {
            let planned = r.schedule.as_ref().and_then(|s| s.next);
            let occurrence = planned.and_then(|d| self.occurrences.get(&format!("{}@{d}", r.id)));
            let remaining = planned.map(|d| (d - today).num_days());
            let phase = if occurrence.is_some_and(|o| o.status == Status::Processing) {
                "processing"
            } else {
                match remaining {
                    None => "idle",
                    Some(d)
                        if d > 0
                            && d <= i64::from(*r.reminder.before.iter().max().unwrap_or(&0)) =>
                    {
                        "reminder"
                    }
                    Some(d) if d > 0 => "normal",
                    Some(0) => "due",
                    Some(d) if -d <= i64::from(r.reminder.grace_days) => "grace",
                    _ => "overdue",
                }
            };
            let previous = previous_events
                .get(r.id.as_str())
                .copied()
                .or(r.schedule.as_ref().map(|s| s.anchor));
            let time_progress = planned.zip(previous).map(|(end, start)| {
                if end == start {
                    if today >= end { 1. } else { 0. }
                } else {
                    ((today - start).num_days() as f64 / (end - start).num_days() as f64)
                        .clamp(0., 1.)
                }
            });
            let next_reminder = planned.and_then(|p| next_reminder(r, p, today));
            let segments=planned.zip(previous).map(|(p,start)| {let end=p.checked_add_signed(Duration::days(r.reminder.grace_days.into())).unwrap_or(p);let full=(end-start).num_days().max(1) as f64;let before=i64::from(*r.reminder.before.iter().max().unwrap_or(&0)).min((p-start).num_days().max(0));json!({"normal":((p-start).num_days()-before).max(0) as f64/full,"reminder":before as f64/full,"grace":r.reminder.grace_days as f64/full})});
            views.insert(r.id.clone(),json!({"planned":planned,"remaining_days":remaining,"phase":phase,"time_progress":time_progress,"next_reminder":next_reminder,"segments":segments,"account":r.account.as_ref().and_then(|a|accounts.get(a))}));
        }
        let mut group_tags = BTreeMap::new();
        for g in self.groups.values().filter(|g| !g.deleted) {
            let tags: BTreeSet<_> = self
                .rules
                .values()
                .filter(|r| !r.deleted && r.group.as_ref() == Some(&g.id))
                .flat_map(|r| r.tags.iter().cloned())
                .collect();
            group_tags.insert(g.id.clone(), tags);
        }
        Ok(
            json!({"state":self,"views":views,"account_views":accounts,"group_tags":group_tags,"today":today,"money_units":MONEY_UNITS.iter().copied().collect::<BTreeMap<_,_>>(),"summary":{"rules":views.len(),"attention":views.values().filter(|v|["reminder","due","grace","overdue","processing"].contains(&v["phase"].as_str().unwrap_or(""))).count(),"low_accounts":self.accounts.values().filter(|ac|!ac.archived && active_accounts.contains(&ac.id) && accounts[&ac.id]["low"]==true).count()}}),
        )
    }
    /// Pure projection, bounded horizon and count. Never calls apply or inserts ledger entries.
    pub fn forecast(&self, account: &str, today: NaiveDate, limit: usize) -> Result<Value> {
        let ac = self.accounts.get(account).ok_or("账户不存在")?;
        let mut balance = self.balance(account)?;
        let mut cursors: Vec<(String, Schedule)> = self
            .rules
            .values()
            .filter(|r| {
                !r.deleted
                    && r.account.as_deref() == Some(account)
                    && (r.change.is_some() || r.reset.is_some())
            })
            .filter_map(|r| {
                r.schedule
                    .clone()
                    .filter(|s| !matches!(s.cycle, calendar::Cycle::Restart { .. }))
                    .map(|s| (r.id.clone(), s))
            })
            .collect();
        let mut events = vec![];
        const MAX_FORECAST_EVENTS: usize = 240;
        for _ in 0..limit.min(MAX_FORECAST_EVENTS) {
            let next = cursors
                .iter()
                .enumerate()
                .filter_map(|(i, (_, s))| s.next.map(|d| (i, d)))
                .min_by_key(|(i, d)| (*d, cursors[*i].0.clone()));
            let Some((i, planned)) = next else { break };
            let (rid, s) = &mut cursors[i];
            let r = &self.rules[rid];
            let delta = if let Some(target) = r.reset {
                target.checked_sub(balance).ok_or("预测超出范围")?
            } else {
                r.change.unwrap_or(0)
            };
            balance = balance.checked_add(delta).ok_or("预测超出范围")?;
            events.push(json!({"rule":rid,"planned":planned,"overdue":planned<today,"delta":ac.unit.format(delta),"balance":ac.unit.format(balance),"insufficient":balance<0}));
            s.next = s.after(planned, planned)?;
        }
        Ok(
            json!({"account":account,"events":events,"assumption":"仅按当前固定计划估算；不含未确认充值、价格变化和操作后重置周期；不代表真实交易","truncated":cursors.iter().any(|(_, s)| s.next.is_some())}),
        )
    }
    pub fn reminder_plan(&self, today: NaiveDate) -> Value {
        let horizon = today
            .checked_add_signed(Duration::days(90))
            .unwrap_or(today);
        let mut notifications = vec![];
        for r in self.rules.values().filter(|r| !r.deleted) {
            if let Some(planned) = r.schedule.as_ref().and_then(|s| s.next) {
                let oid = format!("{}@{planned}", r.id);
                if self
                    .occurrences
                    .get(&oid)
                    .is_some_and(|o| o.status.closed())
                {
                    continue;
                }
                for day in reminder_dates(r, planned, today, horizon) {
                    notifications.push(json!({"id":format!("{oid}:{day}"),"rule":r.id,"occurrence":oid,"date":day,"title":r.name}));
                }
            }
        }
        json!({"notifications":notifications,"delivery":"plan_only","note":"日期提醒计划已计算；当前版本尚未接入操作系统通知"})
    }
}

fn reminder_dates(
    r: &Rule,
    planned: NaiveDate,
    from: NaiveDate,
    to: NaiveDate,
) -> BTreeSet<NaiveDate> {
    let mut dates: BTreeSet<_> = r
        .reminder
        .before
        .iter()
        .filter_map(|n| planned.checked_sub_signed(Duration::days((*n).into())))
        .collect();
    dates.retain(|d| *d >= from && *d <= to);
    if r.reminder.on_day && planned >= from && planned <= to {
        dates.insert(planned);
    }
    if let Some(interval) = r.reminder.repeat_days.filter(|n| *n > 0) {
        let start = -i64::from(*r.reminder.before.iter().max().unwrap_or(&0));
        let end = i64::from(r.reminder.grace_days);
        let lower = (from - planned).num_days().max(start);
        let upper = (to - planned).num_days().min(end);
        let step = i64::from(interval);
        let first = start + (lower - start + step - 1) / step * step;
        for offset in (first..=upper).step_by(interval as usize) {
            if let Some(day) = planned.checked_add_signed(Duration::days(offset)) {
                dates.insert(day);
            }
        }
    }
    dates
}

fn next_reminder(r: &Rule, planned: NaiveDate, today: NaiveDate) -> Option<NaiveDate> {
    let mut next = r
        .reminder
        .before
        .iter()
        .filter_map(|n| planned.checked_sub_signed(Duration::days((*n).into())))
        .filter(|d| *d >= today)
        .min();
    if r.reminder.on_day && planned >= today {
        next = Some(next.map_or(planned, |d| d.min(planned)));
    }
    if let Some(interval) = r.reminder.repeat_days.filter(|n| *n > 0) {
        let start = -i64::from(*r.reminder.before.iter().max().unwrap_or(&0));
        let end = i64::from(r.reminder.grace_days);
        let step = i64::from(interval);
        let lower = (today - planned).num_days().max(start);
        let first = start + (lower - start + step - 1) / step * step;
        if first <= end
            && let Some(day) = planned.checked_add_signed(Duration::days(first))
        {
            next = Some(next.map_or(day, |d| d.min(day)));
        }
    }
    next
}
