//! Read-only system health snapshot for the status dashboard.

use std::path::Path;
use std::time::Instant;

use serde::Serialize;
use sysinfo::{Disks, Networks, ProcessRefreshKind, ProcessesToUpdate, System};

const TOP_PROCESS_COUNT: usize = 6;
const DATA_VOLUME: &str = "/System/Volumes/Data";

#[derive(Debug, Clone, Serialize)]
pub struct Cpu {
    pub usage: f32,
    pub cores: Vec<f32>,
    pub brand: String,
    pub load: [f64; 3],
}

#[derive(Debug, Clone, Serialize)]
pub struct Memory {
    pub total: u64,
    pub used: u64,
    pub available: u64,
    pub swap_total: u64,
    pub swap_used: u64,
}

#[derive(Debug, Clone, Serialize)]
pub struct Disk {
    pub name: String,
    pub mount: String,
    pub total: u64,
    pub available: u64,
}

#[derive(Debug, Clone, Serialize)]
pub struct Network {
    pub rx_bytes_per_sec: u64,
    pub tx_bytes_per_sec: u64,
}

#[derive(Debug, Clone, Serialize)]
pub struct Proc {
    pub pid: u32,
    pub name: String,
    pub cpu: f32,
    pub memory: u64,
}

#[derive(Debug, Clone, Serialize)]
pub struct Status {
    pub timestamp: u64,
    pub hostname: String,
    pub os_version: String,
    pub uptime_secs: u64,
    pub cpu: Cpu,
    pub memory: Memory,
    pub disk: Option<Disk>,
    pub network: Network,
    pub top: Vec<Proc>,
}

/// Holds sysinfo state between samples so rates (CPU, network) are accurate.
pub struct Monitor {
    system: System,
    networks: Networks,
    disks: Disks,
    last_sample: Instant,
}

impl Default for Monitor {
    fn default() -> Self {
        Self::new()
    }
}

impl Monitor {
    pub fn new() -> Self {
        let mut system = System::new();
        system.refresh_cpu_all();
        Self {
            system,
            networks: Networks::new_with_refreshed_list(),
            disks: Disks::new_with_refreshed_list(),
            last_sample: Instant::now(),
        }
    }

    pub fn sample(&mut self) -> Status {
        let elapsed = self.last_sample.elapsed().as_secs_f64().max(0.001);
        self.last_sample = Instant::now();
        self.system.refresh_cpu_all();
        self.system.refresh_memory();
        self.system.refresh_processes_specifics(
            ProcessesToUpdate::All,
            true,
            ProcessRefreshKind::nothing().with_cpu().with_memory(),
        );
        self.networks.refresh(true);
        self.disks.refresh(true);

        Status {
            timestamp: crate::unix_now(),
            hostname: System::host_name().unwrap_or_default(),
            os_version: System::long_os_version().unwrap_or_default(),
            uptime_secs: System::uptime(),
            cpu: self.cpu(),
            memory: self.memory(),
            disk: self.disk(),
            network: self.network(elapsed),
            top: self.top_processes(),
        }
    }

    fn cpu(&self) -> Cpu {
        let load = System::load_average();
        Cpu {
            usage: self.system.global_cpu_usage(),
            cores: self.system.cpus().iter().map(|c| c.cpu_usage()).collect(),
            brand: self
                .system
                .cpus()
                .first()
                .map(|c| c.brand().to_string())
                .unwrap_or_default(),
            load: [load.one, load.five, load.fifteen],
        }
    }

    fn memory(&self) -> Memory {
        let total = self.system.total_memory();
        let used = mach_memory_used()
            .unwrap_or_else(|| total.saturating_sub(self.system.available_memory()))
            .min(total);
        let available = total - used;
        Memory {
            total,
            used,
            available,
            swap_total: self.system.total_swap(),
            swap_used: self.system.used_swap(),
        }
    }

    fn disk(&self) -> Option<Disk> {
        let list = self.disks.list();
        let pick = list
            .iter()
            .find(|d| d.mount_point() == Path::new(DATA_VOLUME))
            .or_else(|| list.iter().find(|d| d.mount_point() == Path::new("/")))?;
        Some(Disk {
            name: pick.name().to_string_lossy().into_owned(),
            mount: pick.mount_point().to_string_lossy().into_owned(),
            total: pick.total_space(),
            available: pick.available_space(),
        })
    }

    fn network(&self, elapsed: f64) -> Network {
        let (rx, tx) = self
            .networks
            .iter()
            .filter(|(name, _)| !name.starts_with("lo"))
            .fold((0u64, 0u64), |(rx, tx), (_, data)| {
                (rx + data.received(), tx + data.transmitted())
            });
        Network {
            rx_bytes_per_sec: (rx as f64 / elapsed) as u64,
            tx_bytes_per_sec: (tx as f64 / elapsed) as u64,
        }
    }

    fn top_processes(&self) -> Vec<Proc> {
        let mut processes: Vec<Proc> = self
            .system
            .processes()
            .iter()
            .map(|(pid, p)| Proc {
                pid: pid.as_u32(),
                name: p.name().to_string_lossy().into_owned(),
                cpu: p.cpu_usage(),
                memory: p.memory(),
            })
            .collect();
        processes.sort_by(|a, b| b.cpu.total_cmp(&a.cpu));
        processes.truncate(TOP_PROCESS_COUNT);
        processes
    }
}

/// "Memory Used" as Activity Monitor defines it: app memory (anonymous pages
/// minus purgeable) + wired + compressed. sysinfo's `available_memory` reads
/// zero on recent macOS releases, so query the kernel directly.
#[cfg(target_os = "macos")]
#[allow(deprecated)] // libc marks mach_host_self deprecated in favour of the mach2 crate
fn mach_memory_used() -> Option<u64> {
    let mut stats: libc::vm_statistics64 = unsafe { std::mem::zeroed() };
    let mut count = libc::HOST_VM_INFO64_COUNT;
    // SAFETY: `stats` is a valid, writable vm_statistics64 and `count` holds
    // its size in natural_t units, as host_statistics64 requires.
    let result = unsafe {
        libc::host_statistics64(
            libc::mach_host_self(),
            libc::HOST_VM_INFO64,
            &mut stats as *mut _ as libc::host_info64_t,
            &mut count,
        )
    };
    if result != libc::KERN_SUCCESS {
        return None;
    }
    // SAFETY: sysconf has no preconditions.
    let page_size = u64::try_from(unsafe { libc::sysconf(libc::_SC_PAGESIZE) }).ok()?;
    let app = u64::from(stats.internal_page_count).saturating_sub(u64::from(stats.purgeable_count));
    let pages = app + u64::from(stats.wire_count) + u64::from(stats.compressor_page_count);
    Some(pages * page_size)
}

#[cfg(not(target_os = "macos"))]
fn mach_memory_used() -> Option<u64> {
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sample_reports_plausible_values() {
        let mut monitor = Monitor::new();
        let status = monitor.sample();
        assert!(status.memory.total > 0);
        assert!(status.memory.used <= status.memory.total);
        assert!(!status.cpu.cores.is_empty());
        assert!(status.top.len() <= TOP_PROCESS_COUNT);
    }
}
