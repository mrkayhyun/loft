//! Terminal rendering for humans. JSON consumers never reach this module.

use burrow_core::analyze::DirReport;
use burrow_core::apps::{AppInfo, Leftover, UninstallReport};
use burrow_core::exec::{CleanReport, ItemResult, Outcome};
use burrow_core::scan::ScanReport;
use burrow_core::status::Status;
use burrow_core::Catalog;

const UNITS: &[&str] = &["B", "KB", "MB", "GB", "TB"];
const UNIT_STEP: f64 = 1000.0;
const BOLD: &str = "\x1b[1m";
const DIM: &str = "\x1b[2m";
const GREEN: &str = "\x1b[32m";
const YELLOW: &str = "\x1b[33m";
const RESET: &str = "\x1b[0m";

/// Decimal units, matching Finder.
pub fn bytes(value: u64) -> String {
    let mut size = value as f64;
    let mut unit = 0;
    while size >= UNIT_STEP && unit < UNITS.len() - 1 {
        size /= UNIT_STEP;
        unit += 1;
    }
    if unit == 0 {
        format!("{value} B")
    } else {
        format!("{size:.1} {}", UNITS[unit])
    }
}

pub fn scan(report: &ScanReport) {
    println!("{BOLD}Reclaimable space{RESET}  {DIM}({} ms){RESET}\n", report.duration_ms);
    for category in &report.categories {
        let mark = if category.selected { "●" } else { "○" };
        let held = if category.held_by.is_empty() {
            String::new()
        } else {
            format!("  {YELLOW}held: {} running{RESET}", category.held_by.join(", "))
        };
        println!(
            "  {mark} {:<28} {:>10}  {DIM}{} items{RESET}{held}",
            category.name,
            bytes(category.bytes),
            category.items.len()
        );
    }
    println!("\n  {BOLD}Total{RESET} {:>34}", bytes(report.total_bytes));
    println!("\n{DIM}Nothing was removed. Use Burrow.app or `burrow clean --plan` to clean.{RESET}");
}

fn outcome_line(result: &ItemResult) -> String {
    match &result.outcome {
        Outcome::Removed { bytes: b } => format!("{GREEN}✓{RESET} {} {DIM}{}{RESET}", result.path, bytes(*b)),
        Outcome::WouldRemove { bytes: b } => format!("· {} {DIM}{}{RESET}", result.path, bytes(*b)),
        Outcome::Skipped { reason } => format!("{YELLOW}–{RESET} {} {DIM}({reason}){RESET}", result.path),
        Outcome::Failed { error } => format!("{YELLOW}✗{RESET} {} {DIM}({error}){RESET}", result.path),
    }
}

pub fn clean(report: &CleanReport) {
    for result in &report.results {
        println!("  {}", outcome_line(result));
    }
    let verb = if report.dry_run { "Would free" } else { "Freed" };
    println!(
        "\n{BOLD}{verb} {}{RESET}  {DIM}{} removed · {} skipped · {} failed{RESET}",
        bytes(report.freed_bytes),
        report.removed,
        report.skipped,
        report.failed
    );
}

pub fn apps(list: &[AppInfo]) {
    for app in list {
        let note = match (&app.protected, app.running) {
            (Some(reason), _) => format!("  {DIM}{reason}{RESET}"),
            (None, true) => format!("  {YELLOW}running{RESET}"),
            _ => String::new(),
        };
        println!("  {:<36} {DIM}{:<12} {}{RESET}{note}", app.name, app.version, app.bundle_id);
    }
}

pub fn leftovers(items: &[Leftover]) {
    if items.is_empty() {
        println!("No leftovers found.");
        return;
    }
    for item in items {
        println!("  {:>10}  {:<20} {}", bytes(item.bytes), item.kind, item.path);
    }
}

pub fn uninstall(report: &UninstallReport) {
    for result in &report.results {
        println!("  {}", outcome_line(result));
    }
    let verb = if report.dry_run { "Would free" } else { "Freed" };
    println!("\n{BOLD}{verb} {}{RESET}", bytes(report.freed_bytes));
}

pub fn analyze(report: &DirReport) {
    println!("{BOLD}{}{RESET}  {}  {DIM}({} ms){RESET}\n", report.path, bytes(report.bytes), report.duration_ms);
    let total = report.bytes.max(1) as f64;
    for node in report.children.iter().take(30) {
        let share = node.bytes as f64 / total;
        let bar = "█".repeat((share * 30.0).round() as usize);
        let suffix = if node.is_dir { "/" } else { "" };
        println!("  {:>10}  {:<30} {}{suffix}", bytes(node.bytes), bar, node.name);
    }
}

pub fn status(status: &Status) {
    let mem = &status.memory;
    println!("{BOLD}{}{RESET}  {DIM}{}{RESET}", status.hostname, status.os_version);
    println!("  CPU     {:>5.1}%   load {:.2} {:.2} {:.2}", status.cpu.usage, status.cpu.load[0], status.cpu.load[1], status.cpu.load[2]);
    println!("  Memory  {} / {}", bytes(mem.used), bytes(mem.total));
    if let Some(disk) = &status.disk {
        println!("  Disk    {} free of {}", bytes(disk.available), bytes(disk.total));
    }
    println!(
        "  Network ↓ {}/s  ↑ {}/s",
        bytes(status.network.rx_bytes_per_sec),
        bytes(status.network.tx_bytes_per_sec)
    );
}

pub fn rules(catalog: &Catalog) {
    for category in &catalog.categories {
        println!("  {:<24} {DIM}{}{RESET}", category.id, category.paths.join(", "));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formats_decimal_units() {
        assert_eq!(bytes(0), "0 B");
        assert_eq!(bytes(999), "999 B");
        assert_eq!(bytes(1_500), "1.5 KB");
        assert_eq!(bytes(2_300_000_000), "2.3 GB");
    }
}
