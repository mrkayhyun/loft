//! Disk explorer: size every child of a folder in parallel.
//!
//! Children are streamed as they finish so a UI can fill in progressively.
//! Walks stay on the starting volume, so firmlinked system volumes are not
//! counted twice.

use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::Path;
use std::time::Instant;

use rayon::prelude::*;
use serde::Serialize;

use crate::Sizer;

#[derive(Debug, Clone, Serialize)]
pub struct Node {
    pub name: String,
    pub path: String,
    pub bytes: u64,
    pub files: u64,
    pub is_dir: bool,
    pub partial: bool,
    pub errors: u64,
}

#[derive(Debug, Clone, Serialize)]
pub struct DirReport {
    pub path: String,
    pub bytes: u64,
    pub files: u64,
    pub errors: u64,
    pub duration_ms: u64,
    pub children: Vec<Node>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum AnalyzeEvent {
    Started { path: String, children: usize },
    Child { node: Node },
}

pub fn analyze(
    root: &Path,
    deadline: Option<Instant>,
    on_event: &(dyn Fn(AnalyzeEvent) + Sync),
) -> anyhow::Result<DirReport> {
    let started = Instant::now();
    let root_meta = fs::symlink_metadata(root)?;
    anyhow::ensure!(root_meta.is_dir(), "{} is not a folder", root.display());
    let entries: Vec<_> = fs::read_dir(root)?.flatten().map(|e| e.path()).collect();
    on_event(AnalyzeEvent::Started {
        path: root.to_string_lossy().into_owned(),
        children: entries.len(),
    });

    let sizer = Sizer::new(deadline).one_file_system(root_meta.dev());
    let mut children: Vec<Node> = entries
        .par_iter()
        .map(|path| {
            let is_dir = fs::symlink_metadata(path).is_ok_and(|m| m.is_dir());
            let size = sizer.measure(path);
            let node = Node {
                name: path
                    .file_name()
                    .map(|n| n.to_string_lossy().into_owned())
                    .unwrap_or_default(),
                path: path.to_string_lossy().into_owned(),
                bytes: size.bytes,
                files: size.files,
                is_dir,
                partial: size.partial,
                errors: size.errors,
            };
            on_event(AnalyzeEvent::Child { node: node.clone() });
            node
        })
        .collect();
    children.sort_by(|a, b| b.bytes.cmp(&a.bytes));

    Ok(DirReport {
        path: root.to_string_lossy().into_owned(),
        bytes: children.iter().map(|c| c.bytes).sum(),
        files: children.iter().map(|c| c.files).sum(),
        errors: children.iter().map(|c| c.errors).sum(),
        duration_ms: started.elapsed().as_millis() as u64,
        children,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    #[test]
    fn sizes_and_sorts_children_and_streams_events() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir_all(dir.path().join("big")).unwrap();
        fs::write(dir.path().join("big/blob"), vec![0u8; 256 * 1024]).unwrap();
        fs::write(dir.path().join("small"), vec![0u8; 1024]).unwrap();
        let events = Mutex::new(0usize);
        let report = analyze(dir.path(), None, &|_| *events.lock().unwrap() += 1).unwrap();
        assert_eq!(report.children.len(), 2);
        assert_eq!(report.children[0].name, "big");
        assert!(report.children[0].is_dir);
        assert_eq!(*events.lock().unwrap(), 3);
    }

    #[test]
    fn rejects_files() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("f");
        fs::write(&file, b"x").unwrap();
        assert!(analyze(&file, None, &|_| {}).is_err());
    }
}
