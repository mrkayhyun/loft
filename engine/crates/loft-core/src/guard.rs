//! Path guard: the last line of defence before anything is removed.
//!
//! Every candidate path is checked here twice — once when a plan is built and
//! again immediately before the sink. The guard is deliberately conservative:
//! it only accepts paths strictly inside the user's home, rejects well-known
//! roots and personal-data folders, refuses to walk through symlinked parents,
//! and blocks anything that belongs to data-sensitive apps.

use std::path::{Component, Path, PathBuf};

use globset::{Glob, GlobSet, GlobSetBuilder};
use thiserror::Error;

/// Folders that may never be removed themselves (their children may be).
const PROTECTED_ROOTS: &[&str] = &[
    "Library",
    "Library/Caches",
    "Library/Logs",
    "Library/Application Support",
    "Library/Containers",
    "Library/Group Containers",
    "Library/Preferences",
    "Library/Developer",
    "Library/Developer/Xcode",
    "Library/Developer/CoreSimulator",
    "Applications",
    "Desktop",
    "Documents",
    "Downloads",
    "Movies",
    "Music",
    "Pictures",
    "Public",
    ".Trash",
    ".cache",
    ".config",
    ".local",
];

/// Subtrees that are never touched, including everything below them.
const FORBIDDEN_TREES: &[&str] = &[
    "Library/Keychains",
    "Library/Mobile Documents",
    "Library/CloudStorage",
    "Library/Mail",
    "Library/Messages",
    "Library/Photos",
    "Library/Safari",
    "Library/Accounts",
    "Library/Cookies",
    "Library/Developer/CoreSimulator/Devices",
    "Library/Containers/com.apple.mail/Data/Library/Mail",
    ".ssh",
    ".gnupg",
    ".aws",
    ".kube",
    ".docker",
    ".config/gcloud",
];

/// Bundle identifiers of apps whose data must never be swept, matched against
/// every path component (password managers, input methods, security agents).
const DATA_PROTECTED_BUNDLES: &[&str] = &[
    "com.1password.*",
    "com.agilebits.*",
    "com.bitwarden.*",
    "com.lastpass.*",
    "com.dashlane.*",
    "org.keepassxc.*",
    "com.apple.keychainaccess*",
    "com.apple.Passwords*",
    "*.inputmethod*",
    "*.InputMethod*",
    "im.rime.*",
    "com.googlecode.rimeime.*",
    "com.crowdstrike.*",
    "com.sentinelone.*",
    "com.jamfsoftware.*",
    "com.paloaltonetworks.*",
    "com.cisco.anyconnect*",
    "com.cisco.secureclient*",
];

#[derive(Debug, Error, PartialEq, Eq)]
pub enum GuardError {
    #[error("path is not absolute")]
    NotAbsolute,
    #[error("path contains relative components")]
    RelativeComponent,
    #[error("path is outside the home folder")]
    OutsideHome,
    #[error("path is a protected folder")]
    ProtectedRoot,
    #[error("path is inside a protected area")]
    ForbiddenTree,
    #[error("path belongs to a data-protected app")]
    ProtectedApp,
    #[error("a parent folder is a symbolic link")]
    SymlinkedParent,
}

#[derive(Debug, Clone)]
pub struct Guard {
    home: PathBuf,
    protected_apps: GlobSet,
}

impl Guard {
    /// Build a guard rooted at `home`. The home path is canonicalised so that
    /// firmlinks such as `/var` → `/private/var` compare correctly.
    pub fn new(home: &Path) -> std::io::Result<Self> {
        let home = home.canonicalize()?;
        let mut builder = GlobSetBuilder::new();
        for pattern in DATA_PROTECTED_BUNDLES {
            builder.add(Glob::new(pattern).expect("static glob is valid"));
        }
        let protected_apps = builder.build().expect("static globset is valid");
        Ok(Self {
            home,
            protected_apps,
        })
    }

    pub fn home(&self) -> &Path {
        &self.home
    }

