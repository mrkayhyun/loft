//! Applications: discovery, leftover detection by exact evidence, uninstall.
//!
//! Leftovers are matched only by the app's exact bundle identifier, plus an
//! opt-in set of exact app-name folders (never selected by default and never
//! for generic names). Vendor-wide, prefix or fuzzy matching is not used.

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

use globset::{Glob, GlobSet, GlobSetBuilder};
use rayon::prelude::*;
use serde::{Deserialize, Serialize};

use crate::exec::{ItemResult, Outcome};
use crate::sink::Sink;
use crate::{Guard, Sizer};

const SYSTEM_APP_ROOT: &str = "/Applications";
const MIN_NAME_EVIDENCE_LEN: usize = 4;

/// Apple apps that users install themselves and may remove.
const APPLE_REMOVABLE: &[&str] = &[
    "com.apple.dt.*",
    "com.apple.FinalCut*",
    "com.apple.Motion",
    "com.apple.Compressor",
    "com.apple.logic*",
    "com.apple.garageband*",
    "com.apple.iMovie*",
    "com.apple.iWork.*",
    "com.apple.MainStage*",
    "com.apple.Playgrounds",
];

/// Security / device-management agents must use their vendor uninstaller.
const VENDOR_MANAGED: &[&str] = &[
    "com.crowdstrike.*",
    "com.sentinelone.*",
    "com.jamfsoftware.*",
    "com.jamf.*",
    "com.paloaltonetworks.*",
    "com.cisco.anyconnect*",
    "com.cisco.secureclient*",
    "com.microsoft.wdav*",
    "com.kandji.*",
    "com.sophos.*",
];

/// Folder names too generic to count as evidence of a specific app.
const COMMON_NAMES: &[&str] = &[
    "music", "notes", "photos", "finder", "safari", "preview", "calendar", "contacts",
    "messages", "reminders", "clock", "weather", "stocks", "books", "news", "files",
    "store", "system", "helper", "agent", "daemon", "service", "update", "sync",
    "backup", "cloud", "manager", "monitor", "server", "client", "worker", "runner",
    "launcher", "driver", "plugin", "extension", "widget", "utility", "google",
    "microsoft", "apple", "adobe", "code", "data", "cache", "caches", "logs",
];

/// `(kind, home-relative pattern)`; `{id}` is the escaped bundle identifier.
const BUNDLE_LEFTOVERS: &[(&str, &str)] = &[
    ("Application Support", "Library/Application Support/{id}"),
    ("Caches", "Library/Caches/{id}"),
    ("Caches", "Library/Caches/{id}.ShipIt"),
    ("Preferences", "Library/Preferences/{id}.plist"),
    ("Preferences", "Library/Preferences/ByHost/{id}.*.plist"),
    ("Container", "Library/Containers/{id}"),
    ("Saved State", "Library/Saved Application State/{id}.savedState"),
    ("Web Data", "Library/HTTPStorages/{id}"),
    ("Web Data", "Library/HTTPStorages/{id}.binarycookies"),
    ("Web Data", "Library/WebKit/{id}"),
    ("Logs", "Library/Logs/{id}"),
    ("App Scripts", "Library/Application Scripts/{id}"),
    ("Launch Agent", "Library/LaunchAgents/{id}.plist"),
];

const NAME_LEFTOVERS: &[(&str, &str)] = &[
    ("Application Support", "Library/Application Support/{name}"),
    ("Caches", "Library/Caches/{name}"),
    ("Logs", "Library/Logs/{name}"),
];

