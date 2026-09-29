//! `burrow` — command-line front end and the engine behind Burrow.app.
//!
//! With `--json` every command writes newline-delimited JSON events to stdout,
//! each tagged with a `type`, ending with a single report event. Errors are
//! reported as `{"type":"error"}` and a non-zero exit code.

mod human;

use std::io::{self, Read, Write};
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use anyhow::Context;
use burrow_core::analyze::{self, AnalyzeEvent};
use burrow_core::apps::{self, UninstallRequest};
use burrow_core::exec::{self, CleanPlan, ExecContext};
use burrow_core::scan::{self, ScanEvent, ScanOptions};
use burrow_core::sink::SystemSink;
use burrow_core::status::Monitor;
use burrow_core::{process, rules, Catalog, Guard, Sizer};
use clap::{Parser, Subcommand};
use rayon::prelude::*;
use serde::Serialize;
use serde_json::json;

const DEFAULT_SCAN_BUDGET_SECS: u64 = 120;
const DEFAULT_STATUS_INTERVAL_MS: u64 = 1000;
const MIN_STATUS_INTERVAL_MS: u64 = 250;

#[derive(Parser)]
#[command(name = "burrow", version, about = "Safe, fast macOS cleanup")]
struct Cli {
    /// Emit newline-delimited JSON events instead of human output.
    #[arg(long, global = true)]
    json: bool,
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Find reclaimable space. Read-only.
    Scan {
        /// Stop sizing after this many seconds and report partial totals.
        #[arg(long, default_value_t = DEFAULT_SCAN_BUDGET_SECS)]
        budget: u64,
    },
    /// Remove the items of a reviewed plan (JSON file, or `-` for stdin).
    Clean {
        #[arg(long)]
        plan: String,
        #[arg(long)]
        dry_run: bool,
    },
    /// List installed applications.
    Apps {
        /// Also measure each app's size (streamed as `app_size` events).
        #[arg(long)]
        sizes: bool,
    },
    /// Show files an app left in your Library.
    Leftovers {
        #[arg(long)]
        app: PathBuf,
    },
    /// Move an app and the selected leftovers to the Trash.
    Uninstall {
        #[arg(long)]
        app: String,
        #[arg(long)]
        include: Vec<String>,
        #[arg(long)]
        dry_run: bool,
    },
    /// Size every item in a folder.
    Analyze { path: Option<PathBuf> },
    /// System health snapshot.
    Status {
        /// Keep sampling until stdout closes.
        #[arg(long)]
        stream: bool,
        #[arg(long, default_value_t = DEFAULT_STATUS_INTERVAL_MS)]
        interval_ms: u64,
    },
    /// Print the cleanup catalog.
    Rules,
}

/// Serialises output so events from worker threads never interleave.
struct Out {
    json: bool,
    lock: Mutex<io::Stdout>,
}

impl Out {
    fn event<T: Serialize>(&self, value: &T) -> io::Result<()> {
        let line = serde_json::to_string(value).map_err(io::Error::other)?;
        let mut stdout = self.lock.lock().unwrap_or_else(|e| e.into_inner());
        writeln!(stdout, "{line}")?;
        stdout.flush()
    }

    /// Best-effort progress event; a closed pipe is surfaced by the final write.
    fn progress<T: Serialize>(&self, value: &T) {
        if self.json {
            let _ = self.event(value);
        }
    }
}

fn main() {
    let cli = Cli::parse();
    let out = Out {
        json: cli.json,
        lock: Mutex::new(io::stdout()),
    };
    if let Err(error) = run(cli.command, &out) {
        if out.json {
            let _ = out.event(&json!({ "type": "error", "message": format!("{error:#}") }));
        } else {
            eprintln!("burrow: {error:#}");
        }
        std::process::exit(1);
    }
}

fn run(command: Command, out: &Out) -> anyhow::Result<()> {
    let home = rules::home_dir()?;
    let guard = Guard::new(&home).context("cannot resolve home folder")?;
    match command {
        Command::Scan { budget } => cmd_scan(out, &guard, budget),
        Command::Clean { plan, dry_run } => cmd_clean(out, &guard, &plan, dry_run),
        Command::Apps { sizes } => cmd_apps(out, &guard, sizes),
        Command::Leftovers { app } => cmd_leftovers(out, &guard, &app),
        Command::Uninstall {
            app,
            include,
            dry_run,
        } => cmd_uninstall(out, &guard, UninstallRequest { app, include }, dry_run),
        Command::Analyze { path } => cmd_analyze(out, &path.unwrap_or(home)),
        Command::Status {
            stream,
            interval_ms,
        } => cmd_status(out, stream, interval_ms),
        Command::Rules => emit(out, &json!({ "type": "rules", "catalog": Catalog::builtin() }), || {
            human::rules(&Catalog::builtin())
        }),
    }
}

