mod cli;
mod daemon;
mod gpu;
mod hotplug;
mod ipc;
mod notify;
mod state;

use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "gpu-control")]
#[command(about = "Dynamic NVIDIA GPU power control for hybrid graphics")]
#[command(version)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,

    /// Output status in JSON format (only for status command)
    #[arg(long, global = true)]
    json: bool,
}

#[derive(Subcommand)]
enum Commands {
    /// Enable the NVIDIA GPU
    On,
    /// Disable the NVIDIA GPU
    Off {
        /// Kill processes using the GPU before disabling
        #[arg(long)]
        kill: bool,
        /// Force disable even if processes are using the GPU (may cause issues)
        #[arg(long)]
        force: bool,
    },
    /// Run the hotplug monitoring daemon
    Daemon,
}

#[tokio::main]
async fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    let cli = Cli::parse();

    let result: Result<(), Box<dyn std::error::Error>> = match cli.command {
        None => cli::status(cli.json).await.map_err(|e| e.into()),
        Some(Commands::On) => cli::enable().await.map_err(|e| e.into()),
        Some(Commands::Off { kill, force }) => cli::disable(kill, force).await.map_err(|e| e.into()),
        Some(Commands::Daemon) => daemon::run().await.map_err(|e| e.into()),
    };

    if let Err(e) = result {
        log::error!("{}", e);
        std::process::exit(1);
    }
}
