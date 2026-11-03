// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

use std::io::{self, BufRead};
fn main() {
    for line in io::stdin().lock().lines() {
        match line {
            Ok(s) => println!("{}", aspan_bridge::invoke(&s)),
            Err(e) => {
                eprintln!("{e}");
                std::process::exit(1);
            }
        }
    }
}