    /// Accept `path` only if it is safe to remove.
    pub fn check(&self, path: &Path) -> Result<(), GuardError> {
        if !path.is_absolute() {
            return Err(GuardError::NotAbsolute);
        }
        if path
            .components()
            .any(|c| matches!(c, Component::ParentDir | Component::CurDir))
        {
            return Err(GuardError::RelativeComponent);
        }
        let relative = path
            .strip_prefix(&self.home)
            .map_err(|_| GuardError::OutsideHome)?;
        if relative.as_os_str().is_empty() {
            return Err(GuardError::ProtectedRoot);
        }
        if PROTECTED_ROOTS.iter().any(|root| relative == Path::new(root)) {
            return Err(GuardError::ProtectedRoot);
        }
        if FORBIDDEN_TREES
            .iter()
            .any(|tree| relative.starts_with(Path::new(tree)))
        {
            return Err(GuardError::ForbiddenTree);
        }
        if relative
            .components()
            .any(|c| self.protected_apps.is_match(c.as_os_str()))
        {
            return Err(GuardError::ProtectedApp);
        }
        self.check_parents_are_real(path)
    }

    /// Walking through a symlinked parent could redirect a removal outside the
    /// intended tree, so every parent below home must be a real directory.
    fn check_parents_are_real(&self, path: &Path) -> Result<(), GuardError> {
        let mut current = path.parent();
        while let Some(dir) = current {
            if dir == self.home {
                return Ok(());
            }
            match std::fs::symlink_metadata(dir) {
                Ok(meta) if meta.file_type().is_symlink() => {
                    return Err(GuardError::SymlinkedParent)
                }
                _ => {}
            }
            current = dir.parent();
        }
        Err(GuardError::OutsideHome)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn setup() -> (tempfile::TempDir, Guard) {
        let dir = tempfile::tempdir().unwrap();
        let guard = Guard::new(dir.path()).unwrap();
        (dir, guard)
    }

    #[test]
    fn accepts_child_of_caches() {
        let (_dir, guard) = setup();
        let target = guard.home().join("Library/Caches/com.example.app");
        fs::create_dir_all(&target).unwrap();
        assert_eq!(guard.check(&target), Ok(()));
    }

    #[test]
    fn rejects_home_and_protected_roots() {
        let (_dir, guard) = setup();
        assert_eq!(guard.check(guard.home()), Err(GuardError::ProtectedRoot));
        let caches = guard.home().join("Library/Caches");
        assert_eq!(guard.check(&caches), Err(GuardError::ProtectedRoot));
        let docs = guard.home().join("Documents");
        assert_eq!(guard.check(&docs), Err(GuardError::ProtectedRoot));
    }

    #[test]
    fn rejects_paths_outside_home() {
        let (_dir, guard) = setup();
        assert_eq!(
            guard.check(Path::new("/System/Library/Caches/x")),
            Err(GuardError::OutsideHome)
        );
    }

    #[test]
    fn rejects_relative_and_dotdot_paths() {
        let (_dir, guard) = setup();
        assert_eq!(
            guard.check(Path::new("Library/Caches/x")),
            Err(GuardError::NotAbsolute)
        );
        let sneaky = guard.home().join("Library/Caches/../../Documents");
        assert_eq!(guard.check(&sneaky), Err(GuardError::RelativeComponent));
    }

    #[test]
    fn rejects_forbidden_trees() {
        let (_dir, guard) = setup();
        let keychain = guard.home().join("Library/Keychains/login.keychain-db");
        assert_eq!(guard.check(&keychain), Err(GuardError::ForbiddenTree));
        let icloud = guard.home().join("Library/Mobile Documents/com~apple~CloudDocs/a");
        assert_eq!(guard.check(&icloud), Err(GuardError::ForbiddenTree));
        let device = guard
            .home()
            .join("Library/Developer/CoreSimulator/Devices/ABC");
        assert_eq!(guard.check(&device), Err(GuardError::ForbiddenTree));
    }

    #[test]
    fn rejects_data_protected_apps() {
        let (_dir, guard) = setup();
        let vault = guard.home().join("Library/Caches/com.1password.1password");
        assert_eq!(guard.check(&vault), Err(GuardError::ProtectedApp));
        let ime = guard.home().join("Library/Caches/com.sogou.inputmethod.pinyin");
        assert_eq!(guard.check(&ime), Err(GuardError::ProtectedApp));
    }

    #[test]
    fn rejects_symlinked_parent() {
        let (_dir, guard) = setup();
        let outside = tempfile::tempdir().unwrap();
        let caches = guard.home().join("Library/Caches");
        fs::create_dir_all(&caches).unwrap();
        std::os::unix::fs::symlink(outside.path(), caches.join("evil")).unwrap();
        let target = caches.join("evil/important");
        assert_eq!(guard.check(&target), Err(GuardError::SymlinkedParent));
    }
}
