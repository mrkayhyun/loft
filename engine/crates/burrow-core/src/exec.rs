//! Execute a reviewed plan.
//!
//! A plan comes back from a client and is treated as untrusted input. Each
//! item is re-validated against the catalog rule it claims, the guard, the
//! running-app hold, and its recorded `(dev, ino)` before reaching the sink.

use std::collections::HashSet;
use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::time::Instant;

use serde::{Deserialize, Serialize};

use crate::process::held_by;
use crate::rules::{Action, Catalog, Category};
use crate::sink::Sink;
use crate::{Guard, Sizer};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanItem {
    pub category: String,
    pub path: String,
    pub dev: u64,
    pub ino: u64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CleanPlan {
    pub items: Vec<PlanItem>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(tag = "status", rename_all = "snake_case")]
pub enum Outcome {
    Removed { bytes: u64 },
    WouldRemove { bytes: u64 },
    Skipped { reason: String },
    Failed { error: String },
}

#[derive(Debug, Clone, Serialize)]
pub struct ItemResult {
    pub category: String,
    pub path: String,
    #[serde(flatten)]
    pub outcome: Outcome,
}

#[derive(Debug, Clone, Serialize)]
pub struct CleanReport {
    pub dry_run: bool,
    pub freed_bytes: u64,
    pub removed: usize,
    pub skipped: usize,
    pub failed: usize,
    pub duration_ms: u64,
    pub results: Vec<ItemResult>,
}

pub struct ExecContext<'a> {
    pub catalog: &'a Catalog,
    pub guard: &'a Guard,
    pub sink: &'a dyn Sink,
    pub running: &'a HashSet<String>,
    pub dry_run: bool,
}

pub fn execute(
    context: &ExecContext<'_>,
    plan: &CleanPlan,
    on_item: &dyn Fn(&ItemResult),
) -> CleanReport {
    let started = Instant::now();
    let mut results = Vec::with_capacity(plan.items.len());
    let sizer = Sizer::default();
    for item in &plan.items {
        let outcome = match validate(context, item) {
            Ok((path, category)) => apply(context, &sizer, &path, category),
            Err(reason) => Outcome::Skipped { reason },
        };
        let result = ItemResult {
            category: item.category.clone(),
            path: item.path.clone(),
            outcome,
        };
        on_item(&result);
        results.push(result);
    }
    summarize(context.dry_run, started, results)
}

fn validate<'c>(
    context: &ExecContext<'c>,
    item: &PlanItem,
) -> Result<(PathBuf, &'c Category), String> {
    let category = context
        .catalog
        .find(&item.category)
        .ok_or_else(|| format!("unknown category {}", item.category))?;
    let path = PathBuf::from(&item.path);
    let home = context.guard.home();
    if !category.covers(&path, home) {
        return Err("path is not covered by its category".into());
    }
    context.guard.check(&path).map_err(|e| e.to_string())?;
    let held = held_by(&category.running_apps, context.running);
    if !held.is_empty() {
        return Err(format!("{} is running", held.join(", ")));
    }
    let meta = fs::symlink_metadata(&path).map_err(|_| "no longer exists".to_string())?;
    if meta.dev() != item.dev || meta.ino() != item.ino {
        return Err("changed since the scan".into());
    }
    if category.action == Action::Delete && path.parent() != Some(&home.join(".Trash")) {
        return Err("permanent delete is limited to the Trash".into());
    }
    Ok((path, category))
}

fn apply(context: &ExecContext<'_>, sizer: &Sizer, path: &Path, category: &Category) -> Outcome {
    let bytes = sizer.measure(path).bytes;
    if context.dry_run {
        return Outcome::WouldRemove { bytes };
    }
    let result = match category.action {
        Action::Trash => context.sink.trash(path),
        Action::Delete => context.sink.delete(path),
    };
    match result {
        Ok(()) => Outcome::Removed { bytes },
        Err(error) => Outcome::Failed {
            error: error.to_string(),
        },
    }
}