#[derive(Debug, Clone, Serialize)]
pub struct AppInfo {
    pub path: String,
    pub name: String,
    pub bundle_id: String,
    pub version: String,
    pub executable: String,
    pub running: bool,
    /// Why this app cannot be removed by Burrow, if it cannot.
    pub protected: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Evidence {
    BundleId,
    Name,
}

#[derive(Debug, Clone, Serialize)]
pub struct Leftover {
    pub path: String,
    pub kind: String,
    pub evidence: Evidence,
    pub bytes: u64,
    pub files: u64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct UninstallRequest {
    pub app: String,
    #[serde(default)]
    pub include: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct UninstallReport {
    pub dry_run: bool,
    pub freed_bytes: u64,
    pub results: Vec<ItemResult>,
}

struct Bundle {
    bundle_id: String,
    name: String,
    version: String,
    executable: String,
}

fn globset(patterns: &[&str]) -> GlobSet {
    let mut builder = GlobSetBuilder::new();
    for pattern in patterns {
        builder.add(Glob::new(pattern).expect("static glob is valid"));
    }
    builder.build().expect("static globset is valid")
}

/// Reason an app must not be uninstalled here, if any.
pub fn protection_reason(bundle_id: &str) -> Option<String> {
    if bundle_id.is_empty() {
        return Some("Missing bundle identifier".into());
    }
    if bundle_id.starts_with("dev.burrow.") {
        return Some("Burrow cannot remove itself".into());
    }
    if globset(VENDOR_MANAGED).is_match(bundle_id) {
        return Some("Managed by your organisation — use the vendor's uninstaller".into());
    }
    if bundle_id.starts_with("com.apple.") && !globset(APPLE_REMOVABLE).is_match(bundle_id) {
        return Some("Part of macOS".into());
    }
    None
}

fn read_bundle(app: &Path) -> Option<Bundle> {
    let info: plist::Dictionary = plist::from_file(app.join("Contents/Info.plist")).ok()?;
    let text = |key: &str| {
        info.get(key)
            .and_then(|v| v.as_string())
            .map(str::to_string)
            .unwrap_or_default()
    };
    let file_stem = app.file_stem()?.to_string_lossy().into_owned();
    let display = text("CFBundleDisplayName");
    let name = if display.is_empty() { file_stem } else { display };
    Some(Bundle {
        bundle_id: text("CFBundleIdentifier"),
        name,
        version: text("CFBundleShortVersionString"),
        executable: text("CFBundleExecutable"),
    })
}

fn app_roots(home: &Path) -> Vec<PathBuf> {
    vec![PathBuf::from(SYSTEM_APP_ROOT), home.join("Applications")]
}

fn is_app_bundle(path: &Path) -> bool {
    path.extension().is_some_and(|e| e.eq_ignore_ascii_case("app"))
}

/// `.app` bundles directly inside each root, or one folder deeper
/// (e.g. `/Applications/Adobe Photoshop 2025/Adobe Photoshop 2025.app`).
fn discover_bundles(roots: &[PathBuf]) -> Vec<PathBuf> {
    let mut bundles = Vec::new();
    for root in roots {
        let Ok(entries) = fs::read_dir(root) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let Ok(meta) = fs::symlink_metadata(&path) else {
                continue;
            };
            if !meta.is_dir() {
                continue;
            }
            if is_app_bundle(&path) {
                bundles.push(path);
                continue;
            }
            if let Ok(nested) = fs::read_dir(&path) {
                bundles.extend(
                    nested
                        .flatten()
                        .map(|e| e.path())
                        .filter(|p| is_app_bundle(p) && !p.is_symlink()),
                );
            }
        }
    }
    bundles
}

pub fn list_apps(home: &Path, running: &HashSet<String>) -> Vec<AppInfo> {
    let mut apps: Vec<AppInfo> = discover_bundles(&app_roots(home))
        .into_par_iter()
        .filter_map(|path| {
            let bundle = read_bundle(&path)?;
            let is_running = !bundle.executable.is_empty()
                && running.contains(&bundle.executable.to_lowercase());
            Some(AppInfo {
                path: path.to_string_lossy().into_owned(),
                protected: protection_reason(&bundle.bundle_id),
                name: bundle.name,
                bundle_id: bundle.bundle_id,
                version: bundle.version,
                executable: bundle.executable,
                running: is_running,
            })
        })
        .collect();
    apps.sort_by_key(|a| a.name.to_lowercase());
    apps
}

fn name_is_evidence(name: &str) -> bool {
    name.chars().count() >= MIN_NAME_EVIDENCE_LEN
        && !name.contains('/')
        && !COMMON_NAMES.contains(&name.to_lowercase().as_str())
}

fn expand_leftover_patterns(guard: &Guard, bundle_id: &str, app_name: &str) -> Vec<(String, Evidence, PathBuf)> {
    let home = glob::Pattern::escape(&guard.home().to_string_lossy());
    let id = glob::Pattern::escape(bundle_id);
    let name = glob::Pattern::escape(app_name);
    let mut specs: Vec<(&str, Evidence, String)> = BUNDLE_LEFTOVERS
        .iter()
        .map(|(kind, p)| (*kind, Evidence::BundleId, p.replace("{id}", &id)))
        .collect();
    if name_is_evidence(app_name) {
        specs.extend(
            NAME_LEFTOVERS
                .iter()
                .map(|(kind, p)| (*kind, Evidence::Name, p.replace("{name}", &name))),
        );
    }
    let mut seen = HashSet::new();
    let mut found = Vec::new();
    for (kind, evidence, relative) in specs {
        let Ok(paths) = glob::glob(&format!("{home}/{relative}")) else {
            continue;
        };
        for path in paths.flatten() {
            if seen.insert(path.clone()) && guard.check(&path).is_ok() {
                found.push((kind.to_string(), evidence, path));
            }
        }
    }
    found
}

pub fn find_leftovers(guard: &Guard, bundle_id: &str, app_name: &str) -> Vec<Leftover> {
    if bundle_id.is_empty() {
        return Vec::new();
    }
    let sizer = Sizer::default();
    let mut leftovers: Vec<Leftover> = expand_leftover_patterns(guard, bundle_id, app_name)
        .into_par_iter()
        .map(|(kind, evidence, path)| {
            let size = sizer.measure(&path);
            Leftover {
                path: path.to_string_lossy().into_owned(),
                kind,
                evidence,
                bytes: size.bytes,
                files: size.files,
            }
        })
        .collect();
    leftovers.sort_by(|a, b| b.bytes.cmp(&a.bytes));
    leftovers
}

/// Confirm `path` is a real `.app` bundle inside an application root.
fn validate_app_path(home: &Path, path: &Path) -> Result<(), String> {
    if !is_app_bundle(path) {
        return Err("not an application bundle".into());
    }
    let meta = fs::symlink_metadata(path).map_err(|_| "application not found".to_string())?;
    if meta.file_type().is_symlink() || !meta.is_dir() {
        return Err("application is not a real bundle".into());
    }
    let parent = path.parent().ok_or("no parent folder")?;
    let inside_root = app_roots(home).iter().any(|root| {
        parent == root || parent.parent() == Some(root.as_path())
    });
    if !inside_root {
        return Err("application is outside /Applications".into());
    }
    Ok(())
}

pub fn uninstall(
    guard: &Guard,
    sink: &dyn Sink,
    running: &HashSet<String>,
    request: &UninstallRequest,
    dry_run: bool,
) -> Result<UninstallReport, String> {
    let app = PathBuf::from(&request.app);
    validate_app_path(guard.home(), &app)?;
    let bundle = read_bundle(&app).ok_or("cannot read Info.plist")?;
    if let Some(reason) = protection_reason(&bundle.bundle_id) {
        return Err(reason);
    }
    if !bundle.executable.is_empty() && running.contains(&bundle.executable.to_lowercase()) {
        return Err(format!("Quit {} before uninstalling", bundle.name));
    }

    let allowed: HashSet<String> = expand_leftover_patterns(guard, &bundle.bundle_id, &bundle.name)
        .into_iter()
        .map(|(_, _, p)| p.to_string_lossy().into_owned())
        .collect();

    let sizer = Sizer::default();
    let mut results = vec![remove(sink, &sizer, &app, "app", dry_run)];
    for path in &request.include {
        let result = if allowed.contains(path) {
            remove(sink, &sizer, Path::new(path), "leftover", dry_run)
        } else {
            ItemResult {
                category: "leftover".into(),
                path: path.clone(),
                outcome: Outcome::Skipped {
                    reason: "not a leftover of this app".into(),
                },
            }
        };
        results.push(result);
    }
    let freed_bytes = results
        .iter()
        .map(|r| match r.outcome {
            Outcome::Removed { bytes } | Outcome::WouldRemove { bytes } => bytes,
            _ => 0,
        })
        .sum();
    Ok(UninstallReport {
        dry_run,
        freed_bytes,
        results,
    })
}

fn remove(sink: &dyn Sink, sizer: &Sizer, path: &Path, category: &str, dry_run: bool) -> ItemResult {
    let bytes = sizer.measure(path).bytes;
    let outcome = if dry_run {
        Outcome::WouldRemove { bytes }
    } else {
        match sink.trash(path) {
            Ok(()) => Outcome::Removed { bytes },
            Err(error) => Outcome::Failed {
                error: error.to_string(),
            },
        }
    };
    ItemResult {
        category: category.into(),
        path: path.to_string_lossy().into_owned(),
        outcome,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write_app(root: &Path, name: &str, bundle_id: &str) -> PathBuf {
        let app = root.join(format!("{name}.app"));
        fs::create_dir_all(app.join("Contents/MacOS")).unwrap();
        let mut info = plist::Dictionary::new();
        info.insert("CFBundleIdentifier".into(), bundle_id.into());
        info.insert("CFBundleShortVersionString".into(), "1.2.3".into());
        info.insert("CFBundleExecutable".into(), name.into());
        plist::to_file_xml(app.join("Contents/Info.plist"), &info).unwrap();
        app
    }

    #[test]
    fn protects_system_and_vendor_apps() {
        assert!(protection_reason("com.apple.Safari").is_some());
        assert!(protection_reason("com.apple.dt.Xcode").is_none());
        assert!(protection_reason("com.crowdstrike.falcon.App").is_some());
        assert!(protection_reason("com.tinyspeck.slackmacgap").is_none());
    }

    #[test]
    fn lists_apps_in_user_applications() {
        let home = tempfile::tempdir().unwrap();
        write_app(&home.path().join("Applications"), "Demo", "com.example.demo");
        let running: HashSet<String> = ["demo".to_string()].into();
        let apps = list_apps(home.path(), &running);
        let demo = apps.iter().find(|a| a.bundle_id == "com.example.demo").unwrap();
        assert_eq!(demo.version, "1.2.3");
        assert!(demo.running);
    }

    #[test]
    fn leftovers_use_exact_bundle_id_only() {
        let home = tempfile::tempdir().unwrap();
        let guard = Guard::new(home.path()).unwrap();
        let lib = guard.home().join("Library");
        fs::create_dir_all(lib.join("Caches/com.example.demo")).unwrap();
        fs::write(lib.join("Caches/com.example.demo/blob"), b"x").unwrap();
        fs::create_dir_all(lib.join("Caches/com.example.demoextra")).unwrap();
        fs::create_dir_all(lib.join("Preferences")).unwrap();
        fs::write(lib.join("Preferences/com.example.demo.plist"), b"x").unwrap();
        let found = find_leftovers(&guard, "com.example.demo", "Demo");
        let paths: Vec<_> = found.iter().map(|l| l.path.clone()).collect();
        assert_eq!(found.len(), 2, "{paths:?}");
        assert!(paths.iter().all(|p| !p.ends_with("demoextra")));
    }

    #[test]
    fn generic_names_are_not_evidence() {
        assert!(!name_is_evidence("Notes"));
        assert!(!name_is_evidence("App"));
        assert!(name_is_evidence("Slack"));
    }

    #[test]
    fn uninstall_rejects_foreign_leftover_paths() {
        struct NoopSink;
        impl Sink for NoopSink {
            fn trash(&self, _: &Path) -> anyhow::Result<()> {
                Ok(())
            }
            fn delete(&self, _: &Path) -> anyhow::Result<()> {
                Ok(())
            }
        }
        let home = tempfile::tempdir().unwrap();
        let guard = Guard::new(home.path()).unwrap();
        let app = write_app(&guard.home().join("Applications"), "Demo", "com.example.demo");
        let docs = guard.home().join("Documents/thesis");
        fs::create_dir_all(&docs).unwrap();
        let request = UninstallRequest {
            app: app.to_string_lossy().into_owned(),
            include: vec![docs.to_string_lossy().into_owned()],
        };
        let report = uninstall(&guard, &NoopSink, &HashSet::new(), &request, true).unwrap();
        assert!(matches!(report.results[0].outcome, Outcome::WouldRemove { .. }));
        assert!(matches!(report.results[1].outcome, Outcome::Skipped { .. }));
    }

    #[test]
    fn uninstall_refuses_running_app() {
        let home = tempfile::tempdir().unwrap();
        let guard = Guard::new(home.path()).unwrap();
        let app = write_app(&guard.home().join("Applications"), "Demo", "com.example.demo");
        let request = UninstallRequest {
            app: app.to_string_lossy().into_owned(),
            include: vec![],
        };
        let running: HashSet<String> = ["demo".to_string()].into();
        assert!(uninstall(&guard, &crate::sink::SystemSink, &running, &request, true).is_err());
    }
}
