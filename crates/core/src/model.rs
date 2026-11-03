// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

use crate::{Result, calendar::Schedule};
use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "snake_case")]
pub enum ResourceKind {
    Money,
    Count,
    Quantity,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
pub struct Unit {
    pub kind: ResourceKind,
    pub code: String,
    pub precision: u8,
}
pub const MONEY_UNITS: &[(&str, u8)] = &[
    ("CNY", 2),
    ("USD", 2),
    ("HKD", 2),
    ("EUR", 2),
    ("GBP", 2),
    ("JPY", 0),
    ("KWD", 3),
];

impl Unit {
    pub fn validate(&self) -> Result<()> {
        if self.code.trim().is_empty() || self.code.len() > 30 || self.precision > 6 {
            return Err("单位或精度无效".into());
        }
        if self.kind == ResourceKind::Count && self.precision != 0 {
            return Err("次数只能使用整数".into());
        }
        if self.kind == ResourceKind::Money {
            let precision = MONEY_UNITS
                .iter()
                .find(|(code, _)| *code == self.code)
                .map(|(_, p)| *p)
                .ok_or("当前支持 CNY/USD/HKD/EUR/GBP/JPY/KWD")?;
            if self.precision != precision {
                return Err("币种精度不匹配".into());
            }
        }
        Ok(())
    }
    pub fn parse(&self, value: &str) -> Result<i64> {
        self.validate()?;
        let negative = value.starts_with('-');
        let raw = if negative { &value[1..] } else { value };
        let pieces: Vec<_> = raw.split('.').collect();
        if pieces.len() > 2
            || pieces[0].is_empty()
            || !pieces
                .iter()
                .all(|s| !s.is_empty() && s.bytes().all(|c| c.is_ascii_digit()))
        {
            return Err("请输入十进制数值，不支持指数记法".into());
        }
        let fraction = pieces.get(1).copied().unwrap_or("");
        if fraction.len() > self.precision as usize {
            return Err("小数位数超出账户精度".into());
        }
        let whole: i128 = pieces[0].parse().map_err(|_| "数值过大")?;
        let frac: i128 = if fraction.is_empty() {
            0
        } else {
            fraction.parse().map_err(|_| "数值过大")?
        };
        let amount = whole
            .checked_mul(10i128.pow(self.precision.into()))
            .and_then(|n| {
                n.checked_add(frac * 10i128.pow(self.precision as u32 - fraction.len() as u32))
            })
            .ok_or("数值过大")?;
        i64::try_from(if negative { -amount } else { amount }).map_err(|_| "数值过大".into())
    }
    pub fn format(&self, amount: i64) -> String {
        let n = i128::from(amount).abs();
        let scale = 10i128.pow(self.precision.into());
        let sign = if amount < 0 { "-" } else { "" };
        if self.precision == 0 {
            format!("{sign}{n}")
        } else {
            format!(
                "{sign}{}.{:0width$}",
                n / scale,
                n % scale,
                width = self.precision as usize
            )
        }
    }
    pub fn key(&self) -> String {
        format!("{:?}:{}:{}", self.kind, self.code, self.precision)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Project {
    pub id: String,
    pub name: String,
    pub order: i64,
}
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Tag {
    pub id: String,
    pub name: String,
    pub color: String,
}
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Account {
    pub id: String,
    pub name: String,
    pub unit: Unit,
    pub reference: Option<i64>,
    pub low: Option<i64>,
    pub archived: bool,
}
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Reminder {
    pub before: Vec<u32>,
    pub on_day: bool,
    pub grace_days: u32,
    pub repeat_days: Option<u32>,
}
impl Default for Reminder {
    fn default() -> Self {
        Self {
            before: vec![7, 1],
            on_day: true,
            grace_days: 0,
            repeat_days: None,
        }
    }
}
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Rule {
    pub id: String,
    pub name: String,
    pub notes: String,
    pub icon: String,
    pub project: Option<String>,
    pub group: Option<String>,
    pub tags: BTreeSet<String>,
    pub schedule: Option<Schedule>,
    pub reminder: Reminder,
    pub account: Option<String>,
    pub change: Option<i64>,
    pub reset: Option<i64>,
    pub pinned: bool,
    pub order: i64,
    pub deleted: bool,
}
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Group {
    pub id: String,
    pub name: String,
    pub project: Option<String>,
    pub order: i64,
    pub accounts: BTreeSet<String>,
    pub archived_accounts: BTreeSet<String>,
    #[serde(default)]
    pub historical_members: BTreeSet<String>,
    pub deleted: bool,
}
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Status {
    Pending,
    Processing,
    Completed,
    Skipped,
    Failed,
}
impl Status {
    pub fn closed(&self) -> bool {
        matches!(self, Self::Completed | Self::Skipped | Self::Failed)
    }
}
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Occurrence {
    pub id: String,
    pub rule: String,
    pub planned: NaiveDate,
    pub actual: Option<NaiveDate>,
    pub completed: Option<NaiveDate>,
    pub window_end: NaiveDate,
    pub status: Status,
}
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Entry {
    pub id: String,
    pub key: String,
    pub account: String,
    pub rule: Option<String>,
    pub occurrence: Option<String>,
    pub delta: i64,
    pub date: NaiveDate,
    pub source: String,
    pub note: String,
    pub corrected_by: Option<String>,
    pub origin: Option<String>,
}
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct History {
    pub id: String,
    pub subject: String,
    pub action: String,
    pub date: NaiveDate,
    pub detail: String,
}
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Template {
    pub id: String,
    pub name: String,
    pub config: serde_json::Value,
}
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct State {
    pub schema: u32,
    pub revision: u64,
    pub rules: BTreeMap<String, Rule>,
    pub projects: BTreeMap<String, Project>,
    pub groups: BTreeMap<String, Group>,
    pub tags: BTreeMap<String, Tag>,
    pub accounts: BTreeMap<String, Account>,
    pub ledger: BTreeMap<String, Entry>,
    pub occurrences: BTreeMap<String, Occurrence>,
    pub history: Vec<History>,
    pub templates: BTreeMap<String, Template>,
    pub settings: BTreeMap<String, String>,
}
impl Default for State {
    fn default() -> Self {
        Self {
            schema: 1,
            revision: 0,
            rules: BTreeMap::new(),
            projects: BTreeMap::new(),
            groups: BTreeMap::new(),
            tags: BTreeMap::new(),
            accounts: BTreeMap::new(),
            ledger: BTreeMap::new(),
            occurrences: BTreeMap::new(),
            history: vec![],
            templates: BTreeMap::new(),
            settings: BTreeMap::new(),
        }
    }
}
