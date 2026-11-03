// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

use crate::Result;
use chrono::{Datelike, Duration, NaiveDate};
use serde::{Deserialize, Serialize};

pub fn date(s: &str) -> Result<NaiveDate> {
    if s.len() != 10 {
        return Err("日期必须为 YYYY-MM-DD".into());
    }
    let parsed = NaiveDate::parse_from_str(s, "%Y-%m-%d").map_err(|_| "日期无效")?;
    if !(1..=9998).contains(&parsed.year()) || parsed.format("%Y-%m-%d").to_string() != s {
        return Err("日期必须为 0001—9998 年的 YYYY-MM-DD".into());
    }
    Ok(parsed)
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Cycle {
    Once,
    Daily,
    Weekly,
    Monthly,
    Yearly,
    Interval { days: u32 },
    Restart { days: u32 },
    Calendar { dates: Vec<NaiveDate> },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Schedule {
    pub anchor: NaiveDate,
    /// Calendar recurrence day/month can differ from the visual period start.
    #[serde(default)]
    pub calendar_anchor: Option<NaiveDate>,
    pub next: Option<NaiveDate>,
    pub cycle: Cycle,
}

impl Schedule {
    pub fn validate(&self) -> Result<()> {
        if self
            .calendar_anchor
            .is_some_and(|d| d.year() < 1 || d.year() > 9998)
        {
            return Err("日历锚点无效".into());
        }
        if self.anchor.year() < 1
            || self.anchor.year() > 9998
            || self
                .next
                .is_some_and(|d| d < self.anchor || d.year() > 9998)
        {
            return Err("日期范围为 0001—9998，事件不能早于起点".into());
        }
        match &self.cycle {
            Cycle::Monthly
                if self.next.is_some_and(|d| {
                    clamped(
                        d.year(),
                        d.month(),
                        self.calendar_anchor.unwrap_or(self.anchor).day(),
                    )
                    .ok()
                        != Some(d)
                }) =>
            {
                return Err("本期日期与月周期锚点不一致".into());
            }
            Cycle::Yearly
                if self.next.is_some_and(|d| {
                    let a = self.calendar_anchor.unwrap_or(self.anchor);
                    clamped(d.year(), a.month(), a.day()).ok() != Some(d)
                }) =>
            {
                return Err("本期日期与年周期锚点不一致".into());
            }
            Cycle::Interval { days } | Cycle::Restart { days } if *days == 0 || *days > 36500 => {
                return Err("间隔须为 1—36500 天".into());
            }
            Cycle::Calendar { dates }
                if dates.is_empty()
                    || dates.windows(2).any(|w| w[0] >= w[1])
                    || dates.iter().any(|d| *d < self.anchor || d.year() > 9998)
                    || self.next.is_some_and(|d| !dates.contains(&d)) =>
            {
                return Err("日历日期须升序、去重且不早于起点".into());
            }
            _ => (),
        }
        Ok(())
    }
    /// Clamp to target month's last day while preserving the original anchor day.
    pub fn after(&self, planned: NaiveDate, actual: NaiveDate) -> Result<Option<NaiveDate>> {
        let anchor = self.calendar_anchor.unwrap_or(self.anchor);
        let add_days = |base: NaiveDate, days: u32| {
            base.checked_add_signed(Duration::days(days.into()))
                .ok_or("日期超出范围".to_string())
        };
        let result = match &self.cycle {
            Cycle::Once => None,
            Cycle::Daily => Some(add_days(planned, 1)?),
            Cycle::Weekly => Some(add_days(planned, 7)?),
            Cycle::Interval { days } => Some(add_days(planned, *days)?),
            Cycle::Restart { days } => {
                let next = add_days(actual, *days)?;
                if next <= planned {
                    return Err("实际日期过早：重置后的下一期必须晚于本期计划日".into());
                }
                Some(next)
            }
            Cycle::Monthly => {
                let (year, month) = if planned.month() == 12 {
                    (planned.year() + 1, 1)
                } else {
                    (planned.year(), planned.month() + 1)
                };
                Some(clamped(year, month, anchor.day())?)
            }
            Cycle::Yearly => Some(clamped(planned.year() + 1, anchor.month(), anchor.day())?),
            Cycle::Calendar { dates } => dates.iter().copied().find(|d| *d > planned),
        };
        if result.is_some_and(|d| d.year() > 9998) {
            return Err("日期超出支持范围".into());
        }
        Ok(result)
    }
}
fn clamped(year: i32, month: u32, day: u32) -> Result<NaiveDate> {
    (1..=day)
        .rev()
        .find_map(|d| NaiveDate::from_ymd_opt(year, month, d))
        .ok_or("日期超出范围".into())
}
