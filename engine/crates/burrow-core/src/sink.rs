//! Final sinks: where a validated item actually leaves its location.

use std::fs;
use std::path::Path;

pub trait Sink: Sync {
    /// Move `path` to the user's Trash (recoverable).
    fn trash(&self, path: &Path) -> anyhow::Result<()>;
    /// Remove `path` permanently.
    fn delete(&self, path: &Path) -> anyhow::Result<()>;
}

/// Production sink: Trash through `NSFileManager`, permanent delete via std.
pub struct SystemSink;

impl Sink for SystemSink {
    fn trash(&self, path: &Path) -> anyhow::Result<()> {
        let mut context = trash::TrashContext::default();
        #[cfg(target_os = "macos")]
        {
            use trash::macos::{DeleteMethod, TrashContextExtMacos};
            // NSFileManager avoids Finder Apple Events (no automation prompt,
            // no sound) and is much faster for batches.
            context.set_delete_method(DeleteMethod::NsFileManager);
        }
        context.delete(path)?;
        Ok(())
    }

    fn delete(&self, path: &Path) -> anyhow::Result<()> {
        let meta = fs::symlink_metadata(path)?;
        if meta.is_dir() {
            fs::remove_dir_all(path)?;
        } else {
            fs::remove_file(path)?;
        }
        Ok(())
    }
}
