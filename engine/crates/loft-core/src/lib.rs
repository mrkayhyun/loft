//! Loft engine: scanning, sizing and safe removal for macOS.
//!
//! The engine never removes anything it did not first put into a plan, and it
//! re-validates every plan item (rule match, guard, file identity) at the sink.

pub mod analyze;
pub mod apps;
pub mod exec;
pub mod guard;
pub mod process;
pub mod rules;
pub mod scan;
pub mod sink;
pub mod size;
pub mod status;

pub use guard::{Guard, GuardError};
pub use rules::{Action, Catalog, Category, Group};
pub use size::{Size, Sizer};

/// Seconds since the Unix epoch, used for report timestamps.
pub fn unix_now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}
