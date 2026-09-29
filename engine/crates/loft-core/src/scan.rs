//! Scan: expand the catalog into concrete targets and size them in parallel.
//!
//! Scanning never modifies the filesystem. Its output is a plan the client
//! reviews; each item carries `(dev, ino)` so execution can prove the file it
//! removes is the same one the user saw.

use std::collections::HashSet;
use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use rayon::prelude::*;
use serde::Serialize;

use crate::process::held_by;
use crate::rules::{Action, Catalog, Category, Group};
use crate::{Guard, Sizer};

const SECONDS_PER_DAY: u64 = 86_400;

#[derive(Debug, Clone, Serialize)]
pub struct Item {
    pub path: String,
    pub bytes: u64,
    pub files: u64,
    pub dev: u64,
    pub ino: u64,
    pub modified: u64,
    pub partial: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct CategoryReport {
    pub id: String,
    pub group: Group,
    pub name: String,
    pub summary: String,
    pub symbol: String,
    pub action: Action,
    pub selected: bool,
    pub held_by: Vec<String>,
    pub bytes: u64,
    pub files: u64,
    pub errors: u64,
    pub partial: bool,
    pub items: Vec<Item>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ScanReport {
    pub home: String,
    pub generated_at: u64,
    pub duration_ms: u64,
    pub total_bytes: u64,
    pub categories: Vec<CategoryReport>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ScanEvent {
    Started { candidates: usize },
    Progress { done: usize, total: usize, category: String, bytes: u64 },
}

pub struct ScanOptions {
    pub now: SystemTime,
    pub running: HashSet<String>,
    pub deadline: Option<Instant>,
}

impl Default for ScanOptions {
    fn default() -> Self {
        Self {
            now: SystemTime::now(),
            running: HashSet::new(),
            deadline: None,
        }
    }
}

struct Candidate {
    category: usize,
    path: PathBuf,
    meta: fs::Metadata,
}

pub fn scan(
    catalog: &Catalog,
    guard: &Guard,
    options: &ScanOptions,
    on_event: &(dyn Fn(ScanEvent) + Sync),
) -> ScanReport {
    let started = Instant::now();
    let candidates = collect_candidates(catalog, guard, options.now);
    on_event(ScanEvent::Started {
        candidates: candidates.len(),
    });

    let sizer = Sizer::new(options.deadline);
    let done = AtomicUsize::new(0);
    let bytes_so_far = AtomicU64::new(0);
    let total = candidates.len();
    let sized: Vec<(usize, Item, u64)> = candidates
        .par_iter()
        .map(|candidate| {
            let size = sizer.measure(&candidate.path);
            let running_bytes = bytes_so_far.fetch_add(size.bytes, Ordering::Relaxed) + size.bytes;
            let finished = done.fetch_add(1, Ordering::Relaxed) + 1;
            on_event(ScanEvent::Progress {
                done: finished,
                total,
                category: catalog.categories[candidate.category].id.clone(),
                bytes: running_bytes,
            });
            let item = Item {
                path: candidate.path.to_string_lossy().into_owned(),
                bytes: size.bytes,
                files: size.files,
                dev: candidate.meta.dev(),
                ino: candidate.meta.ino(),
                modified: unix_seconds(candidate.meta.modified().ok()),
                partial: size.partial,
            };
            (candidate.category, item, size.errors)
        })
        .collect();

    let categories = build_reports(catalog, &options.running, sized);
    ScanReport {
        home: guard.home().to_string_lossy().into_owned(),
        generated_at: crate::unix_now(),
        duration_ms: started.elapsed().as_millis() as u64,
        total_bytes: categories.iter().map(|c| c.bytes).sum(),
        categories,
    }
}

fn collect_candidates(catalog: &Catalog, guard: &Guard, now: SystemTime) -> Vec<Candidate> {
    let mut claimed: Vec<PathBuf> = Vec::new();
    let mut candidates = Vec::new();
    for (index, category) in catalog.categories.iter().enumerate() {
        let matches = expand_category(category, guard, now, &claimed);
        claimed.extend(matches.iter().map(|(path, _)| path.clone()));
        candidates.extend(matches.into_iter().map(|(path, meta)| Candidate {
            category: index,
            path,
            meta,
        }));
    }
    candidates
}

fn expand_category(
    category: &Category,
    guard: &Guard,
    now: SystemTime,
    claimed: &[PathBuf],
) -> Vec<(PathBuf, fs::Metadata)> {
    let Ok(exclusions) = category.exclusions() else {
        return Vec::new();
    };
    let min_age = category
        .min_age_days
        .map(|days| Duration::from_secs(days * SECONDS_PER_DAY));
    let mut seen = HashSet::new();
    let mut matches = Vec::new();
    for pattern in category.expanded_paths(guard.home()) {
        let Ok(paths) = glob::glob(&pattern) else {
            continue;
        };
        for path in paths.flatten() {
            if !seen.insert(path.clone()) {
                continue;
            }
            if path.file_name().is_some_and(|n| exclusions.is_match(n)) {
                continue;
            }
            if overlaps(&path, claimed) || guard.check(&path).is_err() {
                continue;
            }
            let Ok(meta) = fs::symlink_metadata(&path) else {
                continue;
            };
            if let Some(age) = min_age {
                if !is_older_than(&meta, age, now) {
                    continue;
                }
            }
            matches.push((path, meta));
        }
    }
    matches
}

fn overlaps(path: &Path, claimed: &[PathBuf]) -> bool {
    claimed
        .iter()
        .any(|c| path.starts_with(c) || c.starts_with(path))
}

fn is_older_than(meta: &fs::Metadata, age: Duration, now: SystemTime) -> bool {
    meta.modified()
        .ok()
        .and_then(|modified| now.duration_since(modified).ok())
        .is_some_and(|elapsed| elapsed >= age)
}

fn unix_seconds(time: Option<SystemTime>) -> u64 {
    time.and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn build_reports(
    catalog: &Catalog,
    running: &HashSet<String>,
    sized: Vec<(usize, Item, u64)>,
) -> Vec<CategoryReport> {
    let mut reports: Vec<CategoryReport> = catalog
        .categories
        .iter()
        .map(|category| {
            let held = held_by(&category.running_apps, running);
            CategoryReport {
                id: category.id.clone(),
                group: category.group,
                name: category.name.clone(),
                summary: category.summary.clone(),
                symbol: category.symbol.clone(),
                action: category.action,
                selected: category.selected && held.is_empty(),
                held_by: held,
                bytes: 0,
                files: 0,
                errors: 0,
                partial: false,
                items: Vec::new(),
            }
        })
        .collect();

    for (index, item, errors) in sized {
        let report = &mut reports[index];
        report.errors += errors;
        report.partial |= item.partial;
        if item.bytes == 0 && item.files == 0 {
            continue;
        }
        report.bytes += item.bytes;
        report.files += item.files;
        report.items.push(item);
    }
    for report in &mut reports {
        report.items.sort_by(|a, b| b.bytes.cmp(&a.bytes));
    }
    reports.retain(|r| !r.items.is_empty());
    reports
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    fn catalog() -> Catalog {
        Catalog::parse(
            r#"
            [[category]]
            id = "specific"
            group = "developer"
            name = "Specific"
            summary = ""
            symbol = "x"
            paths = ["~/Library/Caches/Specific/*"]
            running_apps = ["SpecificApp"]

            [[category]]
            id = "broad"
            group = "system"
            name = "Broad"
            summary = ""
            symbol = "x"
            paths = ["~/Library/Caches/*"]
            exclude = ["Keep*"]

            [[category]]
            id = "old"
            group = "apps"
            name = "Old"
            summary = ""
            symbol = "x"
            paths = ["~/Downloads/*.part"]
            min_age_days = 1
        "#,
        )
        .unwrap()
    }

    fn write(path: &Path, bytes: usize) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        let mut f = fs::File::create(path).unwrap();
        f.write_all(&vec![1u8; bytes]).unwrap();
    }

    fn run(home: &Path, running: HashSet<String>) -> ScanReport {
        let guard = Guard::new(home).unwrap();
        let options = ScanOptions {
            running,
            ..ScanOptions::default()
        };
        scan(&catalog(), &guard, &options, &|_| {})
    }

    #[test]
    fn specific_category_claims_before_broad() {
        let home = tempfile::tempdir().unwrap();
        let caches = home.path().join("Library/Caches");
        write(&caches.join("Specific/one/blob"), 8192);
        write(&caches.join("com.other/blob"), 8192);
        let report = run(home.path(), HashSet::new());
        let specific = report.categories.iter().find(|c| c.id == "specific").unwrap();
        let broad = report.categories.iter().find(|c| c.id == "broad").unwrap();
        assert_eq!(specific.items.len(), 1);
        assert!(broad.items.iter().all(|i| !i.path.contains("Specific")));
        assert_eq!(broad.items.len(), 1);
    }

    #[test]
    fn exclusions_and_age_are_respected() {
        let home = tempfile::tempdir().unwrap();
        write(&home.path().join("Library/Caches/KeepMe/blob"), 4096);
        write(&home.path().join("Downloads/fresh.part"), 4096);
        let report = run(home.path(), HashSet::new());
        let all_paths: Vec<_> = report
            .categories
            .iter()
            .flat_map(|c| c.items.iter().map(|i| i.path.clone()))
            .collect();
        assert!(all_paths.iter().all(|p| !p.contains("KeepMe")));
        assert!(all_paths.iter().all(|p| !p.contains("fresh.part")));
    }

    #[test]
    fn running_app_holds_and_deselects_category() {
        let home = tempfile::tempdir().unwrap();
        write(&home.path().join("Library/Caches/Specific/one/blob"), 4096);
        let running: HashSet<String> = ["specificapp".to_string()].into();
        let report = run(home.path(), running);
        let specific = report.categories.iter().find(|c| c.id == "specific").unwrap();
        assert!(!specific.selected);
        assert_eq!(specific.held_by, vec!["SpecificApp".to_string()]);
    }

    #[test]
    fn items_carry_identity_and_are_sorted() {
        let home = tempfile::tempdir().unwrap();
        write(&home.path().join("Library/Caches/small/blob"), 4096);
        write(&home.path().join("Library/Caches/large/blob"), 256 * 1024);
        let report = run(home.path(), HashSet::new());
        let broad = report.categories.iter().find(|c| c.id == "broad").unwrap();
        assert!(broad.items[0].path.ends_with("large"));
        assert!(broad.items.iter().all(|i| i.ino != 0));
        assert_eq!(report.total_bytes, broad.bytes);
    }
}