fn summarize(dry_run: bool, started: Instant, results: Vec<ItemResult>) -> CleanReport {
    let mut report = CleanReport {
        dry_run,
        freed_bytes: 0,
        removed: 0,
        skipped: 0,
        failed: 0,
        duration_ms: 0,
        results: Vec::new(),
    };
    for result in &results {
        match &result.outcome {
            Outcome::Removed { bytes } | Outcome::WouldRemove { bytes } => {
                report.removed += 1;
                report.freed_bytes += bytes;
            }
            Outcome::Skipped { .. } => report.skipped += 1,
            Outcome::Failed { .. } => report.failed += 1,
        }
    }
    report.results = results;
    report.duration_ms = started.elapsed().as_millis() as u64;
    report
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    /// Test sink that moves items into a private folder instead of the Trash.
    struct FolderSink {
        bin: PathBuf,
        calls: Mutex<Vec<(String, PathBuf)>>,
    }

    impl Sink for FolderSink {
        fn trash(&self, path: &Path) -> anyhow::Result<()> {
            self.calls.lock().unwrap().push(("trash".into(), path.into()));
            fs::rename(path, self.bin.join(path.file_name().unwrap()))?;
            Ok(())
        }
        fn delete(&self, path: &Path) -> anyhow::Result<()> {
            self.calls.lock().unwrap().push(("delete".into(), path.into()));
            fs::remove_dir_all(path)?;
            Ok(())
        }
    }

    struct Fixture {
        _home: tempfile::TempDir,
        _bin: tempfile::TempDir,
        guard: Guard,
        sink: FolderSink,
        catalog: Catalog,
    }

    fn fixture() -> Fixture {
        let home = tempfile::tempdir().unwrap();
        let bin = tempfile::tempdir().unwrap();
        let guard = Guard::new(home.path()).unwrap();
        let sink = FolderSink {
            bin: bin.path().to_path_buf(),
            calls: Mutex::new(Vec::new()),
        };
        Fixture {
            _home: home,
            _bin: bin,
            guard,
            sink,
            catalog: Catalog::builtin(),
        }
    }

    fn make_item(fx: &Fixture, category: &str, relative: &str) -> PlanItem {
        let path = fx.guard.home().join(relative);
        fs::create_dir_all(&path).unwrap();
        fs::write(path.join("blob"), vec![0u8; 4096]).unwrap();
        let meta = fs::symlink_metadata(&path).unwrap();
        PlanItem {
            category: category.into(),
            path: path.to_string_lossy().into_owned(),
            dev: meta.dev(),
            ino: meta.ino(),
        }
    }

    fn run(fx: &Fixture, items: Vec<PlanItem>, running: HashSet<String>, dry_run: bool) -> CleanReport {
        let context = ExecContext {
            catalog: &fx.catalog,
            guard: &fx.guard,
            sink: &fx.sink,
            running: &running,
            dry_run,
        };
        execute(&context, &CleanPlan { items }, &|_| {})
    }

    #[test]
    fn trashes_valid_item() {
        let fx = fixture();
        let item = make_item(&fx, "user-caches", "Library/Caches/com.example");
        let report = run(&fx, vec![item.clone()], HashSet::new(), false);
        assert_eq!(report.removed, 1);
        assert!(report.freed_bytes > 0);
        assert!(!Path::new(&item.path).exists());
    }

    #[test]
    fn dry_run_touches_nothing() {
        let fx = fixture();
        let item = make_item(&fx, "user-caches", "Library/Caches/com.example");
        let report = run(&fx, vec![item.clone()], HashSet::new(), true);
        assert!(matches!(report.results[0].outcome, Outcome::WouldRemove { .. }));
        assert!(Path::new(&item.path).exists());
        assert!(fx.sink.calls.lock().unwrap().is_empty());
    }

    #[test]
    fn rejects_path_not_covered_by_claimed_category() {
        let fx = fixture();
        let item = make_item(&fx, "user-caches", "Documents/Taxes");
        let report = run(&fx, vec![item.clone()], HashSet::new(), false);
        assert_eq!(report.skipped, 1);
        assert!(Path::new(&item.path).exists());
    }

    #[test]
    fn rejects_replaced_file() {
        let fx = fixture();
        let item = make_item(&fx, "user-caches", "Library/Caches/com.example");
        fs::remove_dir_all(&item.path).unwrap();
        fs::create_dir_all(&item.path).unwrap();
        let report = run(&fx, vec![item.clone()], HashSet::new(), false);
        assert_eq!(
            report.results[0].outcome,
            Outcome::Skipped {
                reason: "changed since the scan".into()
            }
        );
    }

    #[test]
    fn holds_items_while_owner_app_runs() {
        let fx = fixture();
        let item = make_item(&fx, "xcode-derived-data", "Library/Developer/Xcode/DerivedData/App-abc");
        let running: HashSet<String> = ["xcode".to_string()].into();
        let report = run(&fx, vec![item.clone()], running, false);
        assert_eq!(report.skipped, 1);
        assert!(Path::new(&item.path).exists());
    }

    #[test]
    fn trash_category_deletes_permanently() {
        let fx = fixture();
        let item = make_item(&fx, "trash", ".Trash/old-thing");
        let report = run(&fx, vec![item.clone()], HashSet::new(), false);
        assert_eq!(report.removed, 1);
        assert_eq!(fx.sink.calls.lock().unwrap()[0].0, "delete");
    }
}
