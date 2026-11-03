// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

pub mod calendar;
pub mod model;
mod operations;
pub mod view;
pub use model::*;
pub type Result<T> = std::result::Result<T, String>;
pub fn id() -> String {
    uuid::Uuid::new_v4().to_string()
}
