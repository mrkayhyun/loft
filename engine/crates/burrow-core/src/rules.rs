//! Cleanup catalog: declarative categories loaded from `rules/clean.toml`.

use std::path::{Path, PathBuf};

use globset::{Glob, GlobSet, GlobSetBuilder};
use serde::{Deserialize, Serialize};

const BUILTIN_CATALOG: &str = include_str!("../../../rules/clean.toml");

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Group {
    System,
    Browser,
    Developer,
    Apps,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Action {
    /// Move to the user's Trash (recoverable).
    #[default]
    Trash,
    /// Remove permanently. Only valid for items already inside `~/.Trash`.
    Delete,
}

fn default_selected() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Category {
    pub id: String,
    pub group: Group,
    pub name: String,
    pub summary: String,
    pub symbol: String,
    pub paths: Vec<String>,
    #[serde(default)]
    pub exclude: Vec<String>,
    #[serde(default)]
    pub min_age_days: Option<u64>,
    #[serde(default = "default_selected")]
    pub selected: bool,
    #[serde(default)]
    pub running_apps: Vec<String>,
    #[serde(default)]
    pub action: Action,
}

impl Category {
    /// Glob patterns with `~` expanded against `home`.
    pub fn expanded_paths(&self, home: &Path) -> Vec<String> {
        self.paths.iter().map(|p| expand_home(p, home)).collect()
    }

    /// File-name exclusion set.
    pub fn exclusions(&self) -> anyhow::Result<GlobSet> {
        let mut builder = GlobSetBuilder::new();
        for pattern in &self.exclude {
            builder.add(Glob::new(pattern)?);
        }
        Ok(builder.build()?)
    }

    /// True when `path` is one of this category's own glob matches and is not
    /// excluded. Used to re-validate plan items handed back by a client.
    pub fn covers(&self, path: &Path, home: &Path) -> bool {
        let excluded = self
            .exclusions()
            .map(|set| path.file_name().is_some_and(|n| set.is_match(n)))
            .unwrap_or(true);
        if excluded {
            return false;
        }
        let options = glob::MatchOptions {
            case_sensitive: true,
            require_literal_separator: true,
            require_literal_leading_dot: false,
        };
        self.expanded_paths(home).iter().any(|pattern| {
            glob::Pattern::new(pattern)
                .map(|p| p.matches_path_with(path, options))
                .unwrap_or(false)
        })
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Catalog {
    #[serde(rename = "category")]
    pub categories: Vec<Category>,
}

impl Catalog {
    pub fn builtin() -> Self {
        Self::parse(BUILTIN_CATALOG).expect("built-in catalog is valid")
    }

    pub fn parse(source: &str) -> anyhow::Result<Self> {
        let catalog: Catalog = toml::from_str(source)?;
        catalog.validate()?;
        Ok(catalog)
    }

    pub fn find(&self, id: &str) -> Option<&Category> {
        self.categories.iter().find(|c| c.id == id)
    }

    fn validate(&self) -> anyhow::Result<()> {
        let mut seen = std::collections::HashSet::new();
        for category in &self.categories {
            anyhow::ensure!(seen.insert(&category.id), "duplicate id {}", category.id);
            anyhow::ensure!(!category.paths.is_empty(), "{} has no paths", category.id);
            for path in &category.paths {
                anyhow::ensure!(
                    path.starts_with("~/"),
                    "{}: paths must be home-relative ({path})",
                    category.id
                );
                glob::Pattern::new(path)?;
            }
            category.exclusions()?;
        }
        Ok(())
    }
}

pub fn expand_home(pattern: &str, home: &Path) -> String {
    match pattern.strip_prefix("~/") {
        Some(rest) => {
            let escaped_home = glob::Pattern::escape(&home.to_string_lossy());
            format!("{escaped_home}/{rest}")
        }
        None => pattern.to_string(),
    }
}

pub fn home_dir() -> anyhow::Result<PathBuf> {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .ok_or_else(|| anyhow::anyhow!("HOME is not set to an absolute path"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builtin_catalog_parses_and_has_unique_ids() {
        let catalog = Catalog::builtin();
        assert!(catalog.categories.len() > 10);
        assert!(catalog.find("user-caches").is_some());
    }

    #[test]
    fn trash_is_the_only_delete_category() {
        let catalog = Catalog::builtin();
        let deleting: Vec<_> = catalog
            .categories
            .iter()
            .filter(|c| c.action == Action::Delete)
            .map(|c| c.id.as_str())
            .collect();
        assert_eq!(deleting, vec!["trash"]);
    }

    #[test]
    fn rejects_absolute_paths_in_catalog() {
        let source = r#"
            [[category]]
            id = "bad"
            group = "system"
            name = "Bad"
            summary = ""
            symbol = "x"
            paths = ["/System/*"]
        "#;
        assert!(Catalog::parse(source).is_err());
    }

    #[test]
    fn covers_matches_only_direct_glob_hits() {
        let catalog = Catalog::builtin();
        let caches = catalog.find("user-caches").unwrap();
        let home = Path::new("/Users/test");
        assert!(caches.covers(Path::new("/Users/test/Library/Caches/com.foo"), home));
        assert!(!caches.covers(Path::new("/Users/test/Library/Caches/com.foo/deep"), home));
        assert!(!caches.covers(Path::new("/Users/test/Library/Caches/CloudKit"), home));
        assert!(!caches.covers(Path::new("/Users/test/Documents/x"), home));
    }

    #[test]
    fn expand_home_escapes_glob_metacharacters() {
        let expanded = expand_home("~/Library/*", Path::new("/Users/a[b]"));
        assert_eq!(expanded, "/Users/a[[]b[]]/Library/*");
    }
}
