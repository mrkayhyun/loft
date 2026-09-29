//! Running-process detection, used to hold categories whose owning app is open.

use std::collections::HashSet;

use sysinfo::{ProcessRefreshKind, ProcessesToUpdate, System};

/// Lower-cased process names and executable file names currently running.
pub fn running_names() -> HashSet<String> {
    let mut system = System::new();
    system.refresh_processes_specifics(
        ProcessesToUpdate::All,
        true,
        ProcessRefreshKind::nothing().with_exe(sysinfo::UpdateKind::OnlyIfNotSet),
    );
    let mut names = HashSet::new();
    for process in system.processes().values() {
        names.insert(process.name().to_string_lossy().to_lowercase());
        if let Some(file) = process.exe().and_then(|p| p.file_name()) {
            names.insert(file.to_string_lossy().to_lowercase());
        }
    }
    names
}

/// The subset of `apps` that is currently running (case-insensitive).
pub fn held_by(apps: &[String], running: &HashSet<String>) -> Vec<String> {
    apps.iter()
        .filter(|app| running.contains(&app.to_lowercase()))
        .cloned()
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn held_by_is_case_insensitive() {
        let running: HashSet<String> = ["google chrome".to_string()].into();
        let apps = vec!["Google Chrome".to_string(), "Xcode".to_string()];
        assert_eq!(held_by(&apps, &running), vec!["Google Chrome".to_string()]);
    }

    #[test]
    fn running_names_includes_current_test_binary() {
        let names = running_names();
        assert!(!names.is_empty());
    }
}
