//! In-process, parallel physical-size measurement.
//!
//! Replaces the shell's per-path `du`/`stat`/`mdls` forks. Sizes use
//! `st_blocks * 512` (on-disk occupancy, like `du -k`), hard links are counted
//! once per measurement session, and symlinks are never followed.

use std::collections::HashSet;
use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::Instant;

use serde::Serialize;

const BLOCK_SIZE: u64 = 512;

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct Size {
    pub bytes: u64,
    pub files: u64,
    /// Entries that could not be read (permissions, races).
    pub errors: u64,
    /// True when the walk stopped early because the budget ran out.
    pub partial: bool,
}

impl Size {
    fn merge(self, other: Size) -> Size {
        Size {
            bytes: self.bytes + other.bytes,
            files: self.files + other.files,
            errors: self.errors + other.errors,
            partial: self.partial || other.partial,
        }
    }

    fn error() -> Size {
        Size {
            errors: 1,
            ..Size::default()
        }
    }
}

/// Shared state for one measurement session: hard-link de-duplication and an
/// optional deadline / cancellation flag checked inside the walk.
pub struct Sizer {
    seen_inodes: Mutex<HashSet<(u64, u64)>>,
    deadline: Option<Instant>,
    cancelled: AtomicBool,
    device: Option<u64>,
}

impl Default for Sizer {
    fn default() -> Self {
        Self::new(None)
    }
}

impl Sizer {
    pub fn new(deadline: Option<Instant>) -> Self {
        Self {
            seen_inodes: Mutex::new(HashSet::new()),
            deadline,
            cancelled: AtomicBool::new(false),
            device: None,
        }
    }

    /// Do not descend into directories on a different device than `device`.
    pub fn one_file_system(self, device: u64) -> Self {
        Self {
            device: Some(device),
            ..self
        }
    }

    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Relaxed);
    }

    fn out_of_budget(&self) -> bool {
        if self.cancelled.load(Ordering::Relaxed) {
            return true;
        }
        match self.deadline {
            Some(deadline) if Instant::now() >= deadline => {
                self.cancelled.store(true, Ordering::Relaxed);
                true
            }
            _ => false,
        }
    }

    /// Physical size of `path` (file, symlink or directory tree).
    pub fn measure(&self, path: &Path) -> Size {
        match fs::symlink_metadata(path) {
            Ok(meta) => self.measure_entry(path, &meta),
            Err(_) => Size::error(),
        }
    }

    fn measure_entry(&self, path: &Path, meta: &fs::Metadata) -> Size {
        if self.out_of_budget() {
            return Size {
                partial: true,
                ..Size::default()
            };
        }
        let own = self.own_size(meta);
        if !meta.is_dir() || self.device.is_some_and(|dev| dev != meta.dev()) {
            return own;
        }
        let entries = match fs::read_dir(path) {
            Ok(entries) => entries,
            Err(_) => return own.merge(Size::error()),
        };
        // Walk children sequentially. Directory sizing is invoked from
        // `scan`/`analyze` inside an outer `par_iter` over candidates, so the
        // parallelism budget is already spent there; recursing with a nested
        // `par_iter` here floods the global rayon pool on wide, deep trees
        // (e.g. `~/.gradle/caches`) and stalls progress. The deadline is
        // checked every entry so an over-budget walk stops promptly and is
        // reported as `partial` rather than hanging.
        let mut total = own;
        for entry in entries {
            if self.out_of_budget() {
                total.partial = true;
                break;
            }
            let child_size = match entry {
                Ok(entry) => {
                    let child = entry.path();
                    match fs::symlink_metadata(&child) {
                        Ok(meta) => self.measure_entry(&child, &meta),
                        Err(_) => Size::error(),
                    }
                }
                Err(_) => Size::error(),
            };
            total = total.merge(child_size);
        }
        total
    }

    fn own_size(&self, meta: &fs::Metadata) -> Size {
        let files = u64::from(!meta.is_dir());
        if meta.is_file() && meta.nlink() > 1 {
            let key = (meta.dev(), meta.ino());
            let first_sighting = self
                .seen_inodes
                .lock()
                .map(|mut seen| seen.insert(key))
                .unwrap_or(true);
            if !first_sighting {
                return Size {
                    files,
                    ..Size::default()
                };
            }
        }
        Size {
            bytes: meta.blocks() * BLOCK_SIZE,
            files,
            ..Size::default()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    fn write_file(path: &Path, bytes: usize) {
        let mut f = fs::File::create(path).unwrap();
        f.write_all(&vec![7u8; bytes]).unwrap();
        f.sync_all().unwrap();
    }

    #[test]
    fn measures_nested_tree() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("a/b")).unwrap();
        write_file(&dir.path().join("a/one"), 64 * 1024);
        write_file(&dir.path().join("a/b/two"), 64 * 1024);
        let size = Sizer::default().measure(dir.path());
        assert_eq!(size.files, 2);
        assert!(size.bytes >= 128 * 1024, "got {}", size.bytes);
        assert!(!size.partial);
    }

    #[test]
    fn counts_hard_links_once() {
        let dir = tempfile::tempdir().unwrap();
        let original = dir.path().join("original");
        write_file(&original, 256 * 1024);
        fs::hard_link(&original, dir.path().join("link")).unwrap();
        let single = Sizer::default().measure(&original).bytes;
        let both = Sizer::default().measure(dir.path());
        assert_eq!(both.files, 2);
        assert!(both.bytes < single * 2, "hard link was double counted");
    }

    #[test]
    fn does_not_follow_symlinks() {
        let dir = tempfile::tempdir().unwrap();
        let outside = tempfile::tempdir().unwrap();
        write_file(&outside.path().join("big"), 512 * 1024);
        std::os::unix::fs::symlink(outside.path(), dir.path().join("link")).unwrap();
        let size = Sizer::default().measure(dir.path());
        assert!(size.bytes < 512 * 1024);
    }

    #[test]
    fn missing_path_reports_error() {
        let size = Sizer::default().measure(Path::new("/definitely/not/here"));
        assert_eq!(size.errors, 1);
        assert_eq!(size.bytes, 0);
    }

    #[test]
    fn expired_deadline_marks_partial() {
        let dir = tempfile::tempdir().unwrap();
        write_file(&dir.path().join("f"), 1024);
        let sizer = Sizer::new(Some(Instant::now()));
        assert!(sizer.measure(dir.path()).partial);
    }

    #[test]
    fn deadline_stops_walk_over_many_children() {
        // A directory with several children; an already-expired deadline must
        // short-circuit the sequential walk and report a partial result
        // instead of sizing every entry.
        let dir = tempfile::tempdir().unwrap();
        for i in 0..16 {
            write_file(&dir.path().join(format!("f{i}")), 1024);
        }
        let sizer = Sizer::new(Some(Instant::now()));
        let size = sizer.measure(dir.path());
        assert!(size.partial, "expired deadline should mark the walk partial");
        assert!(
            size.files < 16,
            "walk should stop early, got {} files",
            size.files
        );
    }

    #[test]
    fn measures_deep_tree_without_deadline() {
        // Sequential recursion must still descend a deep, narrow tree fully.
        let dir = tempfile::tempdir().unwrap();
        let mut p = dir.path().to_path_buf();
        for level in 0..8 {
            p = p.join(format!("level{level}"));
            fs::create_dir_all(&p).unwrap();
            write_file(&p.join("leaf"), 4096);
        }
        let size = Sizer::default().measure(dir.path());
        assert_eq!(size.files, 8);
        assert!(!size.partial);
    }
}