/// Write the final report as JSON, or run the human renderer.
fn emit<T: Serialize>(out: &Out, value: &T, human: impl FnOnce()) -> anyhow::Result<()> {
    if out.json {
        out.event(value)?;
    } else {
        human();
    }
    Ok(())
}

fn cmd_scan(out: &Out, guard: &Guard, budget: u64) -> anyhow::Result<()> {
    let catalog = Catalog::builtin();
    let options = ScanOptions {
        running: process::running_names(),
        deadline: Some(Instant::now() + Duration::from_secs(budget)),
        ..ScanOptions::default()
    };
    let report = scan::scan(&catalog, guard, &options, &|event: ScanEvent| out.progress(&event));
    emit(out, &json!({ "type": "scan_report", "report": report }), || {
        human::scan(&report)
    })
}

fn read_plan(source: &str) -> anyhow::Result<CleanPlan> {
    let mut text = String::new();
    if source == "-" {
        io::stdin().read_to_string(&mut text)?;
    } else {
        text = std::fs::read_to_string(source).with_context(|| format!("cannot read {source}"))?;
    }
    serde_json::from_str(&text).context("plan is not valid JSON")
}

fn cmd_clean(out: &Out, guard: &Guard, plan_source: &str, dry_run: bool) -> anyhow::Result<()> {
    let catalog = Catalog::builtin();
    let plan = read_plan(plan_source)?;
    let running = process::running_names();
    let context = ExecContext {
        catalog: &catalog,
        guard,
        sink: &SystemSink,
        running: &running,
        dry_run,
    };
    let report = exec::execute(&context, &plan, &|result| {
        out.progress(&json!({ "type": "item", "result": result }));
    });
    emit(out, &json!({ "type": "clean_report", "report": report }), || {
        human::clean(&report)
    })
}

fn cmd_apps(out: &Out, guard: &Guard, sizes: bool) -> anyhow::Result<()> {
    let list = apps::list_apps(guard.home(), &process::running_names());
    if !out.json {
        human::apps(&list);
        return Ok(());
    }
    out.event(&json!({ "type": "apps", "apps": list }))?;
    if sizes {
        let sizer = Sizer::default();
        list.par_iter().for_each(|app| {
            let size = sizer.measure(std::path::Path::new(&app.path));
            out.progress(&json!({ "type": "app_size", "path": app.path, "bytes": size.bytes }));
        });
    }
    out.event(&json!({ "type": "done" }))?;
    Ok(())
}

fn cmd_leftovers(out: &Out, guard: &Guard, app: &std::path::Path) -> anyhow::Result<()> {
    let info: plist::Dictionary = plist::from_file(app.join("Contents/Info.plist"))
        .with_context(|| format!("cannot read {}", app.display()))?;
    let bundle_id = info
        .get("CFBundleIdentifier")
        .and_then(|v| v.as_string())
        .unwrap_or_default();
    let name = app
        .file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();
    let items = apps::find_leftovers(guard, bundle_id, &name);
    emit(out, &json!({ "type": "leftovers", "app": app, "items": items }), || {
        human::leftovers(&items)
    })
}

fn cmd_uninstall(out: &Out, guard: &Guard, request: UninstallRequest, dry_run: bool) -> anyhow::Result<()> {
    let running = process::running_names();
    let report = apps::uninstall(guard, &SystemSink, &running, &request, dry_run)
        .map_err(|reason| anyhow::anyhow!(reason))?;
    emit(out, &json!({ "type": "uninstall_report", "report": report }), || {
        human::uninstall(&report)
    })
}

fn cmd_analyze(out: &Out, path: &std::path::Path) -> anyhow::Result<()> {
    let report = analyze::analyze(path, None, &|event: AnalyzeEvent| out.progress(&event))?;
    emit(out, &json!({ "type": "analyze_report", "report": report }), || {
        human::analyze(&report)
    })
}

fn cmd_status(out: &Out, stream: bool, interval_ms: u64) -> anyhow::Result<()> {
    let interval = Duration::from_millis(interval_ms.max(MIN_STATUS_INTERVAL_MS));
    let mut monitor = Monitor::new();
    // The first CPU sample needs a baseline interval to be meaningful.
    std::thread::sleep(sysinfo::MINIMUM_CPU_UPDATE_INTERVAL);
    loop {
        let status = monitor.sample();
        let value = json!({ "type": "status", "status": status });
        if out.json {
            if out.event(&value).is_err() {
                return Ok(()); // client went away
            }
        } else {
            human::status(&status);
        }
        if !stream {
            return Ok(());
        }
        std::thread::sleep(interval);
    }
}
